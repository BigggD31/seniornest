// Google Play subscription verification -- the Android counterpart of
// apple-subscription-webhook. verify_jwt = false (Google Pub/Sub sends no
// Supabase token); every request is authenticated below instead.
//
// Two ways in:
//  1. Google Play Real-time Developer Notifications (RTDN), delivered by a
//     Pub/Sub PUSH subscription to:
//       https://<project>.supabase.co/functions/v1/google-play-subscriptions?token=<PUBSUB_VERIFICATION_TOKEN>
//     Sent on every purchase, renewal, cancellation, expiry, hold, refund...
//  2. The Android app, right after a purchase (SubscriptionRecorder), with the
//     signed-in user's Supabase token and { purchase_token, product_id }.
//
// Either way the notification is only a trigger: the real state is always
// fetched from the Google Play Developer API (purchases.subscriptionsv2), so a
// late, repeated or out-of-order notification can never apply stale data.
//
// The Play purchase token is stored in subscriptions.original_transaction_id
// (written by the app). Rows are matched on it; lifetime/VIP rows are never
// touched. No extra tables are needed.
//
// Secrets required:
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  service account key (JSON) with access to
//                                     the app in Play Console (View financial
//                                     data + Manage orders and subscriptions)
//   PUBSUB_VERIFICATION_TOKEN         long random string, also put in the
//                                     Pub/Sub push URL above
//   GOOGLE_PLAY_PACKAGE_NAME          optional, defaults to com.devonmurphy.seniornest
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ??
  "com.devonmurphy.seniornest";
const pubsubToken = Deno.env.get("PUBSUB_VERIFICATION_TOKEN") ?? "";
const serviceAccountJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "";

// RTDN subscriptionNotification.notificationType values that mean the
// subscription was revoked (refund / revoke from Play Console).
const SUBSCRIPTION_REVOKED = 12;

// subscriptionsv2 states that still give access until the expiry time.
// CANCELED = auto-renew turned off, but paid-through time still applies.
const ACCESS_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED",
]);

// ── Google OAuth (service account -> access token) ────────────────────────
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);
  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${
    encode({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  }`;
  const pemBody = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const encodedSig = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${encodedSig}`,
    }),
  });
  const json = await resp.json();
  if (!resp.ok) throw new Error(`OAuth token exchange failed: ${JSON.stringify(json)}`);
  cachedAccessToken = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return json.access_token;
}

const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

// Returns null when Google says the token doesn't exist (not ours / bogus).
async function fetchSubscription(purchaseToken: string): Promise<any | null> {
  const resp = await fetch(
    `${API}/${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: { Authorization: `Bearer ${await getAccessToken()}` } },
  );
  if (resp.status === 404 || resp.status === 410) return null;
  if (!resp.ok) throw new Error(`subscriptionsv2.get ${resp.status}: ${await resp.text()}`);
  return await resp.json();
}

// Safety net: the app acknowledges via completePurchase, but Google refunds
// anything left unacknowledged for 3 days, so acknowledge here too if needed.
async function acknowledgeIfNeeded(sub: any, purchaseToken: string) {
  if (sub.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_PENDING") return;
  const productId = sub.lineItems?.[0]?.productId;
  if (!productId) return;
  const resp = await fetch(
    `${API}/${packageName}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${
      encodeURIComponent(purchaseToken)
    }:acknowledge`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await getAccessToken()}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    },
  );
  if (!resp.ok) console.error(`acknowledge failed ${resp.status}: ${await resp.text()}`);
}

// ── Apply Google's state to the app's subscription rows ───────────────────
async function applyToken(
  purchaseToken: string,
  opts: { revoked?: boolean; onlyUserId?: string; source: string },
) {
  const sub = await fetchSubscription(purchaseToken);
  if (!sub) {
    console.log(`google-play-subscriptions: unknown token (${opts.source}), ignored`);
    return;
  }

  // An upgrade/downgrade/resubscribe issues a NEW token that replaces the old
  // one: carry existing rows over so they keep tracking the live purchase.
  if (sub.linkedPurchaseToken) {
    let move = supabase
      .from("subscriptions")
      .update({ original_transaction_id: purchaseToken, updated_at: new Date().toISOString() })
      .eq("original_transaction_id", sub.linkedPurchaseToken)
      .neq("status", "lifetime");
    if (opts.onlyUserId) move = move.eq("user_id", opts.onlyUserId);
    const { error } = await move;
    if (error) throw error;
  }

  const state = String(sub.subscriptionState ?? "");
  if (state === "SUBSCRIPTION_STATE_PENDING") {
    // Payment not completed yet (e.g. pending cash payment): change nothing.
    console.log(`google-play-subscriptions: pending payment (${opts.source})`);
    return;
  }

  const expiryMs = Math.max(
    0,
    ...(sub.lineItems ?? []).map((li: any) => Date.parse(li.expiryTime ?? "") || 0),
  );
  const now = Date.now();
  let status: string;
  let expiresAt: string | null;
  if (opts.revoked) {
    status = "revoked";
    expiresAt = new Date(now).toISOString();
  } else {
    const hasAccess = ACCESS_STATES.has(state) && expiryMs > now;
    status = hasAccess ? "active" : "expired";
    expiresAt = expiryMs > 0 ? new Date(expiryMs).toISOString() : new Date(now).toISOString();
  }

  // Same as the Apple webhook: Google is the source of truth, never touch
  // lifetime/VIP rows.
  let update = supabase
    .from("subscriptions")
    .update({ expires_at: expiresAt, status, updated_at: new Date().toISOString() })
    .eq("original_transaction_id", purchaseToken)
    .neq("status", "lifetime");
  if (opts.onlyUserId) update = update.eq("user_id", opts.onlyUserId);
  const { error } = await update;
  if (error) throw error;

  if (status === "active") await acknowledgeIfNeeded(sub, purchaseToken);

  console.log(
    `google-play-subscriptions ok (${opts.source}): ${sub.lineItems?.[0]?.productId} ` +
      `${state} -> ${status} until ${expiresAt}${sub.testPurchase ? " [test purchase]" : ""}`,
  );
}

// ── Entry point ───────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  try {
    const url = new URL(req.url);
    const body = await req.json();

    // 1) Pub/Sub push (Google Play RTDN)
    if (body?.message) {
      if (!pubsubToken || url.searchParams.get("token") !== pubsubToken) {
        return new Response("forbidden", { status: 403 });
      }
      const raw = body.message.data ? atob(body.message.data) : "{}";
      const note = JSON.parse(raw);
      if (note.packageName && note.packageName !== packageName) {
        console.error(`wrong package: ${note.packageName}`);
        return new Response("ok", { status: 200 }); // not ours; don't retry
      }
      if (note.testNotification) {
        console.log("google-play-subscriptions: test notification received");
        return new Response("ok", { status: 200 });
      }
      if (note.subscriptionNotification?.purchaseToken) {
        const n = note.subscriptionNotification;
        await applyToken(n.purchaseToken, {
          revoked: Number(n.notificationType) === SUBSCRIPTION_REVOKED,
          source: `rtdn type ${n.notificationType}`,
        });
      } else if (note.voidedPurchaseNotification?.purchaseToken) {
        // Refunded / charged back. productType 1 = subscription.
        const v = note.voidedPurchaseNotification;
        if (Number(v.productType) === 1) {
          await applyToken(v.purchaseToken, { revoked: true, source: "voided" });
        }
      }
      return new Response("ok", { status: 200 });
    }

    // 2) The Android app, right after a purchase
    const purchaseToken = body?.purchase_token;
    if (typeof purchaseToken !== "string" || !purchaseToken) {
      return new Response("bad request", { status: 400 });
    }
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
    if (userError || !userData?.user) return new Response("unauthorized", { status: 401 });

    await applyToken(purchaseToken, { onlyUserId: userData.user.id, source: "app" });
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("google-play-subscriptions error:", e);
    // Non-2xx so Pub/Sub retries genuine notifications later.
    return new Response("error", { status: 500 });
  }
});

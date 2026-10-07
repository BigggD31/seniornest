// Apple App Store Server Notifications V2 webhook. verify_jwt = false (Apple sends no Supabase token).
// Secrets required: APPLE_BUNDLE_ID, APPLE_APP_ID, APPLE_ROOT_CA_G3_B64.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Every payload is a signed JWS; it is only trusted after its certificate
// chain verifies up to the pinned Apple Root CA G3 (see verify.ts). Oct 7 2026:
// replaced @apple/app-store-server-library, which fails on Supabase's Deno
// runtime (crypto.X509Certificate.toString is not implemented there).
import { Buffer } from "node:buffer";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAppleJws } from "./verify.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const bundleId = Deno.env.get("APPLE_BUNDLE_ID")!;
const appAppleId = Number(Deno.env.get("APPLE_APP_ID"));
const rootCa = new Uint8Array(
  Buffer.from(Deno.env.get("APPLE_ROOT_CA_G3_B64")!, "base64"),
);

// Notification types that mean "access ends now / is gone".
const ENDED = new Set(["EXPIRED", "GRACE_PERIOD_EXPIRED", "REVOKE", "REFUND"]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  try {
    const { signedPayload } = await req.json();
    if (!signedPayload) return new Response("bad request", { status: 400 });

    const note = await verifyAppleJws(signedPayload, rootCa);

    const data = note.data;
    if (!data) return new Response("ok", { status: 200 }); // nothing to apply
    if (data.bundleId !== bundleId) throw new Error("wrong bundle id");
    const env = String(data.environment); // "Sandbox" | "Production"
    if (env === "Production" && Number(data.appAppleId) !== appAppleId) {
      throw new Error("wrong app id");
    }

    const signedTx = data.signedTransactionInfo;
    if (!signedTx) return new Response("ok", { status: 200 }); // e.g. TEST ping

    const tx = await verifyAppleJws(signedTx, rootCa);
    if (tx.bundleId !== bundleId) throw new Error("wrong bundle id (tx)");
    const originalId = tx.originalTransactionId;
    if (!originalId) return new Response("ok", { status: 200 });

    const type = String(note.notificationType);
    const expiresMs = tx.expiresDate ?? null;
    const revoked = tx.revocationDate != null;
    const expiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;
    const ended = ENDED.has(type) || revoked ||
      (expiresMs != null && expiresMs <= Date.now());
    const status = revoked ? "revoked" : ended ? "expired" : "active";

    // Idempotent: Apple retries, and may deliver out of order. Never let an
    // older notification overwrite a newer expiry.
    const { data: prior } = await supabase
      .from("apple_subscription_state")
      .select("expires_at")
      .eq("original_transaction_id", originalId)
      .maybeSingle();
    if (
      prior?.expires_at && expiresAt && !revoked &&
      new Date(prior.expires_at) > new Date(expiresAt)
    ) {
      return new Response("ok", { status: 200 });
    }

    const { error: upsertError } = await supabase
      .from("apple_subscription_state")
      .upsert({
        original_transaction_id: originalId,
        product_id: tx.productId,
        expires_at: expiresAt,
        status,
        environment: env,
        last_notification_type: type,
        last_notification_uuid: note.notificationUUID,
        updated_at: new Date().toISOString(),
      });
    if (upsertError) throw upsertError;

    // Apply to the app's own subscription rows (never touches lifetime/VIP).
    const { error: updateError } = await supabase
      .from("subscriptions")
      .update({
        original_transaction_id: originalId,
        expires_at: expiresAt,
        status,
        updated_at: new Date().toISOString(),
      })
      .neq("status", "lifetime")
      .or(`original_transaction_id.eq.${originalId},transaction_id.eq.${originalId}`);
    if (updateError) throw updateError;

    console.log(`apple-subscription-webhook ok: ${type} ${env} ${tx.productId} -> ${status}`);
    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("apple-subscription-webhook error:", e);
    // Verification failures must not look like success; Apple will retry
    // genuine notifications.
    return new Response("rejected", { status: 400 });
  }
});

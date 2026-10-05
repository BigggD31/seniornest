// DRAFT -- NOT DEPLOYED. Needs: verify_jwt = false (Apple sends no Supabase
// token), and these secrets set in Supabase:
//   APPLE_BUNDLE_ID        e.g. com.devonmurphy.seniornest
//   APPLE_APP_ID           numeric Apple ID from App Store Connect > App Information
//   APPLE_ROOT_CA_G3_B64   base64 of AppleRootCA-G3.cer (from apple.com/certificateauthority)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Receives App Store Server Notifications V2. Every payload is a signed JWS;
// it is only trusted after its certificate chain verifies up to Apple's root.
// Unverified requests are rejected and change nothing.
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@1";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const bundleId = Deno.env.get("APPLE_BUNDLE_ID")!;
const appAppleId = Number(Deno.env.get("APPLE_APP_ID"));
const rootCa = Buffer.from(Deno.env.get("APPLE_ROOT_CA_G3_B64")!, "base64");

function verifierFor(env: Environment) {
  // Sandbox (TestFlight) notifications have no appAppleId requirement.
  return new SignedDataVerifier(
    [rootCa],
    true,
    env,
    bundleId,
    env === Environment.PRODUCTION ? appAppleId : undefined,
  );
}

// Notification types that mean "access ends now / is gone".
const ENDED = new Set(["EXPIRED", "GRACE_PERIOD_EXPIRED", "REVOKE", "REFUND"]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  try {
    const { signedPayload } = await req.json();
    if (!signedPayload) return new Response("bad request", { status: 400 });

    // Try Production first, then Sandbox (TestFlight sends Sandbox).
    let note;
    let env = Environment.PRODUCTION;
    try {
      note = await verifierFor(Environment.PRODUCTION)
        .verifyAndDecodeNotification(signedPayload);
    } catch (_) {
      env = Environment.SANDBOX;
      note = await verifierFor(Environment.SANDBOX)
        .verifyAndDecodeNotification(signedPayload);
    }

    const signedTx = note.data?.signedTransactionInfo;
    if (!signedTx) return new Response("ok", { status: 200 }); // e.g. TEST ping

    const tx = await verifierFor(env).verifyAndDecodeTransaction(signedTx);
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

    await supabase.from("apple_subscription_state").upsert({
      original_transaction_id: originalId,
      product_id: tx.productId,
      expires_at: expiresAt,
      status,
      environment: env,
      last_notification_type: type,
      last_notification_uuid: note.notificationUUID,
      updated_at: new Date().toISOString(),
    });

    // Apply to the app's own subscription rows (never touches lifetime/VIP).
    await supabase
      .from("subscriptions")
      .update({
        original_transaction_id: originalId,
        expires_at: expiresAt,
        status,
        updated_at: new Date().toISOString(),
      })
      .neq("status", "lifetime")
      .or(`original_transaction_id.eq.${originalId},transaction_id.eq.${originalId}`);

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("apple-subscription-webhook error:", e);
    // Verification failures must not look like success; Apple will retry
    // genuine notifications.
    return new Response("rejected", { status: 400 });
  }
});

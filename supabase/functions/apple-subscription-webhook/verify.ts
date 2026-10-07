import * as x509 from "npm:@peculiar/x509@1";

const LEAF_OID = "1.2.840.113635.100.6.11.1"; // Apple "Mac App Store Receipt Signing" marker (leaf)
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1"; // Apple "WWDR" marker (intermediate)

function b64urlToBytes(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
function b64ToBytes(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

// Verifies an Apple-signed JWS (ES256) against a pinned Apple root cert and
// returns the decoded payload. Throws on ANY failure -- callers must treat a
// throw as "not from Apple".
export async function verifyAppleJws(
  jws: string,
  pinnedRootDer: Uint8Array,
): Promise<any> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
  if (header.alg !== "ES256") throw new Error("unexpected alg");
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== 3) throw new Error("bad x5c");

  const leaf = new x509.X509Certificate(b64ToBytes(x5c[0]));
  const inter = new x509.X509Certificate(b64ToBytes(x5c[1]));
  const root = new x509.X509Certificate(pinnedRootDer);

  // Chain: leaf signed by intermediate, intermediate signed by OUR pinned root.
  if (!(await inter.verify({ publicKey: root.publicKey, signatureOnly: true }))) {
    throw new Error("intermediate not signed by pinned Apple root");
  }
  if (!(await leaf.verify({ publicKey: inter.publicKey, signatureOnly: true }))) {
    throw new Error("leaf not signed by intermediate");
  }
  if (!leaf.getExtension(LEAF_OID)) throw new Error("leaf missing Apple marker");
  if (!inter.getExtension(INTERMEDIATE_OID)) {
    throw new Error("intermediate missing Apple marker");
  }

  // The JWS signature itself, made by the leaf certificate's key.
  const key = await crypto.subtle.importKey(
    "spki",
    new Uint8Array(leaf.publicKey.rawData),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(parts[0] + "." + parts[1]),
  );
  if (!ok) throw new Error("bad JWS signature");

  const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));

  // Certificates must have been valid when Apple signed this.
  const at = new Date(typeof payload.signedDate === "number" ? payload.signedDate : Date.now());
  for (const c of [leaf, inter, root]) {
    if (at < c.notBefore || at > c.notAfter) throw new Error("certificate not valid at signing time");
  }
  return payload;
}

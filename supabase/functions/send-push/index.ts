// Sends one notification to the person's registered devices through Firebase Cloud Messaging (v1).
// Called by the database trigger on notifications. Requires FIREBASE_SERVICE_ACCOUNT
// and FIREBASE_PROJECT_ID as function secrets. The caller proves itself with the database-held webhook secret.
import { createClient } from "jsr:@supabase/supabase-js@2";

const encoder = new TextEncoder();
let cachedGoogleToken: { value: string; expiresAt: number } | null = null;

async function sameSecret(a: string, b: string): Promise<boolean> {
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const x = new Uint8Array(left);
  const y = new Uint8Array(right);
  let difference = 0;
  for (let i = 0; i < x.length; i++) difference |= x[i] ^ y[i];
  return difference === 0;
}

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string"
    ? encoder.encode(data)
    : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(
  account: { client_email: string; private_key: string },
): Promise<string> {
  if (cachedGoogleToken && cachedGoogleToken.expiresAt > Date.now()) {
    return cachedGoogleToken.value;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(
    /\s+/g,
    "",
  );
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(`${header}.${claims}`),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token request failed: ${response.status}`);
  }
  const result = await response.json();
  cachedGoogleToken = {
    value: result.access_token,
    expiresAt: Date.now() + Math.max(0, (result.expires_in - 60) * 1000),
  };
  return cachedGoogleToken.value;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!req.headers.get("x-push-secret")) {
    return new Response("Forbidden", { status: 403 });
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: secret, error: secretError } = await db.rpc(
    "push_webhook_secret",
  );
  if (secretError) return new Response("Secret lookup failed", { status: 500 });
  if (!secret || !await sameSecret(secret, req.headers.get("x-push-secret")!)) {
    return new Response("Forbidden", { status: 403 });
  }
  let notification_id: unknown;
  try {
    ({ notification_id } = await req.json());
  } catch (_) {
    return new Response("Invalid JSON", { status: 400 });
  }
  if (
    typeof notification_id !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      notification_id,
    )
  ) {
    return new Response("Invalid notification ID", { status: 400 });
  }

  const { data: note } = await db.from("notifications").select(
    "venue_id, user_id, title, body, event_id, kind, conversation_id",
  ).eq("id", notification_id).maybeSingle();
  if (!note) return new Response("Not found", { status: 404 });
  const { data: membership, error: membershipError } = await db.from(
    "venue_memberships",
  )
    .select("status").eq("venue_id", note.venue_id).eq("user_id", note.user_id)
    .maybeSingle();
  if (membershipError) {
    return new Response("Membership lookup failed", { status: 500 });
  }
  if (membership?.status !== "active") {
    return new Response("Inactive member", { status: 200 });
  }
  const { data: tokens, error: tokenError } = await db.rpc(
    "push_device_tokens",
    { p_user: note.user_id },
  );
  if (tokenError) return new Response("Device lookup failed", { status: 500 });
  if (!tokens?.length) return new Response("No devices", { status: 200 });

  const account = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const bearer = await accessToken(account);

  let sent = 0;
  for (const { token } of tokens) {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: note.title, body: note.body },
            data: {
              kind: note.kind ?? "",
              event_id: note.event_id ?? "",
              conversation_id: note.conversation_id ?? "",
            },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (response.ok) {
      sent++;
    } else if (response.status === 404) {
      // The device is gone or the token is invalid. Stop pushing to it.
      await db.from("device_tokens").delete().eq("token", token);
    } else {
      // Firebase explains a refusal in the body (for example a sender ID mismatch, or a
      // missing APNs key for iOS). It names the error, never the device token.
      console.error(
        "FCM send failed",
        response.status,
        (await response.text()).slice(0, 500),
      );
    }
  }
  return new Response(JSON.stringify({ sent }), { status: 200 });
});

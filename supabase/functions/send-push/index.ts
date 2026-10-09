// Sends one notification to the person's registered devices through Firebase Cloud Messaging (v1).
// Called by the database trigger on notifications. Requires FIREBASE_SERVICE_ACCOUNT
// and FIREBASE_PROJECT_ID as function secrets. The caller proves itself with the database-held webhook secret.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const encoder = new TextEncoder();

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === 'string' ? encoder.encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function accessToken(account: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const pem = account.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(`${header}.${claims}`));
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  if (!response.ok) throw new Error(`Google token request failed: ${response.status}`);
  return (await response.json()).access_token;
}

Deno.serve(async (req) => {
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: secret } = await db.rpc('push_webhook_secret');
  if (!secret || req.headers.get('x-push-secret') !== secret) {
    return new Response('Forbidden', { status: 403 });
  }
  const { notification_id } = await req.json();

  const { data: note } = await db.from('notifications').select('user_id, title, body, event_id, kind').eq('id', notification_id).maybeSingle();
  if (!note) return new Response('Not found', { status: 404 });
  const { data: tokens } = await db.from('device_tokens').select('token').eq('user_id', note.user_id);
  if (!tokens?.length) return new Response('No devices', { status: 200 });

  const account = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')!;
  const bearer = await accessToken(account);

  let sent = 0;
  for (const { token } of tokens) {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: note.title, body: note.body },
          data: { kind: note.kind ?? '', event_id: note.event_id ?? '' },
          apns: { payload: { aps: { sound: 'default' } } },
        },
      }),
    });
    if (response.ok) {
      sent++;
    } else if (response.status === 404) {
      // The device is gone or the token is invalid. Stop pushing to it.
      await db.from('device_tokens').delete().eq('token', token);
    }
  }
  return new Response(JSON.stringify({ sent }), { status: 200 });
});

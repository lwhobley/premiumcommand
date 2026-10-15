// Shared rules for staff PINs and sign-in locks. The Dart client applies the same PIN rules
// (lib/features/staff/domain/staff_profile.dart) so mistakes are caught before a request.
//
// A PIN is never stored. pinFingerprint() keys it with STAFF_PIN_SECRET, which exists only as
// a function secret. Anyone who reads the database sees fingerprints, and recovering a PIN
// from one needs that secret as well.

const encoder = new TextEncoder();

// Four digits with an obvious pattern are easy to guess, so they are refused.
const WEAK_PINS = new Set(["0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777",
  "8888", "9999", "1234", "4321", "1212", "2580"]);

// Failed PIN sign-ins allowed before a lock, and how long the lock lasts.
// A device is one install of the app. Addresses are shared by everyone on one network,
// so the address limit is higher to keep one wrong entry at a venue from locking everyone.
export const DEVICE_MAX_FAILURES = 5;
export const ADDRESS_MAX_FAILURES = 30;
export const LOCK_MINUTES = 15;

export function isValidPin(pin: unknown): pin is string {
  return typeof pin === "string" && /^[0-9]{4}$/.test(pin) && !WEAK_PINS.has(pin);
}

export function isValidEmployeeId(id: unknown): id is string {
  return typeof id === "string" && /^[A-Z0-9-]{3,20}$/.test(id);
}

export function isValidDeviceId(id: unknown): id is string {
  return typeof id === "string" && /^[A-Za-z0-9-]{16,64}$/.test(id);
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function pinFingerprint(pin: string): Promise<string> {
  const secret = Deno.env.get("STAFF_PIN_SECRET");
  if (!secret || secret.length < 32) {
    throw new Error("STAFF_PIN_SECRET is not configured");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(`pin:${pin}`));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Compares two hex strings without stopping at the first difference.
export function sameFingerprint(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

// Lock keys for one sign-in attempt. The raw device ID and address are never stored.
export async function lockKeys(deviceId: string, address: string | null): Promise<{
  device: string;
  address: string | null;
}> {
  return {
    device: `device:${await sha256Hex(`device:${deviceId}`)}`,
    address: address ? `ip:${await sha256Hex(`ip:${address}`)}` : null,
  };
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

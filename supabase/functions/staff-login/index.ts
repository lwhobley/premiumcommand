// Staff PIN-only sign-in. Takes a 4-digit PIN and this install's device ID. When the PIN matches
// an active staff account, it returns a one-time token hash that the app exchanges for a session.
//
// Attempts are limited per device and per network address, not per account, because a PIN alone
// cannot be tied to an account until it matches. Each attempt reserves a slot in the database
// before the PIN is checked, so parallel requests cannot get past the limit: 5 per device and 30
// per address in 15 minutes. A correct PIN gives the slots back. Locks clear on their own.
//
// Deploy without JWT verification: a person signing in has no token yet.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  ADDRESS_MAX_FAILURES,
  DEVICE_MAX_FAILURES,
  LOCK_MINUTES,
  corsHeaders,
  isValidDeviceId,
  isValidPin,
  json,
  lockKeys,
  pinFingerprint,
} from "../_shared/staff_pin.ts";

const WRONG = "That PIN is not recognized.";
const LOCKED = `Too many incorrect PINs. Try again in ${LOCK_MINUTES} minutes.`;
const UNAVAILABLE = "Sign-in is unavailable. Try again.";

// The caller's address as set by the platform, never a value the caller can choose. Cloudflare
// overwrites cf-connecting-ip; otherwise use the last X-Forwarded-For entry, which our own
// infrastructure appends, not the first, which the caller can send.
function clientAddress(req: Request): string | null {
  const cloudflare = req.headers.get("cf-connecting-ip")?.trim();
  if (cloudflare) return cloudflare;
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const forwarded = req.headers.get("x-forwarded-for")
    ?.split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  return forwarded && forwarded.length > 0 ? forwarded[forwarded.length - 1] : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { pin?: unknown; device_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Enter your 4-digit PIN." }, 400);
  }
  const pin = typeof body.pin === "string" ? body.pin : "";
  if (!isValidPin(pin)) return json({ error: "Enter your 4-digit PIN." }, 400);
  if (!isValidDeviceId(body.device_id)) {
    return json({ error: "This device could not be identified. Update the app and try again." }, 400);
  }

  const keys = await lockKeys(body.device_id, clientAddress(req));
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  async function takeAttempt(key: string, max: number): Promise<boolean> {
    const { data, error } = await admin.rpc("staff_login_take_attempt", {
      p_key: key,
      p_max: max,
      p_lock_minutes: LOCK_MINUTES,
    });
    if (error) throw error;
    return data === true;
  }

  try {
    // Reserve the attempt before looking at the PIN.
    if (!(await takeAttempt(keys.device, DEVICE_MAX_FAILURES))) {
      return json({ error: LOCKED, code: "locked" }, 423);
    }
    if (keys.address && !(await takeAttempt(keys.address, ADDRESS_MAX_FAILURES))) {
      return json({ error: LOCKED, code: "locked" }, 423);
    }

    const fingerprint = await pinFingerprint(pin);
    const { data: match, error: matchError } = await admin
      .from("staff_pins")
      .select("profile_id, venue_id, staff_profiles!inner(user_id, status)")
      .eq("pin_fingerprint", fingerprint)
      .maybeSingle();
    if (matchError) return json({ error: UNAVAILABLE }, 503);

    const profile = match?.staff_profiles as { user_id: string; status: string } | undefined;
    // Only an active account can sign in. Inactive accounts count as wrong, so the response
    // does not reveal that the PIN belongs to someone.
    if (!match || !profile || profile.status !== "active") {
      await admin.from("audit_logs").insert({
        venue_id: match?.venue_id ?? null,
        action: "staff.login_failed",
        entity: "staff_login",
        details: {},
      });
      return json({ error: WRONG }, 401);
    }

    // A correct PIN gives the attempts back.
    await admin.rpc("staff_login_release", { p_key: keys.device, p_clear: true });
    if (keys.address) {
      await admin.rpc("staff_login_release", { p_key: keys.address, p_clear: false });
    }

    const { data: userData, error: userError } = await admin.auth.admin.getUserById(profile.user_id);
    const email = userData?.user?.email;
    if (userError || !email) return json({ error: UNAVAILABLE }, 503);

    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    const tokenHash = link?.properties?.hashed_token;
    if (linkError || !tokenHash) return json({ error: UNAVAILABLE }, 503);

    await admin.from("audit_logs").insert({
      venue_id: match.venue_id,
      action: "staff.signed_in",
      entity: "staff_profile",
      entity_id: match.profile_id,
      details: {},
    });

    return json({ token_hash: tokenHash });
  } catch (error) {
    console.error("staff-login failed", error);
    return json({ error: UNAVAILABLE }, 503);
  }
});

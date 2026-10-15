// Administrator actions for staff accounts that need the auth service: creating the account,
// setting a PIN, deactivating or reactivating, and removing a person.
//
// Every request runs first as the signed-in administrator. The database functions then check
// manage_configuration again, so a caller without access fails before any auth account changes.
// Only after that does this function use the service role to create, ban, or delete the account.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  isValidEmployeeId,
  isValidPin,
  json,
  pinFingerprint,
} from "../_shared/staff_pin.ts";

// Staff accounts get only these roles. Other roles stay with managers under Administration.
const ROLE_CODES = ["suite_attendant", "runner", "beverage_lead"];
// A banned account cannot refresh its session. Access is already blocked by membership status.
const BAN_FOREVER = "876000h";

type Body = {
  action?: string;
  venue_id?: string;
  profile_id?: string;
  fields?: Record<string, unknown>;
  roles?: unknown;
  pin?: unknown;
  active?: unknown;
};

function clientFor(url: string, key: string, authHeader: string): SupabaseClient {
  return createClient(url, key, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// Maps database errors to messages an administrator can act on.
function friendly(error: { code?: string; message?: string }): { message: string; status: number } {
  const text = error.message ?? "";
  if (error.code === "42501") return { message: "You do not have permission to do that.", status: 403 };
  if (error.code === "23505") {
    if (text.includes("pin")) return { message: "That PIN is already used by another staff member. Choose a different PIN.", status: 409 };
    if (text.includes("employee_id")) return { message: "That employee ID already exists.", status: 409 };
    return { message: "That staff member already exists.", status: 409 };
  }
  if (error.code === "40001") return { message: text, status: 409 };
  if (error.code === "P0002") return { message: "That staff member was not found.", status: 404 };
  if (error.code === "22023") return { message: text, status: 400 };
  return { message: text || "The request failed.", status: 400 };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Sign in to manage staff." }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Send a JSON request." }, 400);
  }

  const user = clientFor(url, anonKey, authHeader);
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    switch (body.action) {
      case "create":
        return await createStaff(user, admin, body);
      case "set_pin":
        return await setPin(user, body);
      case "set_status":
        return await setStatus(user, admin, body);
      case "remove":
        return await removeStaff(user, admin, body);
      default:
        return json({ error: "Unknown action." }, 400);
    }
  } catch (error) {
    console.error("staff-admin failed", error);
    return json({ error: "The request failed. Try again." }, 500);
  }
});

async function createStaff(user: SupabaseClient, admin: SupabaseClient, body: Body): Promise<Response> {
  const venueId = body.venue_id;
  const fields = body.fields ?? {};
  const employeeId = typeof fields.employee_id === "string" ? fields.employee_id.trim().toUpperCase() : "";
  if (typeof venueId !== "string") return json({ error: "Choose a venue." }, 400);
  if (!isValidEmployeeId(employeeId)) {
    return json({ error: "Employee ID must be 3 to 20 letters, digits, or hyphens." }, 400);
  }
  if (!isValidPin(body.pin)) {
    return json({ error: "PIN must be 4 digits and not an obvious pattern such as 1234." }, 400);
  }
  if (!Array.isArray(body.roles) || body.roles.length === 0 ||
      !body.roles.every((r) => typeof r === "string" && ROLE_CODES.includes(r))) {
    return json({ error: "Choose at least one role for this staff member." }, 400);
  }

  const { data: allowed, error: allowedError } = await user.rpc("staff_can_manage", { p_venue: venueId });
  if (allowedError) return json(friendly(allowedError), friendly(allowedError).status);
  if (!allowed) return json({ error: "Only administrators can add staff." }, 403);

  const fingerprint = await pinFingerprint(body.pin);

  // The sign-in account has no password and no real mailbox. The person signs in with the PIN.
  // The address is random, not built from the employee ID, so an ID can be changed or reused
  // without colliding with an old account.
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: `staff-${crypto.randomUUID()}@staff.cutx.invalid`,
    email_confirm: true,
    user_metadata: { staff: true },
  });
  if (createError || !created.user) {
    return json({ error: "The account could not be created. Try again." }, 500);
  }

  const { data: profileId, error: rpcError } = await user.rpc("staff_create_profile", {
    p_venue: venueId,
    p_user: created.user.id,
    p_fields: fields,
    p_roles: body.roles,
    p_pin_fingerprint: fingerprint,
  });
  if (rpcError) {
    // Undo the account so the employee ID can be tried again.
    await admin.auth.admin.deleteUser(created.user.id);
    const mapped = friendly(rpcError);
    return json({ error: mapped.message }, mapped.status);
  }
  return json({ id: profileId }, 201);
}

async function setPin(user: SupabaseClient, body: Body): Promise<Response> {
  if (typeof body.profile_id !== "string") return json({ error: "Choose a staff member." }, 400);
  if (!isValidPin(body.pin)) {
    return json({ error: "PIN must be 4 digits and not an obvious pattern such as 1234." }, 400);
  }

  const fingerprint = await pinFingerprint(body.pin);
  const { error } = await user.rpc("staff_set_pin", {
    p_profile: body.profile_id,
    p_pin_fingerprint: fingerprint,
  });
  if (error) return json({ error: friendly(error).message }, friendly(error).status);
  return json({ ok: true });
}

async function setStatus(user: SupabaseClient, admin: SupabaseClient, body: Body): Promise<Response> {
  if (typeof body.profile_id !== "string" || typeof body.active !== "boolean") {
    return json({ error: "Choose a staff member and an action." }, 400);
  }
  const { data: profile, error: readError } = await user
    .from("staff_profiles")
    .select("user_id")
    .eq("id", body.profile_id)
    .maybeSingle();
  if (readError) return json(friendly(readError), friendly(readError).status);
  if (!profile) return json({ error: "That staff member was not found." }, 404);

  const { error } = await user.rpc("staff_set_status", {
    p_profile: body.profile_id,
    p_active: body.active,
  });
  if (error) return json({ error: friendly(error).message }, friendly(error).status);

  const { error: banError } = await admin.auth.admin.updateUserById(profile.user_id, {
    ban_duration: body.active ? "none" : BAN_FOREVER,
  });
  if (banError) return json({ error: "Status changed, but the sign-in could not be updated. Try again." }, 500);
  return json({ ok: true });
}

async function removeStaff(user: SupabaseClient, admin: SupabaseClient, body: Body): Promise<Response> {
  if (typeof body.profile_id !== "string") return json({ error: "Choose a staff member." }, 400);
  const { data: profile, error: readError } = await user
    .from("staff_profiles")
    .select("user_id")
    .eq("id", body.profile_id)
    .maybeSingle();
  if (readError) return json(friendly(readError), friendly(readError).status);
  if (!profile) return json({ error: "That staff member was not found." }, 404);

  const { error } = await user.rpc("staff_remove", { p_profile: body.profile_id });
  if (error) return json({ error: friendly(error).message }, friendly(error).status);

  await admin.auth.admin.deleteUser(profile.user_id);
  return json({ ok: true });
}

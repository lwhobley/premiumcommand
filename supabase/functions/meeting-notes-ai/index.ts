// Reads a saved meeting note, asks Claude which event it is about and what should change, and
// stores the proposal on the note. Administrators only. Nothing on the event changes here:
// an administrator reviews the proposal and applies it with apply_meeting_note.
//
// Request: { note_id, event_id? }. With event_id the administrator has chosen the event, so
// the matching step is skipped.
//
// Every read and write runs as the signed-in administrator, so row level security applies.
// The Anthropic key is the ANTHROPIC_API_KEY function secret and never reaches the app.
import Anthropic from "npm:@anthropic-ai/sdk@0.133.0";
import type { z } from "npm:zod@4.6.7";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";
import {
  checkChanges,
  checkMatch,
  type EventDetail,
  type EventRow,
  type Match,
  MATCH_SYSTEM,
  MatchSchema,
  matchPrompt,
  type NoteInput,
  outputSchema,
  PROPOSAL_SYSTEM,
  ProposalSchema,
  proposalPrompt,
  readOutput,
} from "./analysis.ts";

const MODEL = "claude-haiku-5-5";
// Matching is a lookup over a list, so the model's default (medium) is enough. Proposals must
// follow strict rules (only what the notes support, no duplicates), so they get high.
const MATCH_EFFORT = "medium";
const PROPOSAL_EFFORT = "high";
// Events offered for matching: recent past through the coming year and a half.
const PAST_DAYS = 90;
const FUTURE_DAYS = 540;
const MAX_EVENTS = 300;

const EVENT_COLUMNS =
  "id, name, event_type, status, service_start, service_end, guaranteed_guests, manager_name, notes";
// Two foreign keys link assignments to suites, so the embed names the one to follow.
const SUITE_COLUMNS =
  "id, dietary_notes, special_instructions, guest_contact, venue_suites!suite_event_assignments_suite_id_fkey(name)";

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Sign in to use the assistant." }, 401);

  let body: { note_id?: unknown; event_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Send a JSON request." }, 400);
  }
  if (typeof body.note_id !== "string") return json({ error: "Choose a meeting note." }, 400);
  if (body.event_id !== undefined && body.event_id !== null && typeof body.event_id !== "string") {
    return json({ error: "Choose an event." }, 400);
  }

  const user = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const analysis = await analyze(user, body.note_id, (body.event_id as string | null) ?? null);
    return json({ analysis });
  } catch (error) {
    if (error instanceof HttpError) return json({ error: error.message }, error.status);
    if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
      console.error("meeting-notes-ai: Anthropic key rejected", error.status);
      return json({ error: "The assistant's API key was rejected. Check the ANTHROPIC_API_KEY secret." }, 503);
    }
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "The assistant is busy. Try again in a minute." }, 429);
    }
    if (error instanceof Anthropic.APIConnectionError) {
      return json({ error: "The assistant could not be reached. Try again." }, 502);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("meeting-notes-ai: Anthropic error", error.status, error.message);
      return json({ error: "The assistant failed. Try again." }, 502);
    }
    console.error("meeting-notes-ai failed", error);
    return json({ error: "The request failed. Try again." }, 500);
  }
});

async function analyze(user: SupabaseClient, noteId: string, chosenEventId: string | null) {
  const { data: note, error: noteError } = await user
    .from("meeting_notes")
    .select("id, venue_id, title, body, meeting_at, status")
    .eq("id", noteId)
    .maybeSingle();
  if (noteError) throw new HttpError(400, noteError.message);
  if (!note) throw new HttpError(404, "That meeting note was not found.");
  if (note.status === "applied") throw new HttpError(409, "This meeting note has already been applied.");

  // Applied notes are readable by every member, so check administrator access explicitly.
  const { data: allowed, error: allowedError } = await user.rpc("has_permission", {
    p_venue: note.venue_id,
    p_permission: "manage_configuration",
  });
  if (allowedError) throw new HttpError(400, allowedError.message);
  if (!allowed) throw new HttpError(403, "Only administrators can use the meeting notes assistant.");

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    throw new HttpError(503, "The assistant is not set up. Add the ANTHROPIC_API_KEY function secret.");
  }
  const anthropic = new Anthropic({ apiKey, timeout: 90_000, maxRetries: 1 });

  const { data: venue } = await user.from("venues").select("time_zone").eq("id", note.venue_id).single();
  const timeZone: string = venue?.time_zone || "UTC";
  const now = new Date();
  const input: NoteInput = { title: note.title, body: note.body, meeting_at: note.meeting_at };

  let match: Match & { chosen_by: "assistant" | "administrator" };
  if (chosenEventId) {
    match = {
      event_id: chosenEventId,
      confidence: "high",
      reason: "Chosen by an administrator.",
      alternative_event_ids: [],
      chosen_by: "administrator",
    };
  } else {
    const events = await listCandidateEvents(user, note.venue_id, now);
    const raw = await ask(
      anthropic,
      MATCH_SYSTEM,
      matchPrompt(input, events, timeZone, now),
      MatchSchema,
      MATCH_EFFORT,
    );
    match = { ...checkMatch(raw, events), chosen_by: "assistant" };
  }

  const result = {
    event_id: match.event_id,
    match: {
      confidence: match.confidence,
      reason: match.reason,
      alternative_event_ids: match.alternative_event_ids,
      chosen_by: match.chosen_by,
    },
    summary: "",
    key_details: [] as string[],
    changes: [] as unknown[],
    model: MODEL,
    analyzed_at: now.toISOString(),
  };

  if (match.event_id) {
    const detail = await loadEventDetail(user, note.venue_id, match.event_id);
    const proposal = await ask(
      anthropic,
      PROPOSAL_SYSTEM,
      proposalPrompt(input, detail, timeZone, now),
      ProposalSchema,
      PROPOSAL_EFFORT,
    );
    result.summary = proposal.summary.trim();
    result.key_details = proposal.key_details.map((d) => d.trim()).filter(Boolean).slice(0, 20);
    result.changes = checkChanges(proposal.changes, detail, timeZone);
  }

  const { error: saveError } = await user
    .from("meeting_notes")
    .update({
      analysis: result,
      status: "analyzed",
      event_id: match.event_id,
      updated_at: new Date().toISOString(),
    })
    .eq("id", note.id);
  if (saveError) throw new HttpError(400, saveError.message);
  return result;
}

/** One structured request. The answer is checked against the schema before it is used. */
async function ask<T extends z.ZodType>(
  anthropic: Anthropic,
  system: string,
  prompt: string,
  schema: T,
  effort: "medium" | "high",
): Promise<z.infer<T>> {
  // Thinking is on by default for this model, so the answer is read from the text blocks.
  const response = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 16000,
    system,
    messages: [{ role: "user", content: prompt }],
    output_config: { effort, format: { type: "json_schema", schema: outputSchema(schema) } },
  });
  // This model has no server-side fallback, so a safety decline ends here.
  if (response.stop_reason === "refusal") {
    throw new HttpError(422, "The assistant declined to read these notes. Apply the changes by hand.");
  }
  if (response.stop_reason === "max_tokens") {
    throw new HttpError(422, "These notes are too long for the assistant to finish. Shorten them and try again.");
  }
  const text = response.content
    .filter((block): block is Anthropic.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("");
  const output = readOutput(text, schema);
  if (output === null) {
    throw new HttpError(502, "The assistant returned an answer the app could not read. Try again.");
  }
  return output;
}

async function listCandidateEvents(user: SupabaseClient, venueId: string, now: Date): Promise<EventRow[]> {
  const from = new Date(now.getTime() - PAST_DAYS * 86_400_000).toISOString();
  const to = new Date(now.getTime() + FUTURE_DAYS * 86_400_000).toISOString();
  const { data, error } = await user
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("venue_id", venueId)
    .gte("service_start", from)
    .lte("service_start", to)
    .order("service_start")
    .limit(MAX_EVENTS);
  if (error) throw new HttpError(400, error.message);
  return (data ?? []) as EventRow[];
}

async function loadEventDetail(user: SupabaseClient, venueId: string, eventId: string): Promise<EventDetail> {
  const { data: event, error } = await user
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("venue_id", venueId)
    .eq("id", eventId)
    .maybeSingle();
  if (error) throw new HttpError(400, error.message);
  if (!event) throw new HttpError(404, "That event was not found at this venue.");

  const [tasks, suites, menu] = await Promise.all([
    user.from("event_tasks").select("department, title, status, is_required, due_at")
      .eq("venue_id", venueId).eq("event_id", eventId).order("created_at"),
    user.from("suite_event_assignments").select(SUITE_COLUMNS)
      .eq("venue_id", venueId).eq("event_id", eventId),
    user.from("event_menu_items").select("name, course, dietary_tags, allergens")
      .eq("venue_id", venueId).eq("event_id", eventId).order("created_at"),
  ]);
  for (const result of [tasks, suites, menu]) {
    if (result.error) throw new HttpError(400, result.error.message);
  }

  return {
    event: event as EventRow,
    tasks: (tasks.data ?? []) as EventDetail["tasks"],
    suites: (suites.data ?? []).map((s: Record<string, unknown>) => {
      const suite = s.venue_suites as { name?: string } | { name?: string }[] | null;
      const name = Array.isArray(suite) ? suite[0]?.name : suite?.name;
      return {
        assignment_id: s.id as string,
        suite_name: name ?? "Suite",
        dietary_notes: (s.dietary_notes as string) ?? "",
        special_instructions: (s.special_instructions as string) ?? "",
        guest_contact: (s.guest_contact as string) ?? "",
      };
    }),
    menu: (menu.data ?? []) as EventDetail["menu"],
  };
}

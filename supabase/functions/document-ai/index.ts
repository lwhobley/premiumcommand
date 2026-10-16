// Reads a BEO or menu with Claude and returns what it found, for an administrator to
// review. Nothing is written to the event here: the app opens the BEO editor or the menu
// list with the result, and the usual BEO and menu rules apply when it is saved.
//
// Request: { venue_id, event_id, kind: "beo" | "menu", path?, text? }. path is a file the
// administrator uploaded to the private documents bucket ({venue_id}/{event_id}/{file});
// it is deleted once read. text is pasted text.
//
// Every read runs as the signed-in administrator, so row level security and the storage
// policies apply. The Anthropic key is the ANTHROPIC_API_KEY function secret.
import Anthropic from "npm:@anthropic-ai/sdk@0.133.0";
import type { z } from "npm:zod@4.6.7";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";
import { outputSchema, readOutput } from "../_shared/structured_output.ts";
import {
  BeoSchema,
  checkBeo,
  checkMenu,
  type EventContext,
  type ImportKind,
  instructionFor,
  MAX_FILE_BYTES,
  MAX_TEXT_CHARS,
  MenuSchema,
  pathBelongsTo,
  sourceKind,
  systemFor,
} from "./extraction.ts";

const MODEL = "claude-haiku-5-5";
// Extraction must copy the document faithfully, so it runs at high effort.
const EFFORT = "high";
const BUCKET = "documents";

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

type Body = { venue_id?: unknown; event_id?: unknown; kind?: unknown; path?: unknown; text?: unknown };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Sign in to use the assistant." }, 401);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Send a JSON request." }, 400);
  }
  const { venue_id: venueId, event_id: eventId, kind, path, text } = body;
  if (typeof venueId !== "string" || typeof eventId !== "string") {
    return json({ error: "Choose an event." }, 400);
  }
  if (kind !== "beo" && kind !== "menu") return json({ error: "Choose a BEO or a menu." }, 400);
  if ((typeof path === "string") === (typeof text === "string")) {
    return json({ error: "Upload a file or paste the text." }, 400);
  }

  const user = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const result = await extract(user, {
      venueId,
      eventId,
      kind,
      path: typeof path === "string" ? path : null,
      text: typeof text === "string" ? text : null,
    });
    return json(result);
  } catch (error) {
    if (error instanceof HttpError) return json({ error: error.message }, error.status);
    if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
      console.error("document-ai: Anthropic key rejected", error.status);
      return json({ error: "The assistant's API key was rejected. Check the ANTHROPIC_API_KEY secret." }, 503);
    }
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "The assistant is busy. Try again in a minute." }, 429);
    }
    if (error instanceof Anthropic.APIConnectionError) {
      return json({ error: "The assistant could not be reached. Try again." }, 502);
    }
    if (error instanceof Anthropic.BadRequestError) {
      console.error("document-ai: request rejected", error.message);
      return json({ error: "The assistant could not read that file. Try a clearer PDF or photo, or paste the text." }, 422);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("document-ai: Anthropic error", error.status, error.message);
      return json({ error: "The assistant failed. Try again." }, 502);
    }
    console.error("document-ai failed", error);
    return json({ error: "The request failed. Try again." }, 500);
  } finally {
    // The document is only needed for this read.
    if (typeof path === "string" && pathBelongsTo(path, venueId, eventId)) {
      await user.storage.from(BUCKET).remove([path]).catch(() => {});
    }
  }
});

async function extract(
  user: SupabaseClient,
  request: { venueId: string; eventId: string; kind: ImportKind; path: string | null; text: string | null },
) {
  const { venueId, eventId, kind } = request;
  const { data: allowed, error: allowedError } = await user.rpc("has_permission", {
    p_venue: venueId,
    p_permission: "manage_configuration",
  });
  if (allowedError) throw new HttpError(400, allowedError.message);
  if (!allowed) throw new HttpError(403, "Only administrators can use the document assistant.");

  const { data: event, error: eventError } = await user
    .from("events")
    .select("name, event_type, service_start, guaranteed_guests")
    .eq("venue_id", venueId)
    .eq("id", eventId)
    .maybeSingle();
  if (eventError) throw new HttpError(400, eventError.message);
  if (!event) throw new HttpError(404, "That event was not found at this venue.");

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    throw new HttpError(503, "The assistant is not set up. Add the ANTHROPIC_API_KEY function secret.");
  }

  const source = await loadSource(user, request);
  const anthropic = new Anthropic({ apiKey, timeout: 120_000, maxRetries: 1 });
  const instruction = instructionFor(kind, event as EventContext);
  const content: Anthropic.ContentBlockParam[] = [source, { type: "text", text: instruction }];

  if (kind === "beo") {
    const beo = checkBeo(await ask(anthropic, kind, content, BeoSchema));
    return { kind, beo, menu_items: beo.menu_items, warnings: beo.warnings, model: MODEL };
  }
  const menu = checkMenu(await ask(anthropic, kind, content, MenuSchema));
  return { kind, menu_items: menu.menu_items, warnings: menu.warnings, model: MODEL };
}

/** The document as a Claude content block: a PDF, an image, or text. */
async function loadSource(
  user: SupabaseClient,
  request: { venueId: string; eventId: string; path: string | null; text: string | null },
): Promise<Anthropic.ContentBlockParam> {
  if (request.text !== null) {
    const text = request.text.trim();
    if (!text) throw new HttpError(400, "Paste the BEO or menu text.");
    if (text.length > MAX_TEXT_CHARS) {
      throw new HttpError(413, "That text is too long. Paste one BEO or menu at a time.");
    }
    return { type: "text", text: `<document>\n${text}\n</document>` };
  }

  const path = request.path!;
  if (!pathBelongsTo(path, request.venueId, request.eventId)) {
    throw new HttpError(400, "That file is not in this event's folder.");
  }
  const { data: file, error } = await user.storage.from(BUCKET).download(path);
  if (error || !file) throw new HttpError(404, "The uploaded file could not be read. Upload it again.");
  if (file.size > MAX_FILE_BYTES) throw new HttpError(413, "Files must be 10 MB or smaller.");
  const kind = sourceKind(file.type, path);
  if (!kind) throw new HttpError(415, "Upload a PDF, a JPEG, PNG, or WebP photo, or a text file.");

  const bytes = new Uint8Array(await file.arrayBuffer());
  switch (kind.kind) {
    case "pdf":
      return {
        type: "document",
        source: { type: "base64", media_type: "application/pdf", data: encodeBase64(bytes) },
      };
    case "image":
      return {
        type: "image",
        source: {
          type: "base64",
          media_type: kind.mediaType as "image/jpeg" | "image/png" | "image/webp",
          data: encodeBase64(bytes),
        },
      };
    case "text": {
      const text = new TextDecoder().decode(bytes).slice(0, MAX_TEXT_CHARS);
      return { type: "text", text: `<document>\n${text}\n</document>` };
    }
  }
}

/** One structured request. The answer is checked against the schema before it is used. */
async function ask<T extends z.ZodType>(
  anthropic: Anthropic,
  kind: ImportKind,
  content: Anthropic.ContentBlockParam[],
  schema: T,
): Promise<z.infer<T>> {
  // Thinking is on by default for this model, so the answer is read from the text blocks.
  const response = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 16000,
    system: systemFor(kind),
    messages: [{ role: "user", content }],
    output_config: { effort: EFFORT, format: { type: "json_schema", schema: outputSchema(schema) } },
  });
  // This model has no server-side fallback, so a safety decline ends here.
  if (response.stop_reason === "refusal") {
    throw new HttpError(422, "The assistant declined to read this document. Enter it by hand.");
  }
  if (response.stop_reason === "max_tokens") {
    throw new HttpError(422, "This document is too long to read in one go. Split it and try again.");
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

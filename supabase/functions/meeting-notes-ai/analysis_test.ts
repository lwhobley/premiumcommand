// deno test supabase/functions/meeting-notes-ai/
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type Change,
  checkChanges,
  checkMatch,
  type EventDetail,
  type EventRow,
  MatchSchema,
  matchPrompt,
  outputSchema,
  ProposalSchema,
  proposalPrompt,
  readOutput,
  venueIso,
} from "./analysis.ts";

const event: EventRow = {
  id: "11111111-1111-1111-1111-111111111111",
  name: "Hawks vs. Stars",
  event_type: "hockey_game",
  status: "planning",
  service_start: "2026-10-18T00:00:00Z",
  service_end: "2026-10-18T04:00:00Z",
  guaranteed_guests: 150,
  manager_name: "Dana",
  notes: "",
};

const detail: EventDetail = {
  event,
  tasks: [],
  suites: [{
    assignment_id: "22222222-2222-2222-2222-222222222222",
    suite_name: "Suite 12",
    dietary_notes: "",
    special_instructions: "Champagne on arrival",
    guest_contact: "",
  }],
  menu: [],
};

Deno.test("venue times carry the zone's offset, including across daylight saving", () => {
  assertEquals(venueIso("2026-10-18T00:30:00Z", "America/Chicago"), "2026-10-17T19:30-05:00");
  assertEquals(venueIso("2026-12-18T00:30:00Z", "America/Chicago"), "2026-12-17T18:30-06:00");
  assertEquals(venueIso("2026-10-18T00:30:00Z", "UTC"), "2026-10-18T00:30+00:00");
});

Deno.test("output schemas use only shapes structured outputs accept", () => {
  for (const schema of [MatchSchema, ProposalSchema]) {
    const text = JSON.stringify(outputSchema(schema));
    assert(!text.includes('"oneOf"'), "oneOf should be sent as anyOf");
    assert(!text.includes('"$schema"'));
    assert(!/"type":\[/.test(text), "type lists should be sent as anyOf");
  }
  const proposal = JSON.stringify(outputSchema(ProposalSchema));
  assert(proposal.includes('"const":"update_suite"'), "change types stay enforced");
  assert(proposal.includes('"enum":["suites","banquets","culinary","beverage","lounge","operations"]'));

  const walk = (node: unknown): void => {
    if (Array.isArray(node)) return node.forEach(walk);
    if (node && typeof node === "object") {
      const object = node as Record<string, unknown>;
      if (object.type === "object") assertEquals(object.additionalProperties, false);
      Object.values(object).forEach(walk);
    }
  };
  walk(outputSchema(ProposalSchema));
});

Deno.test("readOutput rejects answers that do not fit the schema", () => {
  assertEquals(readOutput("not json", MatchSchema), null);
  assertEquals(readOutput('{"event_id":null}', MatchSchema), null);
  const ok = readOutput(
    '{"event_id":null,"confidence":"none","reason":"No date given.","alternative_event_ids":[]}',
    MatchSchema,
  );
  assertEquals(ok?.confidence, "none");
});

Deno.test("checkMatch keeps only events that were offered", () => {
  const unknown = checkMatch(
    { event_id: "made-up", confidence: "high", reason: " x ", alternative_event_ids: [event.id, "other"] },
    [event],
  );
  assertEquals(unknown.event_id, null);
  assertEquals(unknown.confidence, "none");
  assertEquals(unknown.alternative_event_ids, [event.id]);

  const known = checkMatch(
    { event_id: event.id, confidence: "medium", reason: "Saturday's game", alternative_event_ids: [event.id] },
    [event],
  );
  assertEquals(known.event_id, event.id);
  assertEquals(known.alternative_event_ids, []);
});

Deno.test("checkChanges drops invalid or no-op changes and records the value replaced", () => {
  const changes: Change[] = [
    { type: "update_event", field: "guaranteed_guests", value: "180", reason: "r" },
    { type: "update_event", field: "guaranteed_guests", value: "about 200", reason: "r" },
    { type: "update_event", field: "manager_name", value: "Dana", reason: "unchanged" },
    { type: "update_event", field: "service_start", value: "2026-10-17T19:00-05:00", reason: "same instant" },
    { type: "update_event", field: "service_end", value: "late", reason: "r" },
    { type: "add_task", department: "culinary", title: "  Confirm GF count ", is_required: true, due_at: "soon", reason: "r" },
    { type: "update_suite", assignment_id: "unknown", field: "dietary_notes", value: "Nut allergy", reason: "r" },
    {
      type: "update_suite",
      assignment_id: "22222222-2222-2222-2222-222222222222",
      field: "dietary_notes",
      value: "Nut allergy",
      reason: "r",
    },
    { type: "append_event_notes", text: "   ", reason: "empty" },
  ];
  const checked = checkChanges(changes, detail, "America/Chicago");
  assertEquals(checked.length, 3);

  const guests = checked[0];
  assert(guests.type === "update_event");
  assertEquals(guests.current, "150");

  const task = checked[1];
  assert(task.type === "add_task");
  assertEquals(task.title, "Confirm GF count");
  assertEquals(task.due_at, null);

  const suite = checked[2];
  assert(suite.type === "update_suite");
  assertEquals(suite.suite_name, "Suite 12");
  assertEquals(suite.current, "");
});

Deno.test("prompts fence the notes as data and include venue-local times", () => {
  const note = { title: "Hawks planning", body: "Bump to 180 guests.", meeting_at: "2026-10-15T15:00:00Z" };
  const now = new Date("2026-10-16T14:00:00Z");
  const match = matchPrompt(note, [event], "America/Chicago", now);
  assert(match.includes("<meeting_notes>\nBump to 180 guests.\n</meeting_notes>"));
  assert(match.includes("2026-10-17T19:00-05:00"));
  assert(match.includes(event.id));

  const proposal = proposalPrompt(note, detail, "America/Chicago", now);
  assert(proposal.includes("22222222-2222-2222-2222-222222222222"));
  assert(proposal.includes("Champagne on arrival"));
});

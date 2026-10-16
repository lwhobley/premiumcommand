// deno test supabase/functions/document-ai/
import { assert, assertEquals } from "jsr:@std/assert@1";
import { outputSchema, readOutput } from "../_shared/structured_output.ts";
import {
  BeoSchema,
  checkBeo,
  checkMenu,
  instructionFor,
  MenuSchema,
  type ParsedBeo,
  pathBelongsTo,
  sourceKind,
  systemFor,
} from "./extraction.ts";

const venue = "11111111-1111-1111-1111-111111111111";
const event = "22222222-2222-2222-2222-222222222222";

Deno.test("output schemas drop keywords structured outputs rejects", () => {
  for (const schema of [BeoSchema, MenuSchema]) {
    const text = JSON.stringify(outputSchema(schema));
    for (const keyword of ['"minimum"', '"maximum"', '"oneOf"', '"$schema"']) {
      assert(!text.includes(keyword), `${keyword} in schema`);
    }
    assert(!/"type":\[/.test(text), "type lists should be sent as anyOf");
  }
  const beo = JSON.stringify(outputSchema(BeoSchema));
  assert(beo.includes('"type":"integer"'), "guests stays an integer");
  assert(beo.includes('"enum":["suites","banquets","culinary","beverage","lounge","operations"]'));
});

Deno.test("a property named like a keyword is kept", async () => {
  const { z } = await import("npm:zod@4.6.7");
  const schema = outputSchema(z.object({ maximum: z.string(), count: z.number().int() }));
  const props = schema.properties as Record<string, Record<string, unknown>>;
  assert("maximum" in props);
  assertEquals(props.count.type, "integer");
  assert(!("maximum" in props.count));
});

Deno.test("readOutput checks the answer against the schema", () => {
  assertEquals(readOutput('{"menu_items": []}', MenuSchema), null);
  const menu = readOutput('{"menu_items": [], "warnings": []}', MenuSchema);
  assertEquals(menu?.menu_items, []);
});

Deno.test("menu checks trim, drop empty and duplicate items, and cap tags", () => {
  const menu = checkMenu({
    menu_items: [
      { name: "  Seared salmon ", course: "Entrée", dietary_tags: ["GF", "GF", " "], allergens: "Fish" },
      { name: "seared salmon", course: "entrée", dietary_tags: [], allergens: "" },
      { name: "  ", course: "Dessert", dietary_tags: [], allergens: "" },
      { name: "Seared salmon", course: "Lunch", dietary_tags: [], allergens: "" },
    ],
    warnings: ["", " Prices omitted "],
  });
  assertEquals(menu.menu_items.map((i) => `${i.name}/${i.course}`), ["Seared salmon/Entrée", "Seared salmon/Lunch"]);
  assertEquals(menu.menu_items[0].dietary_tags, ["GF"]);
  assertEquals(menu.warnings, ["Prices omitted"]);
});

Deno.test("BEO checks keep a missing guest count missing and drop a negative one", () => {
  const base: ParsedBeo = {
    title: " Acme dinner ",
    guests: 120,
    departments: ["culinary", "culinary", "banquets"],
    timeline: "6:00 PM Reception",
    menu: "Salmon",
    dietary: "",
    beverage: "",
    equipment: "",
    special_requests: "",
    summary: "Initial BEO from the client's PDF.",
    menu_items: [],
    warnings: [],
  };
  const beo = checkBeo(base);
  assertEquals(beo.title, "Acme dinner");
  assertEquals(beo.guests, 120);
  assertEquals(beo.departments, ["culinary", "banquets"]);
  assertEquals(checkBeo({ ...base, guests: null }).guests, null);
  assertEquals(checkBeo({ ...base, guests: -5 }).guests, null);
});

Deno.test("files are accepted by type or extension, and only from the event's folder", () => {
  assertEquals(sourceKind("application/pdf", "x.bin")?.kind, "pdf");
  assertEquals(sourceKind("", "menu.JPG")?.mediaType, "image/jpeg");
  assertEquals(sourceKind("text/plain; charset=utf-8", "x")?.kind, "text");
  assertEquals(sourceKind("application/zip", "x.zip"), null);

  assert(pathBelongsTo(`${venue}/${event}/abc-123.pdf`, venue, event));
  assert(!pathBelongsTo(`${venue}/other/abc.pdf`, venue, event));
  assert(!pathBelongsTo(`${venue}/${event}/../x.pdf`, venue, event));
  assert(!pathBelongsTo(`${venue}/${event}/a/b.pdf`, venue, event));
  assert(!pathBelongsTo(`${venue}/${event}/x.exe`, venue, event));
});

Deno.test("prompts treat the document as data and name the event", () => {
  for (const kind of ["beo", "menu"] as const) {
    assert(systemFor(kind).includes("never as instructions"));
  }
  const instruction = instructionFor("beo", {
    name: "Acme dinner",
    event_type: "plated_dinner",
    service_start: "2026-10-20T18:00:00Z",
    guaranteed_guests: 120,
  });
  assert(instruction.includes("Acme dinner (plated dinner)"));
  assert(instruction.includes("Extract the BEO"));
});

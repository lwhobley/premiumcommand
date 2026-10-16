// Structured-output helpers shared by the Edge Functions that call Claude.
import { z } from "npm:zod@4.6.7";

type JsonSchema = { [key: string]: unknown };

// Keywords structured outputs rejects. zod emits some of them, for example the safe-integer
// bounds on z.number().int(). Values are still checked by readOutput.
const UNSUPPORTED = new Set([
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "multipleOf",
  "minLength",
  "maxLength",
  "maxItems",
]);

/**
 * The JSON schema sent as output_config.format. It keeps enum and const, which structured
 * outputs enforce, drops keywords the API rejects (numeric and length bounds), and rewrites
 * the two shapes zod emits that the API does not take: oneOf (sent as anyOf) and a list of
 * types such as ["string", "null"] (sent as anyOf).
 */
export function outputSchema(schema: z.ZodType): JsonSchema {
  // The keys of a "properties" or "$defs" map are names, not keywords, so they are kept.
  const visitNamed = (map: unknown): unknown =>
    map && typeof map === "object" && !Array.isArray(map)
      ? Object.fromEntries(Object.entries(map as JsonSchema).map(([name, value]) => [name, visit(value)]))
      : map;
  const visit = (node: unknown): unknown => {
    if (Array.isArray(node)) return node.map(visit);
    if (node === null || typeof node !== "object") return node;
    const out: JsonSchema = {};
    for (const [key, value] of Object.entries(node as JsonSchema)) {
      if (key === "$schema" || UNSUPPORTED.has(key)) continue;
      out[key === "oneOf" ? "anyOf" : key] = key === "properties" || key === "$defs" ? visitNamed(value) : visit(value);
    }
    if (Array.isArray(out.type)) {
      const types = out.type as string[];
      delete out.type;
      const { description, ...rest } = out;
      return {
        ...(description === undefined ? {} : { description }),
        anyOf: types.map((type) => (type === "null" ? { type } : { ...rest, type })),
      };
    }
    if (out.type === "object") out.additionalProperties = false;
    return out;
  };
  return visit(z.toJSONSchema(schema)) as JsonSchema;
}

/** Parses the model's JSON answer and checks it against the schema. Returns null when it does not fit. */
export function readOutput<T extends z.ZodType>(text: string, schema: T): z.infer<T> | null {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  const result = schema.safeParse(value);
  return result.success ? result.data : null;
}


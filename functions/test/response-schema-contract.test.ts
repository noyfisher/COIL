/**
 * Server half of the cross-stack response contract.
 *
 * `response-schemas.test.ts` exercises the Zod schemas against inputs written in that same
 * file, so it can only ever prove the schemas are self-consistent. This file instead parses
 * the shared fixtures in `contracts/response-schemas/` — the *same files* the iOS test
 * decodes — so the two stacks are pinned to one artifact rather than each to itself.
 *
 * Every object is made `.strict()` recursively for the check. The production schemas stay
 * permissive on purpose (Claude occasionally adds chatter), but the contract test should
 * fail on a field added, removed, renamed, or retyped anywhere in the tree.
 */

import { readFileSync } from "fs";
import { resolve } from "path";
import { z } from "zod";

import {
  analysisSchema,
  rehabPlanSchema,
  exerciseSubstituteSchema,
  formAnalysisSchema,
  wellnessAnalysisSchema,
  RESPONSE_SCHEMAS,
} from "../src/response-schemas";

/**
 * Rebuild a schema with `.strict()` at every nested object level. Zod's `.strict()` only
 * applies to the object it's called on, so without recursing, an extra key inside
 * `conditions[0]` would pass unnoticed — exactly the drift we're trying to catch.
 */
function deepStrict(schema: z.ZodTypeAny): z.ZodTypeAny {
  if (schema instanceof z.ZodObject) {
    const shape = Object.fromEntries(
      Object.entries(schema.shape as Record<string, z.ZodTypeAny>).map(([key, value]) => [
        key,
        deepStrict(value),
      ]),
    );
    return z.object(shape).strict();
  }
  if (schema instanceof z.ZodArray) return z.array(deepStrict(schema.element));
  if (schema instanceof z.ZodOptional) return deepStrict(schema.unwrap()).optional();
  if (schema instanceof z.ZodNullable) return deepStrict(schema.unwrap()).nullable();
  // ZodEffects (lowercaseEnum), primitives, enums — nothing to recurse into.
  return schema;
}

const REPO_ROOT = resolve(__dirname, "../..");
const FIXTURE_DIR = resolve(REPO_ROOT, "contracts/response-schemas");
const IOS_FIXTURE_DIR = resolve(REPO_ROOT, "ios/PT-Helper/COILTests/Fixtures");

/**
 * Paths are resolved from string literals rather than interpolated at call time. The
 * names are all internal constants, but building them from a variable trips static
 * analysis for path traversal, and an explicit table is clearer anyway: this is the
 * complete set of shapes under contract, and `keyof` makes a typo a compile error.
 */
const FIXTURES = {
  analysis: {
    schema: analysisSchema,
    canonical: resolve(FIXTURE_DIR, "analysis.json"),
    mirrored: resolve(IOS_FIXTURE_DIR, "contract-analysis.json"),
  },
  rehab_plan: {
    schema: rehabPlanSchema,
    canonical: resolve(FIXTURE_DIR, "rehab_plan.json"),
    mirrored: resolve(IOS_FIXTURE_DIR, "contract-rehab_plan.json"),
  },
  exercise_substitute: {
    schema: exerciseSubstituteSchema,
    canonical: resolve(FIXTURE_DIR, "exercise_substitute.json"),
    mirrored: resolve(IOS_FIXTURE_DIR, "contract-exercise_substitute.json"),
  },
  form_analysis: {
    schema: formAnalysisSchema,
    canonical: resolve(FIXTURE_DIR, "form_analysis.json"),
    mirrored: resolve(IOS_FIXTURE_DIR, "contract-form_analysis.json"),
  },
  wellness_analysis: {
    schema: wellnessAnalysisSchema,
    canonical: resolve(FIXTURE_DIR, "wellness_analysis.json"),
    mirrored: resolve(IOS_FIXTURE_DIR, "contract-wellness_analysis.json"),
  },
} as const;

type FixtureName = keyof typeof FIXTURES;

const CASES = Object.entries(FIXTURES) as Array<
  [FixtureName, (typeof FIXTURES)[FixtureName]]
>;

function fixture(name: FixtureName): unknown {
  return JSON.parse(readFileSync(FIXTURES[name].canonical, "utf8"));
}

describe("response-schema contract (server side)", () => {
  for (const [name, { schema }] of CASES) {
    it(`${name}.json matches its schema exactly`, () => {
      const result = deepStrict(schema).safeParse(fixture(name));

      if (!result.success) {
        const issues = result.error.issues
          .map((i) => `  ${i.path.join(".") || "(root)"}: ${i.message}`)
          .join("\n");
        throw new Error(
          `contracts/response-schemas/${name}.json no longer matches the Zod schema:\n${issues}\n\n` +
            "Update the fixture, the schema, and the matching Swift struct together — " +
            "changing only one is what this test exists to catch.",
        );
      }
    });
  }

  /**
   * The fixtures must be complete. An optional field left out of a fixture is a field
   * neither stack is checking, which would let it drift unnoticed.
   */
  for (const [name, { schema }] of CASES) {
    it(`${name}.json populates every optional field`, () => {
      const data = fixture(name) as Record<string, unknown>;

      const missing: string[] = [];
      const walk = (node: z.ZodTypeAny, value: unknown, path: string) => {
        if (node instanceof z.ZodOptional) {
          if (value === undefined) missing.push(path);
          walk(node.unwrap(), value, path);
          return;
        }
        if (node instanceof z.ZodArray) {
          if (Array.isArray(value) && value.length > 0) walk(node.element, value[0], `${path}[0]`);
          return;
        }
        if (node instanceof z.ZodObject) {
          const record = (value ?? {}) as Record<string, unknown>;
          for (const [key, child] of Object.entries(node.shape as Record<string, z.ZodTypeAny>)) {
            walk(child, record[key], path ? `${path}.${key}` : key);
          }
        }
      };
      walk(schema, data, "");

      expect(missing).toEqual([]);
    });
  }

  /**
   * Guards the fixture set itself: every request type `claudeProxy` validates should have a
   * fixture, so adding a schema without a fixture fails rather than silently going
   * uncovered. Aliased types (analysis_verify, wellness_verify, wellness_plan) reuse another
   * type's shape and share its fixture.
   */
  /**
   * The iOS test target bundles its own copies, because XCTest runs sandboxed on the
   * simulator and cannot read the repo at runtime (the same constraint
   * `AIRequestTypeContractTests.swift` documents). A copy that drifts from the canonical
   * file would quietly break the whole point of a shared artifact, so pin them byte for
   * byte here — Node can see both paths.
   */
  for (const [name, paths] of CASES) {
    it(`${name}.json is mirrored verbatim into the iOS test bundle`, () => {
      const canonical = readFileSync(paths.canonical, "utf8");
      const mirrored = readFileSync(paths.mirrored, "utf8");

      expect(mirrored).toBe(canonical);
    });
  }

  it("covers every schema in the RESPONSE_SCHEMAS dispatch table", () => {
    const aliases: Record<string, string> = {
      analysis_verify: "analysis",
      wellness_verify: "wellness_analysis",
      wellness_plan: "rehab_plan",
    };
    const covered = new Set<string>(CASES.map(([name]) => name));

    const uncovered = Object.keys(RESPONSE_SCHEMAS).filter(
      (type) => !covered.has(aliases[type] ?? type),
    );

    expect(uncovered).toEqual([]);
  });
});

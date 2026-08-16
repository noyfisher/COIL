# Response-schema contract

Golden examples of every AI response shape the iOS client decodes. **Both stacks assert
against these same files**, which is the entire point:

- `functions/test/response-schema-contract.test.ts` parses each fixture against a
  recursively-`.strict()` version of the Zod schema in `functions/src/response-schemas.ts`.
  Strict at every level means a field added, removed, renamed, or retyped on the server
  fails the test.
- `ios/PT-Helper/COILTests/ResponseSchemaContractTests.swift` decodes each fixture into the
  production `Decodable` type the app actually uses, and separately compares the fixture's
  key set against the type's stored properties.

Before this existed, each side was only ever tested against itself: the Zod schemas had
tests, the Swift structs had hand-written fixtures, and neither referenced the other. A
field rename on either side shipped silently — and because server prompts and schemas
deploy independently of iOS releases, that drift could reach production between releases.

## Rules

**These files are committed data, not generated.** A fixture derived from the schema would
trivially validate against that schema, which is the self-consistency flaw this is meant to
fix. Write them by hand.

**Every optional field must be present.** An optional field omitted from a fixture is a
field neither side is checking.

**Changing a shape means changing three things together:** the fixture, the Zod schema, and
the Swift struct. If you only change two, one of the two tests fails — that is the contract
working, not a broken test.

## Not covered here

`recovery_insights` (validated by `validateInsightResult` in `managed-agent.ts`),
`nightly_report` (markdown, not JSON), and `cross_verify` (validated inside the `crossVerify`
function, not routed through `claudeProxy`). These have no `claudeProxy` schema, so there is
nothing to pin them against; see the header of `functions/src/response-schemas.ts`.

`agentFormAnalysisSchema` is the cross-session superset of `form_analysis` and is validated
by `validateFormResult` in `form-agent.ts` rather than by `RESPONSE_SCHEMAS`. The iOS type
`AIFormFeedbackResponse` deliberately decodes both shapes, so the Swift side treats
`form_analysis.json` as a subset rather than an exact match.

/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["<rootDir>/test/**/*.test.ts"],
  // Emulator-backed suites are excluded from the default run:
  //   - test/rules/       → `npm run test:rules` (jest.rules.config.js)
  //   - test/integration/ → `npm run test:integration` (jest.integration.config.js)
  testPathIgnorePatterns: [
    "/node_modules/",
    "<rootDir>/test/rules/",
    "<rootDir>/test/integration/",
  ],
  moduleFileExtensions: ["ts", "js", "json"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "tsconfig.json" }],
  },
  // Tests run standalone — no Firebase emulator setup here.
  // Response-schema tests exercise the pure Zod schemas directly.
  testTimeout: 10000,
};

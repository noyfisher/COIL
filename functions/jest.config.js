/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["<rootDir>/test/**/*.test.ts"],
  // Integration tests require the Firebase emulator — run via
  // `npm run test:integration`, not the standalone default suite.
  testPathIgnorePatterns: ["/node_modules/", "<rootDir>/test/integration/"],
  moduleFileExtensions: ["ts", "js", "json"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "tsconfig.json" }],
  },
  // Tests run standalone — no Firebase emulator setup here.
  // Response-schema tests exercise the pure Zod schemas directly.
  testTimeout: 10000,
};

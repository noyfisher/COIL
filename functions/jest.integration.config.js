/** @type {import('jest').Config} */
// Integration tests that require the Firebase emulator (firebase-admin pointed at
// the local Firestore). Run via `npm run test:integration` (wraps this in
// `firebase emulators:exec`). Kept separate from the default jest suite.
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["<rootDir>/test/integration/**/*.test.ts"],
  moduleFileExtensions: ["ts", "js", "json"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "tsconfig.json" }],
  },
  testTimeout: 30000,
};

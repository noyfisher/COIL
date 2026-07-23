/** @type {import('jest').Config} */
// Firestore Security Rules tests. Run under the emulator via `npm run test:rules`
// (which wraps this in `firebase emulators:exec`). Kept separate from the default
// jest suite because these require a live Firestore emulator.
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["<rootDir>/test/rules/**/*.test.ts"],
  moduleFileExtensions: ["ts", "js", "json"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "tsconfig.json" }],
  },
  testTimeout: 20000,
};

/**
 * Tier 2 PR B: tests for the Firestore-backed distributed rate limiter.
 *
 * Exercises `isRateLimited(uid, now, db)` with a mock `Firestore` that
 * records transaction reads/writes. This verifies:
 * - the increment-on-allow / no-increment-on-deny semantics
 * - the current-count threshold (20 requests per window)
 * - the ISO-minute bucket key (different minutes → different doc paths)
 *
 * Does NOT exercise real Firestore. Staging dry-run (`rate-limit-e2e.sh`)
 * covers live-network behavior.
 */

import { rateLimitWindowKey, RATE_LIMIT_MAX, isRateLimited } from "../src/index";

// ---------------------------------------------------------------------------
// Mock Firestore for the transaction path
// ---------------------------------------------------------------------------

type DocData = Record<string, unknown>;

interface FakeDocSnapshot {
  exists: boolean;
  data: () => DocData | undefined;
}

interface FakeDocRef {
  __path: string;
  __data: DocData | undefined;
  collection: (name: string) => FakeCollectionRef;
  doc?: never;
}

interface FakeCollectionRef {
  doc: (id: string) => FakeDocRef;
}

interface FakeTx {
  get: (ref: FakeDocRef) => Promise<FakeDocSnapshot>;
  set: (ref: FakeDocRef, data: DocData, options?: { merge?: boolean }) => void;
}

/**
 * Minimal fake that implements just enough of the Firestore API for the
 * rate limiter to work. Stores all docs in a flat Map keyed by their path.
 */
class FakeFirestore {
  private store: Map<string, DocData> = new Map();
  public transactionCount = 0;

  collection(name: string): FakeCollectionRef {
    return this.makeCollection(name);
  }

  doc(path: string): FakeDocRef {
    return this.makeDocRef(path);
  }

  private makeCollection(path: string): FakeCollectionRef {
    return {
      doc: (id: string) => this.makeDocRef(`${path}/${id}`),
    };
  }

  private makeDocRef(path: string): FakeDocRef {
    const store = this.store;
    return {
      __path: path,
      get __data() { return store.get(path); },
      collection: (name: string) => this.makeCollection(`${path}/${name}`),
    };
  }

  async runTransaction<T>(fn: (tx: FakeTx) => Promise<T>): Promise<T> {
    this.transactionCount++;
    const tx: FakeTx = {
      get: async (ref: FakeDocRef): Promise<FakeDocSnapshot> => {
        const data = this.store.get(ref.__path);
        return {
          exists: data !== undefined,
          data: () => data,
        };
      },
      set: (ref: FakeDocRef, data: DocData, options?: { merge?: boolean }) => {
        // Resolve any FieldValue.increment sentinels and merge with existing data.
        const existing = options?.merge ? (this.store.get(ref.__path) ?? {}) : {};
        const resolved: DocData = { ...existing };
        for (const [k, v] of Object.entries(data)) {
          if (isIncrementSentinel(v)) {
            const prev = Number(resolved[k] ?? 0);
            resolved[k] = prev + v.__increment;
          } else if (isServerTimestampSentinel(v)) {
            resolved[k] = new Date();
          } else {
            resolved[k] = v;
          }
        }
        this.store.set(ref.__path, resolved);
      },
    };
    return await fn(tx);
  }

  /** Inspect what's at a given path (tests only). */
  snapshot(path: string): DocData | undefined {
    return this.store.get(path);
  }
}

// Minimal sentinels that mimic firebase-admin's FieldValue API.
type IncrementSentinel = { __increment: number };
type ServerTimestampSentinel = { __serverTimestamp: true };

function isIncrementSentinel(v: unknown): v is IncrementSentinel {
  return typeof v === "object" && v !== null && "__increment" in v;
}
function isServerTimestampSentinel(v: unknown): v is ServerTimestampSentinel {
  return typeof v === "object" && v !== null && "__serverTimestamp" in v;
}

// Mock `admin.firestore.FieldValue.increment` / `.serverTimestamp` by
// hijacking the module. We do this via jest.mock at the top.
jest.mock("firebase-admin", () => {
  return {
    __esModule: true,
    initializeApp: jest.fn(),
    default: {},
    firestore: Object.assign(
      () => ({
        /* overridden per-test with an injected FakeFirestore */
      }),
      {
        FieldValue: {
          increment: (n: number): IncrementSentinel => ({ __increment: n }),
          serverTimestamp: (): ServerTimestampSentinel => ({ __serverTimestamp: true }),
        },
      },
    ),
  };
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("rateLimitWindowKey", () => {
  it("formats ISO-minute: YYYY-MM-DDTHH:MM", () => {
    const key = rateLimitWindowKey(new Date("2026-04-24T14:37:59.123Z"));
    expect(key).toBe("2026-04-24T14:37");
  });

  it("different seconds in the same minute → same key", () => {
    const a = rateLimitWindowKey(new Date("2026-04-24T14:37:01.000Z"));
    const b = rateLimitWindowKey(new Date("2026-04-24T14:37:59.999Z"));
    expect(a).toBe(b);
  });

  it("different minutes → different keys", () => {
    const a = rateLimitWindowKey(new Date("2026-04-24T14:37:59.000Z"));
    const b = rateLimitWindowKey(new Date("2026-04-24T14:38:00.000Z"));
    expect(a).not.toBe(b);
  });
});

describe("RATE_LIMIT_MAX constant", () => {
  it("is 20 (matches DoD)", () => {
    expect(RATE_LIMIT_MAX).toBe(20);
  });
});

describe("isRateLimited", () => {
  let db: FakeFirestore;
  const uid = "test-user";
  const now = new Date("2026-04-24T14:37:30.000Z");
  const windowKey = "2026-04-24T14:37";
  const docPath = `rateLimits/${uid}/windows/${windowKey}`;

  beforeEach(() => {
    db = new FakeFirestore();
  });

  it("first request: not rate-limited, count=1 written", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const result = await isRateLimited(uid, now, db as any);
    expect(result).toBe(false);
    const doc = db.snapshot(docPath);
    expect(doc?.count).toBe(1);
  });

  it("allows up to RATE_LIMIT_MAX requests in one window", async () => {
    for (let i = 1; i <= RATE_LIMIT_MAX; i++) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result = await isRateLimited(uid, now, db as any);
      expect(result).toBe(false);
      expect(db.snapshot(docPath)?.count).toBe(i);
    }
  });

  it("rejects the (MAX+1)th request in the same window", async () => {
    for (let i = 1; i <= RATE_LIMIT_MAX; i++) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await isRateLimited(uid, now, db as any);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const rejected = await isRateLimited(uid, now, db as any);
    expect(rejected).toBe(true);
    // Count does NOT increment on rejection — user is already over.
    expect(db.snapshot(docPath)?.count).toBe(RATE_LIMIT_MAX);
  });

  it("new minute → fresh window, counter resets", async () => {
    for (let i = 1; i <= RATE_LIMIT_MAX; i++) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await isRateLimited(uid, now, db as any);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(await isRateLimited(uid, now, db as any)).toBe(true);

    // New minute bucket.
    const nextMinute = new Date("2026-04-24T14:38:00.000Z");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(await isRateLimited(uid, nextMinute, db as any)).toBe(false);
    expect(db.snapshot(`rateLimits/${uid}/windows/2026-04-24T14:38`)?.count).toBe(1);
    // Old window untouched.
    expect(db.snapshot(docPath)?.count).toBe(RATE_LIMIT_MAX);
  });

  it("different uids have independent counters", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    for (let i = 0; i < RATE_LIMIT_MAX; i++) await isRateLimited("alice", now, db as any);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const rejectedAlice = await isRateLimited("alice", now, db as any);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const bob = await isRateLimited("bob", now, db as any);

    expect(rejectedAlice).toBe(true);
    expect(bob).toBe(false);
    expect(db.snapshot(`rateLimits/alice/windows/${windowKey}`)?.count).toBe(RATE_LIMIT_MAX);
    expect(db.snapshot(`rateLimits/bob/windows/${windowKey}`)?.count).toBe(1);
  });

  it("each call runs inside a transaction", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await isRateLimited(uid, now, db as any);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await isRateLimited(uid, now, db as any);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await isRateLimited(uid, now, db as any);
    expect(db.transactionCount).toBe(3);
  });

  it("records firstSeenAt only once per window", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await isRateLimited(uid, now, db as any);
    const firstSnapshot = db.snapshot(docPath);
    const firstSeen = firstSnapshot?.firstSeenAt;
    expect(firstSeen).toBeInstanceOf(Date);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await isRateLimited(uid, now, db as any);
    const secondSnapshot = db.snapshot(docPath);
    // firstSeenAt should be preserved from the initial write.
    expect(secondSnapshot?.firstSeenAt).toBe(firstSeen);
  });
});

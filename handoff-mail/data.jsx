// Mock data for the PR tracker app.
// Represents what the app would fetch from GitHub's API.

const REPOS = [
  { id: 'spark-ios', name: 'spark-ios', org: 'oreilly', selected: true },
  { id: 'guac-android', name: 'guac-android', org: 'oreilly' },
  { id: 'learning-web', name: 'learning-web', org: 'oreilly' },
  { id: 'platform-api', name: 'platform-api', org: 'oreilly' },
];

const ME = { login: 'alex.chen', name: 'Alex Chen', avatar: '#c96442' };

// Users who appear across the data
const USERS = {
  'alex.chen':             { login: 'alex.chen', name: 'Alex Chen', color: '#c96442' },
  'theconstellationiris':  { login: 'theconstellationiris', name: 'Iris K.', color: '#7c3aed' },
  'danieldraper':          { login: 'danieldraper', name: 'Daniel Draper', color: '#0891b2' },
  'marisol.v':             { login: 'marisol.v', name: 'Marisol V.', color: '#be185d' },
  'kenji':                 { login: 'kenji', name: 'Kenji N.', color: '#15803d' },
  'priya.r':               { login: 'priya.r', name: 'Priya R.', color: '#b45309' },
  'samir':                 { login: 'samir', name: 'Samir H.', color: '#4338ca' },
};

// Status helpers
// review: APPROVED | CHANGES_REQUESTED | PENDING | COMMENTED | null
// ci:     { pass: n, fail: n, running: n, pending: n }
// mergeable: CLEAN | CONFLICTS | UNKNOWN | BLOCKED

const PULL_REQUESTS = [
  // ── My open PRs ──────────────────────────────────────────────
  {
    id: 5107,
    number: 5107,
    title: 'GUAC-6450 Fetch badge data when credlyID is missing',
    author: 'alex.chen',
    repo: 'spark-ios',
    branch: 'alex/guac-6450-badge-fallback',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: true,
    review: 'CHANGES_REQUESTED',
    ci: { pass: 8, fail: 0, running: 4, pending: 0, total: 12 },
    mergeable: 'BLOCKED',
    additions: 142, deletions: 38, changedFiles: 7,
    opened: '2026-04-21T09:14:00Z',
    lastActivity: '2026-04-23T10:47:00Z',
    reviewers: [
      { login: 'theconstellationiris', state: 'CHANGES_REQUESTED' },
      { login: 'danieldraper', state: 'PENDING' },
    ],
    needsMyAttention: true,
    attentionHint: 'Iris posted "Testing out on device now!" ~5m ago. CI (4 App Store Connect jobs) still running.',
    unread: true,
    labels: ['bug', 'badges'],
  },
  {
    id: 5072,
    number: 5072,
    title: 'SPARK Add cover color background to audiobook player',
    author: 'alex.chen',
    repo: 'spark-ios',
    branch: 'alex/audiobook-cover-color',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: true,
    review: 'APPROVED',
    ci: { pass: 12, fail: 0, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 87, deletions: 12, changedFiles: 4,
    opened: '2026-03-26T14:22:00Z',
    lastActivity: '2026-04-22T16:30:00Z',
    reviewers: [
      { login: 'danieldraper', state: 'APPROVED' },
      { login: 'marisol.v', state: 'APPROVED' },
    ],
    needsMyAttention: false,
    unread: false,
    labels: ['enhancement', 'audiobooks'],
  },

  // ── Needs my review ──────────────────────────────────────────
  {
    id: 5114,
    number: 5114,
    title: 'GUAC-6512 Throttle analytics events during scroll',
    author: 'kenji',
    repo: 'spark-ios',
    branch: 'kenji/throttle-analytics',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: false,
    review: 'PENDING',
    ci: { pass: 10, fail: 0, running: 2, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 64, deletions: 22, changedFiles: 3,
    opened: '2026-04-23T08:02:00Z',
    lastActivity: '2026-04-23T09:18:00Z',
    reviewers: [
      { login: 'alex.chen', state: 'PENDING' },
    ],
    needsMyReview: true,
    unread: true,
    labels: ['performance'],
  },
  {
    id: 5111,
    number: 5111,
    title: 'SPARK-2204 Replace legacy Combine wrapper in PlayerVM',
    author: 'priya.r',
    repo: 'spark-ios',
    branch: 'priya/combine-wrapper-cleanup',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: false,
    review: 'PENDING',
    ci: { pass: 11, fail: 1, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 318, deletions: 402, changedFiles: 14,
    opened: '2026-04-22T11:42:00Z',
    lastActivity: '2026-04-22T19:55:00Z',
    reviewers: [
      { login: 'alex.chen', state: 'PENDING' },
      { login: 'samir', state: 'APPROVED' },
    ],
    needsMyReview: true,
    unread: false,
    labels: ['refactor', 'player'],
  },

  // ── Others' PRs I'm involved in ──────────────────────────────
  {
    id: 5105,
    number: 5105,
    title: 'GUAC-6291 Fix for restoring audiobook mini player',
    author: 'theconstellationiris',
    repo: 'spark-ios',
    branch: 'iris/fix-mini-player-restore',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: false,
    review: 'CHANGES_REQUESTED', // my review state on their PR
    ci: { pass: 12, fail: 0, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 46, deletions: 28, changedFiles: 3,
    opened: '2026-04-20T16:11:00Z',
    lastActivity: '2026-04-21T14:02:00Z',
    reviewers: [
      { login: 'alex.chen', state: 'CHANGES_REQUESTED' },
    ],
    involved: true,
    involvedHint: 'Awaiting their update',
    unread: false,
    labels: ['bug'],
  },
  {
    id: 5102,
    number: 5102,
    title: 'GUAC-6424 Add easy dismissal for offline toast',
    author: 'theconstellationiris',
    repo: 'spark-ios',
    branch: 'iris/offline-toast-dismiss',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: false,
    review: 'CHANGES_REQUESTED',
    ci: { pass: 12, fail: 0, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 31, deletions: 8, changedFiles: 2,
    opened: '2026-04-19T10:33:00Z',
    lastActivity: '2026-04-20T09:44:00Z',
    reviewers: [
      { login: 'alex.chen', state: 'CHANGES_REQUESTED' },
    ],
    involved: true,
    involvedHint: 'Awaiting their update',
    unread: false,
    labels: ['ux'],
  },

  // ── Mentions ─────────────────────────────────────────────────
  {
    id: 5098,
    number: 5098,
    title: 'SPARK-2179 Migrate cache layer to SQLite.swift',
    author: 'samir',
    repo: 'spark-ios',
    branch: 'samir/sqlite-swift-migration',
    base: 'main',
    state: 'OPEN',
    isDraft: false,
    mine: false,
    review: 'COMMENTED',
    ci: { pass: 9, fail: 3, running: 0, pending: 0, total: 12 },
    mergeable: 'BLOCKED',
    additions: 1204, deletions: 886, changedFiles: 38,
    opened: '2026-04-17T13:15:00Z',
    lastActivity: '2026-04-23T07:12:00Z',
    reviewers: [
      { login: 'alex.chen', state: 'COMMENTED' },
      { login: 'marisol.v', state: 'APPROVED' },
    ],
    mention: true,
    mentionHint: '@alex.chen mentioned you in "can you verify the migration path for older installs?"',
    unread: true,
    labels: ['migration', 'large'],
  },

  // ── Recently merged ──────────────────────────────────────────
  {
    id: 5088,
    number: 5088,
    title: 'SPARK Fix deadlock in DownloadQueue.cancel()',
    author: 'alex.chen',
    repo: 'spark-ios',
    branch: 'alex/download-queue-deadlock',
    base: 'main',
    state: 'MERGED',
    isDraft: false,
    mine: true,
    review: 'APPROVED',
    ci: { pass: 12, fail: 0, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 22, deletions: 14, changedFiles: 1,
    opened: '2026-04-16T09:20:00Z',
    mergedAt: '2026-04-18T11:00:00Z',
    lastActivity: '2026-04-18T11:00:00Z',
    reviewers: [{ login: 'danieldraper', state: 'APPROVED' }],
    unread: false,
    labels: ['bug'],
  },
  {
    id: 5081,
    number: 5081,
    title: 'GUAC-6401 Remove dead feature flag `newShelvesLayout`',
    author: 'marisol.v',
    repo: 'spark-ios',
    branch: 'marisol/remove-shelves-flag',
    base: 'main',
    state: 'MERGED',
    isDraft: false,
    mine: false,
    review: 'APPROVED',
    ci: { pass: 12, fail: 0, running: 0, pending: 0, total: 12 },
    mergeable: 'CLEAN',
    additions: 8, deletions: 214, changedFiles: 6,
    opened: '2026-04-15T12:00:00Z',
    mergedAt: '2026-04-17T15:30:00Z',
    lastActivity: '2026-04-17T15:30:00Z',
    reviewers: [{ login: 'alex.chen', state: 'APPROVED' }],
    unread: false,
    labels: ['cleanup'],
  },
];

// ── Timeline/conversation for PR #5107 (the hero example) ─────────
const TIMELINE_5107 = [
  { id: 't1', type: 'commit', at: '2026-04-21T09:14:00Z', actor: 'alex.chen',
    title: 'Initial implementation: fall back to name+issuer lookup',
    sha: 'a3f12c9', seen: true },
  { id: 't2', type: 'commit', at: '2026-04-21T09:14:00Z', actor: 'alex.chen',
    title: 'Add test for missing credlyID case',
    sha: 'b71e4a2', seen: true },
  { id: 't3', type: 'opened', at: '2026-04-21T09:15:00Z', actor: 'alex.chen',
    title: 'opened this pull request', seen: true },

  { id: 't4', type: 'review', at: '2026-04-21T18:22:00Z', actor: 'danieldraper',
    state: 'COMMENTED', body: 'Left a couple of style nits — happy to approve once those are in.', seen: true },

  { id: 't5', type: 'comment', at: '2026-04-22T08:45:00Z', actor: 'theconstellationiris',
    body: "Hmm, I'm not seeing the badge image load on the device for users who migrated from v4.2. Are we handling the case where `issuerId` is also nil? Repro steps in our QA channel.", seen: true },

  { id: 't6', type: 'commit', at: '2026-04-22T14:10:00Z', actor: 'alex.chen',
    title: 'Handle nil issuerId via catalog lookup',
    sha: 'c88a013', seen: true },

  { id: 't7', type: 'review', at: '2026-04-22T20:01:00Z', actor: 'theconstellationiris',
    state: 'CHANGES_REQUESTED', body: "Catalog lookup is good but I'm worried about the perf cost on the shelf view where we already have 20+ badges visible. Can we batch the fetch or cache by issuerId?", seen: true },

  { id: 't8', type: 'commit', at: '2026-04-23T07:32:00Z', actor: 'alex.chen',
    title: 'Batch catalog lookups with per-issuer cache',
    sha: 'd4f91ee', seen: false },
  { id: 't9', type: 'commit', at: '2026-04-23T07:32:00Z', actor: 'alex.chen',
    title: 'Memoize catalog results within session',
    sha: 'e8b03c1', seen: false },

  { id: 't10', type: 'status', at: '2026-04-23T07:40:00Z',
    title: 'CI started (12 checks)', seen: false },

  { id: 't11', type: 'comment', at: '2026-04-23T10:42:00Z', actor: 'theconstellationiris',
    body: 'Testing out on device now!', seen: false, isNew: true },

  { id: 't12', type: 'status', at: '2026-04-23T10:47:00Z',
    title: '4 App Store Connect checks still running',
    details: ['ASC: TestFlight upload (running 3m)', 'ASC: Validation (running 1m)', 'ASC: Symbolication (queued)', 'ASC: Provisioning (queued)'],
    seen: false, isNew: true },
];

// ── Relative time helper ─────────────────────────────────────────
function relTime(iso, now = new Date('2026-04-23T10:55:00Z')) {
  const d = new Date(iso);
  const secs = Math.floor((now - d) / 1000);
  if (secs < 60) return `${secs}s ago`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  const weeks = Math.floor(days / 7);
  if (weeks < 5) return `${weeks}w ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

Object.assign(window, {
  REPOS, ME, USERS, PULL_REQUESTS, TIMELINE_5107, relTime,
});

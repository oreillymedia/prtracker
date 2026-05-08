// Shared UI primitives for the PR tracker app.
// - Avatars (initials on colored fill)
// - Status pills (review / CI / mergeable)
// - Icons (inline SVG, stroke-based, consistent 14-16px)
// - Theme-aware color tokens (light + dark)

// ─── Theme tokens ───────────────────────────────────────────────
const THEMES = {
  light: {
    windowBg: '#ffffff',
    panelBg: 'rgba(246, 246, 248, 0.85)',
    contentBg: '#ffffff',
    sidebarBg: 'rgba(210,225,245,0.45)',
    sidebarGlass: 'rgba(255,255,255,0.5)',
    border: 'rgba(0,0,0,0.08)',
    borderStrong: 'rgba(0,0,0,0.14)',
    hairline: 'rgba(0,0,0,0.06)',
    text: 'rgba(0,0,0,0.88)',
    textMuted: 'rgba(0,0,0,0.56)',
    textFaint: 'rgba(0,0,0,0.38)',
    accent: '#007aff',
    accentBg: 'rgba(0,122,255,0.10)',
    accentText: '#0062cc',
    // Review states
    approved: '#1a7f37', approvedBg: 'rgba(26,127,55,0.10)',
    changes: '#cf222e',  changesBg:  'rgba(207,34,46,0.10)',
    pending: '#9a6700',  pendingBg:  'rgba(154,103,0,0.10)',
    commented: '#6e7781', commentedBg: 'rgba(110,119,129,0.10)',
    // CI
    ciPass: '#1a7f37', ciFail: '#cf222e', ciRunning: '#bf8700', ciPending: '#6e7781',
    // Mergeable
    clean: '#1a7f37', blocked: '#9a6700', conflicts: '#cf222e',
    // Card
    cardBg: '#ffffff',
    cardShadow: '0 1px 2px rgba(0,0,0,0.04), 0 1px 3px rgba(0,0,0,0.05)',
    rowHover: 'rgba(0,0,0,0.03)',
    rowSelect: 'rgba(0,122,255,0.10)',
    unreadDot: '#007aff',
    newHighlight: 'rgba(0,122,255,0.06)',
  },
  dark: {
    windowBg: '#1c1c1e',
    panelBg: 'rgba(28,28,30,0.85)',
    contentBg: '#1c1c1e',
    sidebarBg: 'rgba(44,44,46,0.55)',
    sidebarGlass: 'rgba(255,255,255,0.06)',
    border: 'rgba(255,255,255,0.10)',
    borderStrong: 'rgba(255,255,255,0.18)',
    hairline: 'rgba(255,255,255,0.06)',
    text: 'rgba(255,255,255,0.92)',
    textMuted: 'rgba(235,235,245,0.60)',
    textFaint: 'rgba(235,235,245,0.40)',
    accent: '#0a84ff',
    accentBg: 'rgba(10,132,255,0.18)',
    accentText: '#64a9ff',
    approved: '#3fb950', approvedBg: 'rgba(63,185,80,0.15)',
    changes: '#f85149',  changesBg:  'rgba(248,81,73,0.15)',
    pending: '#d29922',  pendingBg:  'rgba(210,153,34,0.15)',
    commented: '#8b949e', commentedBg: 'rgba(139,148,158,0.15)',
    ciPass: '#3fb950', ciFail: '#f85149', ciRunning: '#d29922', ciPending: '#8b949e',
    clean: '#3fb950', blocked: '#d29922', conflicts: '#f85149',
    cardBg: '#2c2c2e',
    cardShadow: '0 1px 2px rgba(0,0,0,0.3), 0 1px 3px rgba(0,0,0,0.35)',
    rowHover: 'rgba(255,255,255,0.04)',
    rowSelect: 'rgba(10,132,255,0.20)',
    unreadDot: '#0a84ff',
    newHighlight: 'rgba(10,132,255,0.08)',
  },
};

const ThemeCtx = React.createContext(THEMES.light);
const useTheme = () => React.useContext(ThemeCtx);

// ─── Avatar ─────────────────────────────────────────────────────
function Avatar({ user, size = 22, ring = false }) {
  const u = (window.USERS || {})[user] || { login: user, name: user, color: '#888' };
  const initials = u.name.split(/\s+/).map(s => s[0]).slice(0,2).join('').toUpperCase();
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: u.color, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: Math.round(size * 0.42), fontWeight: 600, letterSpacing: 0.2,
      boxShadow: ring ? `0 0 0 2px var(--avatar-ring, #fff)` : 'none',
      flexShrink: 0, userSelect: 'none',
    }}>{initials}</div>
  );
}

function AvatarStack({ users, size = 20, max = 3 }) {
  const shown = users.slice(0, max);
  const rest = users.length - max;
  return (
    <div style={{ display: 'flex', alignItems: 'center' }}>
      {shown.map((u, i) => (
        <div key={u} style={{ marginLeft: i === 0 ? 0 : -6 }}>
          <Avatar user={u} size={size} ring />
        </div>
      ))}
      {rest > 0 && (
        <div style={{
          marginLeft: -6, width: size, height: size, borderRadius: '50%',
          background: 'rgba(0,0,0,0.12)', fontSize: Math.round(size*0.45),
          fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 0 0 2px var(--avatar-ring, #fff)',
        }}>+{rest}</div>
      )}
    </div>
  );
}

// ─── Icons ──────────────────────────────────────────────────────
const I = {
  pr: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <circle cx="4" cy="4" r="1.5" stroke={c} strokeWidth="1.5"/>
      <circle cx="4" cy="12" r="1.5" stroke={c} strokeWidth="1.5"/>
      <circle cx="12" cy="12" r="1.5" stroke={c} strokeWidth="1.5"/>
      <path d="M4 5.5v5M12 10.5V6a2 2 0 0 0-2-2H7.5M7.5 4l1.5-1.5M7.5 4l1.5 1.5" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  merged: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <circle cx="4" cy="4" r="1.5" stroke={c} strokeWidth="1.5"/>
      <circle cx="4" cy="12" r="1.5" stroke={c} strokeWidth="1.5"/>
      <circle cx="12" cy="8" r="1.5" stroke={c} strokeWidth="1.5"/>
      <path d="M4 5.5v5M4 5.5c0 2 2 2.5 4.5 2.5h2" stroke={c} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  ),
  check: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M2.5 6.5l2.5 2.5 4.5-5.5" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  x: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M3 3l6 6M9 3l-6 6" stroke={c} strokeWidth="1.8" strokeLinecap="round"/>
    </svg>
  ),
  dot: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <circle cx="6" cy="6" r="2.5" fill={c}/>
    </svg>
  ),
  clock: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <circle cx="6" cy="6" r="4.5" stroke={c} strokeWidth="1.5"/>
      <path d="M6 3.5V6l1.5 1.5" stroke={c} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  ),
  spinner: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none" style={{ animation: 'pr-spin 1.1s linear infinite' }}>
      <circle cx="6" cy="6" r="4" stroke={c} strokeOpacity="0.25" strokeWidth="1.5"/>
      <path d="M10 6a4 4 0 0 0-4-4" stroke={c} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  ),
  refresh: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <path d="M12 6a5 5 0 1 0-1.5 3.5M12 3v3h-3" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  chevR: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M4.5 2.5l3 3.5-3 3.5" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  chevL: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M7.5 2.5l-3 3.5 3 3.5" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  chevD: (s = 10, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 10 10" fill="none">
      <path d="M2 3.5L5 6.5l3-3" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  comment: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M2 3.5A1.5 1.5 0 0 1 3.5 2h5A1.5 1.5 0 0 1 10 3.5v3A1.5 1.5 0 0 1 8.5 8H5L3 10V8A1.5 1.5 0 0 1 2 6.5v-3z" stroke={c} strokeWidth="1.2" strokeLinejoin="round"/>
    </svg>
  ),
  commit: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <circle cx="6" cy="6" r="2.5" stroke={c} strokeWidth="1.5"/>
      <path d="M6 1.5V3.5M6 8.5v2" stroke={c} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  ),
  moon: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <path d="M12 8.5A5 5 0 1 1 5.5 2a4 4 0 0 0 6.5 6.5z" stroke={c} strokeWidth="1.4" strokeLinejoin="round"/>
    </svg>
  ),
  sun: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="2.5" stroke={c} strokeWidth="1.4"/>
      <path d="M7 1v1.5M7 11.5V13M1 7h1.5M11.5 7H13M2.6 2.6l1.1 1.1M10.3 10.3l1.1 1.1M2.6 11.4l1.1-1.1M10.3 3.7l1.1-1.1" stroke={c} strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  ),
  dots: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <circle cx="3" cy="7" r="1.2" fill={c}/>
      <circle cx="7" cy="7" r="1.2" fill={c}/>
      <circle cx="11" cy="7" r="1.2" fill={c}/>
    </svg>
  ),
  inbox: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <path d="M2 8v3a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V8M2 8l1.5-5h7L12 8M2 8h3l.75 1.5h2.5L9 8h3" stroke={c} strokeWidth="1.3" strokeLinejoin="round"/>
    </svg>
  ),
  at: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="2.5" stroke={c} strokeWidth="1.3"/>
      <path d="M9.5 7v1.5a1.5 1.5 0 0 0 3 0V7a5.5 5.5 0 1 0-2.5 4.6" stroke={c} strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  ),
  eye: (s = 13, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <path d="M1.5 7s2-4 5.5-4 5.5 4 5.5 4-2 4-5.5 4S1.5 7 1.5 7z" stroke={c} strokeWidth="1.3"/>
      <circle cx="7" cy="7" r="1.5" stroke={c} strokeWidth="1.3"/>
    </svg>
  ),
  eyeOff: (s = 13, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <path d="M2 2l10 10M4 4.4C2.5 5.4 1.5 7 1.5 7s2 4 5.5 4c1 0 1.9-.3 2.6-.7M6 3.2A6 6 0 0 1 7 3c3.5 0 5.5 4 5.5 4a10 10 0 0 1-1.5 2" stroke={c} strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  ),
  settings: (s = 14, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="1.8" stroke={c} strokeWidth="1.3"/>
      <path d="M7 1v1.5M7 11.5V13M1 7h1.5M11.5 7H13M2.6 2.6l1 1M10.4 10.4l1 1M2.6 11.4l1-1M10.4 3.6l1-1" stroke={c} strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  ),
  arrow: (s = 12, c = 'currentColor') => (
    <svg width={s} height={s} viewBox="0 0 12 12" fill="none">
      <path d="M2 6h8M7 3l3 3-3 3" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
};

// ─── Review / CI / Merge pills ──────────────────────────────────
function ReviewPill({ state, compact = false }) {
  const t = useTheme();
  const map = {
    APPROVED:           { label: compact ? 'Approved' : 'Approved',           bg: t.approvedBg,  fg: t.approved,  icon: I.check(11, t.approved) },
    CHANGES_REQUESTED:  { label: compact ? 'Changes' : 'Changes requested',   bg: t.changesBg,   fg: t.changes,   icon: I.x(11, t.changes) },
    PENDING:            { label: compact ? 'Pending' : 'Review pending',      bg: t.pendingBg,   fg: t.pending,   icon: I.dot(10, t.pending) },
    COMMENTED:          { label: compact ? 'Comments' : 'Commented',          bg: t.commentedBg, fg: t.commented, icon: I.comment(11, t.commented) },
  };
  const m = map[state]; if (!m) return null;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: compact ? '1px 6px 1px 5px' : '2px 8px 2px 6px',
      borderRadius: 999, background: m.bg, color: m.fg,
      fontSize: compact ? 10.5 : 11, fontWeight: 600, letterSpacing: 0.1,
      whiteSpace: 'nowrap',
    }}>
      {m.icon}{m.label}
    </span>
  );
}

function CIPill({ ci, compact = false }) {
  const t = useTheme();
  const { pass = 0, fail = 0, running = 0, pending = 0, total = 0 } = ci || {};
  // Choose dominant icon: fail > running > pass
  let state, color, label, icon;
  if (fail > 0) {
    state = 'fail'; color = t.ciFail;
    label = compact ? `${fail} failing` : `${fail}/${total} failing`;
    icon = I.x(11, color);
  } else if (running > 0) {
    state = 'running'; color = t.ciRunning;
    label = compact ? `${running} running` : `${pass + running}/${total} · ${running} running`;
    icon = I.spinner(11, color);
  } else if (pass === total && total > 0) {
    state = 'pass'; color = t.ciPass;
    label = compact ? `CI passing` : `${total}/${total} passing`;
    icon = I.check(11, color);
  } else {
    state = 'pending'; color = t.ciPending;
    label = `${pending} pending`;
    icon = I.clock(11, color);
  }
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: compact ? '1px 6px 1px 5px' : '2px 8px 2px 6px',
      borderRadius: 999, background: 'transparent',
      border: `1px solid ${color}33`,
      color, fontSize: compact ? 10.5 : 11, fontWeight: 600,
      whiteSpace: 'nowrap',
    }}>
      {icon}{label}
    </span>
  );
}

function MergeablePill({ state, compact = false }) {
  const t = useTheme();
  const map = {
    CLEAN:     { label: 'Ready to merge',  fg: t.clean },
    BLOCKED:   { label: 'Blocked',         fg: t.blocked },
    CONFLICTS: { label: 'Conflicts',       fg: t.conflicts },
    UNKNOWN:   { label: 'Checking…',       fg: t.textMuted },
  };
  const m = map[state]; if (!m) return null;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      fontSize: compact ? 10.5 : 11, fontWeight: 500, color: m.fg,
    }}>
      {I.dot(7, m.fg)}
      {m.label}
    </span>
  );
}

// Unread dot
function UnreadDot({ on }) {
  const t = useTheme();
  return (
    <div style={{
      width: 8, height: 8, borderRadius: '50%',
      background: on ? t.unreadDot : 'transparent',
      flexShrink: 0,
      boxShadow: on ? `0 0 0 2px ${t.unreadDot}22` : 'none',
    }} />
  );
}

// Global spinner keyframes (idempotent)
if (typeof document !== 'undefined' && !document.getElementById('pr-anim')) {
  const s = document.createElement('style');
  s.id = 'pr-anim';
  s.textContent = `
    @keyframes pr-spin { to { transform: rotate(360deg); } }
    @keyframes pr-pulse { 0%,100% { opacity: 1 } 50% { opacity: 0.5 } }
    .pr-pulse { animation: pr-pulse 1.6s ease-in-out infinite; }
    .pr-row-hover:hover .pr-row-actions { opacity: 1 !important; }
  `;
  document.head.appendChild(s);
}

Object.assign(window, {
  THEMES, ThemeCtx, useTheme,
  Avatar, AvatarStack, I,
  ReviewPill, CIPill, MergeablePill, UnreadDot,
});

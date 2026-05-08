// Shared macOS window chrome for all variants.
// Provides:
//  - MacShell: traffic lights + sidebar + toolbar frame
//  - RepoSwitcher: segmented control at the toolbar for swapping active repo
//  - Toolbar: title + refresh button + last-updated + theme toggle
//  - Sidebar: repo list + section nav

function TrafficLights() {
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '2px 4px' }}>
      <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57', border: '0.5px solid rgba(0,0,0,0.15)' }} />
      <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e', border: '0.5px solid rgba(0,0,0,0.15)' }} />
      <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840', border: '0.5px solid rgba(0,0,0,0.15)' }} />
    </div>
  );
}

// ─── Sidebar row ─────────────────────────────────────────────
function SidebarRow({ icon, label, count, selected, onClick, children, dim, pulse }) {
  const t = useTheme();
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '5px 10px', margin: '0 8px', borderRadius: 6,
        cursor: onClick ? 'pointer' : 'default',
        background: selected ? t.rowSelect : 'transparent',
        color: selected ? t.accentText : t.text,
        fontSize: 13, fontWeight: selected ? 600 : 500,
        opacity: dim ? 0.6 : 1,
        userSelect: 'none',
        transition: 'background 0.12s',
      }}
      onMouseEnter={e => { if (!selected) e.currentTarget.style.background = t.rowHover; }}
      onMouseLeave={e => { if (!selected) e.currentTarget.style.background = 'transparent'; }}
    >
      {icon && <span style={{ color: selected ? t.accentText : t.textMuted, display: 'flex' }}>{icon}</span>}
      <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</span>
      {pulse && (
        <span style={{
          width: 6, height: 6, borderRadius: '50%', background: t.accent,
        }} className="pr-pulse" />
      )}
      {count != null && (
        <span style={{
          fontSize: 11, fontWeight: 600, color: selected ? t.accentText : t.textMuted,
          background: selected ? 'transparent' : t.hairline, padding: '1px 6px', borderRadius: 10,
          minWidth: 18, textAlign: 'center',
        }}>{count}</span>
      )}
      {children}
    </div>
  );
}

function SidebarHeader({ children }) {
  const t = useTheme();
  return (
    <div style={{
      padding: '14px 18px 4px', fontSize: 10.5, fontWeight: 700,
      color: t.textFaint, textTransform: 'uppercase', letterSpacing: 0.6,
    }}>{children}</div>
  );
}

// ─── Sidebar ─────────────────────────────────────────────────
function Sidebar({
  activeSection, onSectionChange,
  activeRepo, onRepoChange, counts = {},
  showAccountFooter = true,
}) {
  const t = useTheme();
  const sections = [
    { id: 'review',   label: 'Needs my review',     icon: I.eye(13), key: 'review' },
    { id: 'attention', label: 'Needs my attention', icon: I.dot(10, t.pending), key: 'attention', pulse: (counts.attention || 0) > 0 },
    { id: 'mine',     label: 'My open PRs',         icon: I.pr(13), key: 'mine' },
    { id: 'involved', label: "Others' PRs",         icon: I.comment(13), key: 'involved' },
    { id: 'mentions', label: 'Mentions',            icon: I.at(13), key: 'mentions' },
    { id: 'recent',   label: 'Recently merged',     icon: I.merged(13), key: 'recent' },
  ];

  return (
    <div style={{
      width: 220, display: 'flex', flexDirection: 'column',
      background: t.sidebarBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
      borderRight: `0.5px solid ${t.border}`,
      position: 'relative',
      flexShrink: 0,
    }}>
      {/* Traffic lights zone */}
      <div style={{ height: 38, display: 'flex', alignItems: 'center', padding: '0 12px' }}>
        <TrafficLights />
      </div>

      {/* Repo switcher */}
      <div style={{ padding: '4px 10px 8px' }}>
        <div style={{
          padding: '6px 10px', borderRadius: 7,
          background: t.cardBg, border: `0.5px solid ${t.border}`,
          display: 'flex', alignItems: 'center', gap: 8,
          cursor: 'pointer', boxShadow: `inset 0 -1px 0 ${t.hairline}`,
        }}>
          <div style={{ width: 20, height: 20, borderRadius: 5, background: 'linear-gradient(135deg,#c96442,#7b2d1a)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 10, fontWeight: 700 }}>
            {activeRepo?.name?.slice(0,2).toUpperCase() || 'SP'}
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, color: t.textMuted, lineHeight: 1.1 }}>{activeRepo?.org}</div>
            <div style={{ fontSize: 13, fontWeight: 600, color: t.text, lineHeight: 1.2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{activeRepo?.name}</div>
          </div>
          <span style={{ color: t.textFaint }}>{I.chevD(10, t.textFaint)}</span>
        </div>
      </div>

      <SidebarHeader>Feed</SidebarHeader>
      {sections.map(s => (
        <SidebarRow
          key={s.id}
          icon={s.icon}
          label={s.label}
          count={counts[s.key]}
          selected={activeSection === s.id}
          onClick={() => onSectionChange?.(s.id)}
          pulse={s.pulse}
        />
      ))}

      <SidebarHeader>Watching</SidebarHeader>
      <SidebarRow icon={I.inbox(13)} label="All repos" dim />
      <SidebarRow icon={I.pr(13)} label="Search PRs…" dim />

      <div style={{ flex: 1 }} />

      {showAccountFooter && (
        <div style={{
          padding: '10px 14px', borderTop: `0.5px solid ${t.border}`,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <Avatar user={ME.login} size={22} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: t.text, lineHeight: 1.1 }}>{ME.name}</div>
            <div style={{ fontSize: 10.5, color: t.textMuted, lineHeight: 1.2 }}>@{ME.login}</div>
          </div>
          <span style={{ color: t.textFaint, cursor: 'pointer' }}>{I.settings(14, t.textFaint)}</span>
        </div>
      )}
    </div>
  );
}

// ─── Toolbar ─────────────────────────────────────────────────
function Toolbar({ title, subtitle, lastUpdated, isRefreshing, onRefresh, theme, onThemeToggle, right, centerControls }) {
  const t = useTheme();
  return (
    <div style={{
      height: 44, display: 'flex', alignItems: 'center',
      padding: '0 12px', gap: 12, flexShrink: 0,
      background: t.panelBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
      borderBottom: `0.5px solid ${t.border}`,
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 700, color: t.text, lineHeight: 1.1, whiteSpace: 'nowrap' }}>{title}</div>
        {subtitle && <div style={{ fontSize: 11, color: t.textMuted, lineHeight: 1.2 }}>{subtitle}</div>}
      </div>
      <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>
        {centerControls}
      </div>
      {/* Last updated */}
      {lastUpdated && (
        <div style={{
          fontSize: 11, color: t.textMuted,
          display: 'flex', alignItems: 'center', gap: 5,
        }}>
          {isRefreshing
            ? <>{I.spinner(11, t.accent)}<span>Refreshing…</span></>
            : <>{I.clock(11, t.textFaint)}<span>Updated {lastUpdated}</span></>}
        </div>
      )}
      {/* Refresh */}
      <button
        onClick={onRefresh}
        disabled={isRefreshing}
        style={{
          height: 26, padding: '0 8px', borderRadius: 6,
          border: `0.5px solid ${t.border}`,
          background: t.cardBg, color: t.text,
          fontSize: 12, fontWeight: 500, cursor: 'pointer',
          display: 'inline-flex', alignItems: 'center', gap: 5,
        }}
      >
        <span style={{ animation: isRefreshing ? 'pr-spin 1s linear infinite' : 'none', display: 'flex' }}>
          {I.refresh(13, t.textMuted)}
        </span>
        Refresh
      </button>
      {/* Theme toggle */}
      <button
        onClick={onThemeToggle}
        style={{
          height: 26, width: 26, borderRadius: 6,
          border: `0.5px solid ${t.border}`,
          background: t.cardBg, color: t.textMuted,
          cursor: 'pointer', display: 'inline-flex',
          alignItems: 'center', justifyContent: 'center',
        }}
      >
        {theme === 'dark' ? I.sun(13, t.textMuted) : I.moon(13, t.textMuted)}
      </button>
      {right}
    </div>
  );
}

// ─── MacShell: window frame ──────────────────────────────────
function MacShell({ width = 1280, height = 820, children }) {
  const t = useTheme();
  return (
    <div style={{
      width, height, borderRadius: 12, overflow: 'hidden',
      background: t.windowBg,
      color: t.text,
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.18), 0 24px 70px rgba(0,0,0,0.35)',
      display: 'flex',
      fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro", "Helvetica Neue", sans-serif',
      fontSmooth: 'always',
      WebkitFontSmoothing: 'antialiased',
    }}>
      {children}
    </div>
  );
}

// ─── Section header (content area) ───────────────────────────
function SectionHeader({ icon, title, count, action, hint }) {
  const t = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', gap: 8,
      padding: '18px 20px 10px',
    }}>
      {icon && <span style={{ color: t.textMuted, position: 'relative', top: 2 }}>{icon}</span>}
      <h2 style={{
        margin: 0, fontSize: 15, fontWeight: 700, color: t.text,
        letterSpacing: -0.1,
      }}>{title}</h2>
      {count != null && (
        <span style={{
          fontSize: 12, fontWeight: 500, color: t.textMuted,
          padding: '1px 7px', borderRadius: 10, background: t.hairline,
        }}>{count}</span>
      )}
      {hint && <span style={{ fontSize: 11.5, color: t.textFaint, marginLeft: 4 }}>{hint}</span>}
      <div style={{ flex: 1 }} />
      {action}
    </div>
  );
}

function EmptySection({ message }) {
  const t = useTheme();
  return (
    <div style={{
      padding: '10px 20px 18px',
      fontSize: 12.5, color: t.textFaint, fontStyle: 'italic',
    }}>{message}</div>
  );
}

Object.assign(window, {
  MacShell, Sidebar, Toolbar, SectionHeader, EmptySection, SidebarRow, SidebarHeader,
});

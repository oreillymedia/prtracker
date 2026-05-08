// Main app for Option C (polished) — Priority Lanes with tweaks + collapsible sections.

const DEFAULT_OPTS = /*EDITMODE-BEGIN*/{
  "gaugeStyle": "bar",
  "density": "comfortable",
  "palette": "current",
  "grouping": "sections",
  "statusEmphasis": "always",
  "authorPlacement": "meta"
}/*EDITMODE-END*/;

function PRAppC({ initialTheme = 'light', initialOpts = {}, showMenuBarHint = false }) {
  const [theme, setTheme] = React.useState(initialTheme);
  const [opts, setOptsState] = React.useState({ ...DEFAULT_OPTS, ...initialOpts });
  const [activeSection, setActiveSection] = React.useState('all');
  const [selectedPR, setSelectedPR] = React.useState(null);
  const [readMap, setReadMap] = React.useState({});
  const [isRefreshing, setRefreshing] = React.useState(false);
  const [lastUpdated, setLastUpdated] = React.useState('just now');
  const [tweaksOpen, setTweaksOpen] = React.useState(false);

  const tokens = THEMES[theme];
  const activeRepo = REPOS.find(r => r.id === 'spark-ios');

  // Tweaks mode handshake with host
  React.useEffect(() => {
    const onMsg = (e) => {
      const d = e.data;
      if (d?.type === '__activate_edit_mode')   setTweaksOpen(true);
      if (d?.type === '__deactivate_edit_mode') setTweaksOpen(false);
    };
    window.addEventListener('message', onMsg);
    try { window.parent.postMessage({ type: '__edit_mode_available' }, '*'); } catch (_) {}
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const setOpts = (patch) => {
    setOptsState(prev => {
      const next = { ...prev, ...patch };
      try { window.parent.postMessage({ type: '__edit_mode_set_keys', edits: patch }, '*'); } catch (_) {}
      return next;
    });
  };

  const repoPRs = PULL_REQUESTS.filter(p => p.repo === 'spark-ios');
  const byKey = (key) => {
    if (key === 'review')    return repoPRs.filter(p => p.needsMyReview);
    if (key === 'attention') return repoPRs.filter(p => p.needsMyAttention);
    if (key === 'mine')      return repoPRs.filter(p => p.mine && p.state === 'OPEN');
    if (key === 'involved')  return repoPRs.filter(p => p.involved);
    if (key === 'mentions')  return repoPRs.filter(p => p.mention);
    if (key === 'recent')    return repoPRs.filter(p => p.state === 'MERGED');
    return [];
  };

  const counts = {
    review: byKey('review').length, attention: byKey('attention').length,
    mine: byKey('mine').length, involved: byKey('involved').length,
    mentions: byKey('mentions').length, recent: byKey('recent').length,
  };

  const toggleRead = (id) => {
    setReadMap(prev => {
      const pr = PULL_REQUESTS.find(p => p.id === id);
      const current = prev[id] ?? !pr.unread;
      return { ...prev, [id]: !current };
    });
  };
  const openPR = (pr) => { setSelectedPR(pr); setReadMap(prev => ({ ...prev, [pr.id]: true })); };
  const refresh = () => { setRefreshing(true); setTimeout(() => { setRefreshing(false); setLastUpdated('just now'); }, 900); };

  // Build grouped sections (priority order)
  const sectionMap = [
    { key: 'attention', title: 'Needs my attention' },
    { key: 'review',    title: 'Needs my review' },
    { key: 'mentions',  title: 'Mentions' },
    { key: 'mine',      title: 'My open PRs' },
    { key: 'involved',  title: "Others' PRs I'm involved in" },
    { key: 'recent',    title: 'Recently merged' },
  ];

  const visibleSections = activeSection === 'all'
    ? sectionMap
    : sectionMap.filter(s => s.key === activeSection);

  const groupedSections = visibleSections.map(s => ({ ...s, prs: byKey(s.key) }));

  const unifiedList = activeSection === 'all' && opts.grouping === 'unified'
    ? sectionMap.flatMap(s => byKey(s.key).map(pr => ({ pr, sectionKey: s.key })))
        .sort((a, b) => new Date(b.pr.lastActivity) - new Date(a.pr.lastActivity))
    : null;

  const sectionTitle = activeSection === 'all'
    ? 'Feed'
    : sectionMap.find(s => s.key === activeSection)?.title;

  return (
    <ThemeCtx.Provider value={tokens}>
      <MacShell width={1280} height={820}>
        <SidebarC
          activeSection={activeSection}
          onSectionChange={(s) => { setActiveSection(s); setSelectedPR(null); }}
          activeRepo={activeRepo}
          counts={counts}
          palette={opts.palette}
        />
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: tokens.contentBg, position: 'relative' }}>
          {selectedPR ? (
            <PRDetail pr={selectedPR} onClose={() => setSelectedPR(null)} readMap={readMap} onToggleRead={toggleRead} />
          ) : (
            <>
              <Toolbar
                title={sectionTitle}
                subtitle={`${activeRepo.org}/${activeRepo.name}`}
                lastUpdated={lastUpdated}
                isRefreshing={isRefreshing}
                onRefresh={refresh}
                theme={theme}
                onThemeToggle={() => setTheme(x => x === 'light' ? 'dark' : 'light')}
              />
              <div style={{ flex: 1, overflow: 'auto' }}>
                <FeedLanes
                  groupedSections={groupedSections}
                  unified={activeSection === 'all' && opts.grouping === 'unified'}
                  unifiedList={unifiedList}
                  readMap={readMap}
                  onOpen={openPR}
                  onToggleRead={toggleRead}
                  opts={opts}
                />
              </div>
              <TweaksPanel opts={opts} setOpts={setOpts} visible={tweaksOpen} />
            </>
          )}
        </div>
      </MacShell>
    </ThemeCtx.Provider>
  );
}

// Sidebar tailored for C — includes an "All" option + priority dots
function SidebarC({ activeSection, onSectionChange, activeRepo, counts, palette }) {
  const t = useTheme();
  const colors = LANE_COLORS[palette] || LANE_COLORS.current;
  const sections = [
    { id: 'all',       label: 'All feed',             color: t.textMuted, icon: I.inbox(13) },
    { id: 'attention', label: 'Needs my attention',   color: colors.attention, pulse: counts.attention > 0 },
    { id: 'review',    label: 'Needs my review',      color: colors.review },
    { id: 'mentions',  label: 'Mentions',             color: colors.mentions },
    { id: 'mine',      label: 'My open PRs',          color: colors.mine },
    { id: 'involved',  label: "Others' PRs",          color: colors.involved },
    { id: 'recent',    label: 'Recently merged',      color: colors.recent },
  ];

  return (
    <div style={{
      width: 220, display: 'flex', flexDirection: 'column',
      background: t.sidebarBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
      borderRight: `0.5px solid ${t.border}`,
      flexShrink: 0,
    }}>
      <div style={{ height: 38, display: 'flex', alignItems: 'center', padding: '0 12px' }}>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57', border: '0.5px solid rgba(0,0,0,0.15)' }} />
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e', border: '0.5px solid rgba(0,0,0,0.15)' }} />
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840', border: '0.5px solid rgba(0,0,0,0.15)' }} />
        </div>
      </div>

      <div style={{ padding: '4px 10px 8px' }}>
        <div style={{
          padding: '7px 10px', borderRadius: 7,
          background: t.cardBg, border: `0.5px solid ${t.border}`,
          display: 'flex', alignItems: 'center', gap: 8,
          boxShadow: `inset 0 -1px 0 ${t.hairline}`,
        }}>
          <div style={{ width: 22, height: 22, borderRadius: 5, background: 'linear-gradient(135deg,#c96442,#7b2d1a)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 10, fontWeight: 700 }}>
            SP
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, color: t.textMuted, lineHeight: 1.1 }}>{activeRepo.org}</div>
            <div style={{ fontSize: 13, fontWeight: 600, color: t.text, lineHeight: 1.2 }}>{activeRepo.name}</div>
          </div>
          <span style={{ color: t.textFaint }}>{I.chevD(10, t.textFaint)}</span>
        </div>
      </div>

      <SidebarHeader>Feed</SidebarHeader>
      {sections.map(s => (
        <div
          key={s.id}
          onClick={() => onSectionChange(s.id)}
          style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '5px 10px', margin: '0 8px', borderRadius: 6,
            cursor: 'pointer',
            background: activeSection === s.id ? t.rowSelect : 'transparent',
            color: activeSection === s.id ? t.accentText : t.text,
            fontSize: 13, fontWeight: activeSection === s.id ? 600 : 500,
            userSelect: 'none', transition: 'background 0.12s',
          }}
          onMouseEnter={e => { if (activeSection !== s.id) e.currentTarget.style.background = t.rowHover; }}
          onMouseLeave={e => { if (activeSection !== s.id) e.currentTarget.style.background = 'transparent'; }}
        >
          {s.id === 'all' ? (
            <span style={{ color: t.textMuted, display: 'flex' }}>{s.icon}</span>
          ) : (
            <div style={{ width: 4, height: 14, borderRadius: 1.5, background: s.color }} />
          )}
          <span style={{ flex: 1 }}>{s.label}</span>
          {s.pulse && <span style={{ width: 6, height: 6, borderRadius: '50%', background: t.accent }} className="pr-pulse" />}
          {s.id !== 'all' && counts[s.id] != null && (
            <span style={{
              fontSize: 11, fontWeight: 600,
              color: activeSection === s.id ? t.accentText : t.textMuted,
              background: activeSection === s.id ? 'transparent' : t.hairline,
              padding: '1px 6px', borderRadius: 10, minWidth: 18, textAlign: 'center',
            }}>{counts[s.id]}</span>
          )}
        </div>
      ))}

      <div style={{ flex: 1 }} />

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
    </div>
  );
}

Object.assign(window, { PRAppC, SidebarC, DEFAULT_OPTS });

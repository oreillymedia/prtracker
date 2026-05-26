// Mail-style two-pane variant: filter pills + source list on the left,
// detail view on the right (always visible). No drilling; selecting a row
// swaps the detail pane like a mail app.

const MAIL_DEFAULT_OPTS = /*EDITMODE-BEGIN*/{
  "palette": "current",
  "density": "comfortable",
  "showGauge": true,
  "showHints": true
}/*EDITMODE-END*/;

const MAIL_FILTERS = [
  { id: 'all',       label: 'All',           key: null },
  { id: 'attention', label: 'Attention',     key: 'attention' },
  { id: 'review',    label: 'Review',        key: 'review' },
  { id: 'mentions',  label: 'Mentions',      key: 'mentions' },
  { id: 'mine',      label: 'Mine',          key: 'mine' },
  { id: 'involved',  label: 'Involved',      key: 'involved' },
  { id: 'recent',    label: 'Merged',        key: 'recent' },
];

function filterPRs(prs, filterId) {
  if (filterId === 'review')    return prs.filter(p => p.needsMyReview);
  if (filterId === 'attention') return prs.filter(p => p.needsMyAttention);
  if (filterId === 'mine')      return prs.filter(p => p.mine && p.state === 'OPEN');
  if (filterId === 'involved')  return prs.filter(p => p.involved);
  if (filterId === 'mentions')  return prs.filter(p => p.mention);
  if (filterId === 'recent')    return prs.filter(p => p.state === 'MERGED');
  // 'all' — combine everything visible across the other buckets, dedup, sort
  const seen = new Set();
  const out = [];
  for (const p of prs) {
    if (seen.has(p.id)) continue;
    seen.add(p.id); out.push(p);
  }
  return out.sort((a, b) => new Date(b.lastActivity) - new Date(a.lastActivity));
}

function bucketFor(pr) {
  if (pr.needsMyAttention) return 'attention';
  if (pr.needsMyReview)    return 'review';
  if (pr.mention)          return 'mentions';
  if (pr.mine && pr.state === 'OPEN') return 'mine';
  if (pr.involved)         return 'involved';
  if (pr.state === 'MERGED') return 'recent';
  return 'all';
}

// ─── Source list row (mail-style) ──────────────────────────────
function MailRow({ pr, read, selected, onOpen, onToggleRead, opts }) {
  const t = useTheme();
  const [hover, setHover] = React.useState(false);
  const merged = pr.state === 'MERGED';
  const bucket = bucketFor(pr);
  const pri = priorityFor(bucket, opts.palette);
  const stages = computeStages(pr);
  const hint = pr.attentionHint || pr.mentionHint || pr.involvedHint;

  return (
    <div
      onClick={() => onOpen?.(pr)}
      onContextMenu={(e) => { e.preventDefault(); onToggleRead?.(pr.id); }}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        padding: '9px 12px 9px 14px',
        cursor: 'pointer',
        background: selected ? t.rowSelect : (hover ? t.rowHover : 'transparent'),
        borderBottom: `0.5px solid ${t.hairline}`,
        opacity: read && !selected ? 0.62 : 1,
        transition: 'background 0.1s, opacity 0.18s',
      }}
    >
      {/* Priority rail */}
      <div style={{
        position: 'absolute', left: 0, top: 6, bottom: 6,
        width: 3, borderRadius: 2, background: pri.color,
        opacity: read ? 0.5 : 1,
      }} />

      {/* Top line: unread dot · title · time */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
        <UnreadDot on={!read} />
        <span style={{
          fontSize: 13, fontWeight: read ? 500 : 700,
          color: selected ? t.accentText : t.text,
          flex: 1, minWidth: 0,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          letterSpacing: -0.05,
        }}>{pr.title}</span>
        <span style={{
          fontSize: 10.5, color: t.textFaint,
          fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap',
        }}>{relTime(pr.lastActivity)}</span>
      </div>

      {/* Second line: avatar · author · #number · branch */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 4 }}>
        <Avatar user={pr.author} size={16} />
        <span style={{ fontSize: 11.5, color: t.textMuted, fontWeight: 500 }}>
          {(USERS[pr.author] || {}).name || pr.author}
        </span>
        <span style={{ color: t.textFaint, fontSize: 11 }}>·</span>
        <span style={{ fontSize: 11, color: t.textFaint, fontVariantNumeric: 'tabular-nums' }}>
          #{pr.number}
        </span>
        <div style={{ flex: 1 }} />
        {merged ? (
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 3,
            fontSize: 10.5, fontWeight: 600, color: '#8250df',
          }}>{I.merged(11, '#8250df')} Merged</span>
        ) : (
          opts.showGauge && <MiniGaugeDots stages={stages} />
        )}
      </div>

      {/* Optional hint preview (single line) */}
      {opts.showHints && hint && (
        <div style={{
          marginTop: 5,
          marginLeft: 15,
          fontSize: 11.5, color: t.textMuted, lineHeight: 1.4,
          overflow: 'hidden', textOverflow: 'ellipsis',
          display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
        }}>{hint}</div>
      )}
    </div>
  );
}

function MiniGaugeDots({ stages }) {
  const t = useTheme();
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 3 }} title={stages.map(s => s.label + (s.ok ? ' ✓' : s.bad ? ' ✕' : s.running ? ' …' : '')).join(' · ')}>
      {stages.map(s => {
        let color = t.textFaint;
        if (s.ok) color = t.approved;
        else if (s.bad) color = t.changes;
        else if (s.running) color = t.pending;
        return (
          <div key={s.key} style={{
            width: 7, height: 7, borderRadius: '50%',
            background: (s.ok || s.bad || s.running) ? color : 'transparent',
            border: (s.ok || s.bad || s.running) ? 'none' : `1px solid ${t.borderStrong}`,
          }} className={s.running ? 'pr-pulse' : ''} />
        );
      })}
    </div>
  );
}

// ─── Filter pills strip ─────────────────────────────────────────
function FilterPills({ active, onChange, counts, palette }) {
  const t = useTheme();
  const colors = LANE_COLORS[palette] || LANE_COLORS.current;
  const totalAll = MAIL_FILTERS.filter(f => f.key).reduce((s, f) => s + (counts[f.key] || 0), 0);

  return (
    <div style={{
      display: 'flex', gap: 6, padding: '8px 12px 10px',
      borderBottom: `0.5px solid ${t.hairline}`,
      overflowX: 'auto',
      scrollbarWidth: 'none',
    }}>
      {MAIL_FILTERS.map(f => {
        const n = f.key ? counts[f.key] : totalAll;
        const isActive = active === f.id;
        const dotColor = f.key ? colors[f.key] : null;
        return (
          <button
            key={f.id}
            onClick={() => onChange(f.id)}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '4px 9px 4px 8px',
              borderRadius: 999,
              border: `0.5px solid ${isActive ? 'transparent' : t.border}`,
              background: isActive ? t.text : t.cardBg,
              color: isActive ? t.contentBg : t.text,
              fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
              whiteSpace: 'nowrap',
              transition: 'all 0.1s',
            }}
          >
            {dotColor && (
              <span style={{
                width: 7, height: 7, borderRadius: '50%',
                background: isActive ? dotColor : dotColor,
                opacity: isActive ? 1 : 0.95,
              }} />
            )}
            {f.label}
            {n > 0 && (
              <span style={{
                fontSize: 10, fontWeight: 700,
                color: isActive ? t.contentBg : t.textMuted,
                opacity: isActive ? 0.7 : 1,
                fontVariantNumeric: 'tabular-nums',
              }}>{n}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}

// ─── Source list pane ──────────────────────────────────────────
function SourceList({ prs, activeFilter, onFilterChange, counts, selectedId, onOpen, onToggleRead, readMap, opts, repo }) {
  const t = useTheme();
  return (
    <div style={{
      width: 380, flexShrink: 0,
      display: 'flex', flexDirection: 'column',
      background: t.sidebarBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
      borderRight: `0.5px solid ${t.border}`,
      minHeight: 0,
    }}>
      {/* Traffic lights + repo header */}
      <div style={{
        height: 38, display: 'flex', alignItems: 'center',
        padding: '0 12px', gap: 12, flexShrink: 0,
      }}>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#ff5f57', border: '0.5px solid rgba(0,0,0,0.15)' }} />
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#febc2e', border: '0.5px solid rgba(0,0,0,0.15)' }} />
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#28c840', border: '0.5px solid rgba(0,0,0,0.15)' }} />
        </div>
      </div>

      {/* Repo selector */}
      <div style={{ padding: '0 12px 8px' }}>
        <div style={{
          padding: '6px 10px', borderRadius: 7,
          background: t.cardBg, border: `0.5px solid ${t.border}`,
          display: 'flex', alignItems: 'center', gap: 8,
          cursor: 'pointer',
        }}>
          <div style={{
            width: 22, height: 22, borderRadius: 5,
            background: 'linear-gradient(135deg,#c96442,#7b2d1a)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontSize: 10, fontWeight: 700,
          }}>SP</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, color: t.textMuted, lineHeight: 1.1 }}>{repo.org}</div>
            <div style={{ fontSize: 13, fontWeight: 600, color: t.text, lineHeight: 1.2 }}>{repo.name}</div>
          </div>
          <span style={{ color: t.textFaint }}>{I.chevD(10, t.textFaint)}</span>
        </div>
      </div>

      {/* Filter pills */}
      <FilterPills active={activeFilter} onChange={onFilterChange} counts={counts} palette={opts.palette} />

      {/* List */}
      <div style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
        {prs.length === 0 ? (
          <div style={{
            padding: 40, textAlign: 'center',
            fontSize: 12.5, color: t.textFaint, fontStyle: 'italic',
          }}>Nothing in this filter.</div>
        ) : (
          prs.map(pr => {
            const read = readMap[pr.id] ?? !pr.unread;
            return (
              <MailRow
                key={pr.id}
                pr={pr}
                read={read}
                selected={selectedId === pr.id}
                onOpen={onOpen}
                onToggleRead={onToggleRead}
                opts={opts}
              />
            );
          })
        )}
      </div>

      {/* Footer: account */}
      <div style={{
        padding: '10px 14px', borderTop: `0.5px solid ${t.border}`,
        display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0,
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

// ─── Empty detail state ────────────────────────────────────────
function MailEmpty() {
  const t = useTheme();
  return (
    <div style={{
      flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
      flexDirection: 'column', gap: 8, color: t.textFaint,
      background: t.contentBg,
    }}>
      <div style={{ opacity: 0.5 }}>{I.pr(28, t.textFaint)}</div>
      <div style={{ fontSize: 13 }}>No pull request selected.</div>
    </div>
  );
}

// ─── Detail header (no close button — it's a permanent pane) ───
function MailDetailHeader({ pr, theme, onThemeToggle, onRefresh, isRefreshing, lastUpdated }) {
  const t = useTheme();
  const merged = pr.state === 'MERGED';
  return (
    <div style={{
      padding: '10px 18px 12px',
      borderBottom: `0.5px solid ${t.border}`,
      background: t.panelBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
    }}>
      {/* Toolbar row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 11.5, color: t.textFaint }}>spark-ios</span>
        <span style={{ color: t.textFaint }}>/</span>
        <span style={{ fontSize: 11.5, color: t.textMuted, fontVariantNumeric: 'tabular-nums' }}>#{pr.number}</span>
        <span style={{ color: t.textFaint }}>·</span>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          fontSize: 10.5, fontWeight: 600,
          color: merged ? '#8250df' : t.approved,
          padding: '1px 7px', borderRadius: 999,
          background: merged ? 'rgba(130,80,223,0.12)' : t.approvedBg,
        }}>
          {merged ? I.merged(10, '#8250df') : I.pr(10, t.approved)}
          {merged ? 'Merged' : 'Open'}
        </span>
        <div style={{ flex: 1 }} />
        {lastUpdated && (
          <div style={{ fontSize: 11, color: t.textMuted, display: 'flex', alignItems: 'center', gap: 5 }}>
            {isRefreshing
              ? <>{I.spinner(11, t.accent)}<span>Refreshing…</span></>
              : <>{I.clock(11, t.textFaint)}<span>Updated {lastUpdated}</span></>}
          </div>
        )}
        <button
          onClick={onRefresh}
          disabled={isRefreshing}
          style={{
            height: 24, width: 24, borderRadius: 5,
            border: `0.5px solid ${t.border}`,
            background: t.cardBg, color: t.textMuted, cursor: 'pointer',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}
          title="Refresh"
        >
          <span style={{ animation: isRefreshing ? 'pr-spin 1s linear infinite' : 'none', display: 'flex' }}>
            {I.refresh(12, t.textMuted)}
          </span>
        </button>
        <button
          onClick={onThemeToggle}
          style={{
            height: 24, width: 24, borderRadius: 5,
            border: `0.5px solid ${t.border}`,
            background: t.cardBg, color: t.textMuted, cursor: 'pointer',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}
        >{theme === 'dark' ? I.sun(12, t.textMuted) : I.moon(12, t.textMuted)}</button>
      </div>

      <h1 style={{
        margin: 0, fontSize: 17, fontWeight: 700, color: t.text,
        letterSpacing: -0.2, textWrap: 'pretty', lineHeight: 1.25,
      }}>{pr.title}</h1>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginTop: 8,
        fontSize: 11.5, color: t.textMuted, flexWrap: 'wrap',
      }}>
        <Avatar user={pr.author} size={18} />
        <span style={{ color: t.text, fontWeight: 500 }}>{(USERS[pr.author] || {}).name}</span>
        <span>wants to merge into</span>
        <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 10.5, color: t.text, background: t.hairline, padding: '1px 5px', borderRadius: 4 }}>{pr.base}</span>
        <span>from</span>
        <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 10.5, color: t.text, background: t.hairline, padding: '1px 5px', borderRadius: 4 }}>{pr.branch}</span>
        <span style={{ color: t.textFaint }}>·</span>
        <span>opened {relTime(pr.opened)}</span>
      </div>
    </div>
  );
}

// ─── Detail body — reuses CIBreakdown / TimelineItem etc. via composition.
// For PRs without a real timeline we render a stub.

function MailDetail({ pr, theme, onThemeToggle, onRefresh, isRefreshing, lastUpdated, onToggleRead }) {
  const t = useTheme();
  const [reply, setReply] = React.useState('');
  const realTimeline = pr.id === 5107 ? window.TIMELINE_5107 : null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minWidth: 0, background: t.contentBg }}>
      <MailDetailHeader pr={pr} theme={theme} onThemeToggle={onThemeToggle} onRefresh={onRefresh} isRefreshing={isRefreshing} lastUpdated={lastUpdated} />

      <div style={{ flex: 1, display: 'flex', overflow: 'hidden', minHeight: 0 }}>
        {/* Timeline column */}
        <div style={{ flex: 1, overflow: 'auto', padding: '16px 20px 22px', minWidth: 0 }}>
          {realTimeline ? (
            <div style={{ position: 'relative' }}>
              <div style={{
                position: 'absolute', left: 13, top: 4, bottom: 4,
                width: 1, background: t.hairline,
              }} />
              {realTimeline.map((ev, i) => (
                <TimelineItem key={ev.id} ev={ev} isLast={i === realTimeline.length - 1} />
              ))}
            </div>
          ) : (
            <StubTimeline pr={pr} />
          )}

          {/* Quick reply */}
          <div style={{
            marginTop: 18, padding: 12, borderRadius: 10,
            background: t.cardBg, border: `0.5px solid ${t.border}`,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <Avatar user={ME.login} size={20} />
              <span style={{ fontSize: 12, fontWeight: 600, color: t.text }}>Reply as {ME.name}</span>
            </div>
            <textarea
              value={reply}
              onChange={e => setReply(e.target.value)}
              placeholder="Write a comment…"
              style={{
                width: '100%', minHeight: 64, padding: 10,
                borderRadius: 6, border: `0.5px solid ${t.border}`,
                background: t.contentBg, color: t.text,
                fontSize: 13, fontFamily: 'inherit', resize: 'vertical',
                outline: 'none', boxSizing: 'border-box',
              }}
            />
            <div style={{ display: 'flex', gap: 6, marginTop: 8, justifyContent: 'flex-end' }}>
              <button style={btnSecondaryStyle(t)}>Approve</button>
              <button style={btnSecondaryStyle(t)}>Request changes</button>
              <button style={btnPrimaryStyle(t)} disabled={!reply.trim()}>Comment</button>
            </div>
          </div>
        </div>

        {/* Right meta rail */}
        <div style={{
          width: 232, flexShrink: 0,
          borderLeft: `0.5px solid ${t.border}`,
          padding: '16px 16px', overflow: 'auto',
          background: t.panelBg,
        }}>
          <RailSection title="Status">
            <RailRow label="Review" value={<ReviewPill state={pr.review} compact />} />
            <RailRow label="CI" value={<CIPill ci={pr.ci} compact />} />
            <RailRow label="Mergeable" value={<MergeablePill state={pr.mergeable} compact />} />
          </RailSection>

          <RailSection title="CI checks">
            <CIBreakdown ci={pr.ci} />
          </RailSection>

          <RailSection title="Reviewers">
            {(pr.reviewers || []).map(r => (
              <div key={r.login} style={{
                display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0',
              }}>
                <Avatar user={r.login} size={20} />
                <span style={{ fontSize: 12, color: t.text, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {(USERS[r.login] || {}).name || r.login}
                </span>
                <ReviewPill state={r.state} compact />
              </div>
            ))}
          </RailSection>

          <RailSection title="Labels">
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
              {(pr.labels || []).map(l => (
                <span key={l} style={{
                  fontSize: 10.5, padding: '2px 7px', borderRadius: 999,
                  background: t.hairline, color: t.textMuted, fontWeight: 500,
                }}>{l}</span>
              ))}
            </div>
          </RailSection>

          <RailSection title="Changes">
            <div style={{ fontSize: 12, color: t.textMuted, display: 'flex', gap: 10 }}>
              <span style={{ color: t.approved, fontWeight: 600 }}>+{pr.additions}</span>
              <span style={{ color: t.changes, fontWeight: 600 }}>−{pr.deletions}</span>
              <span>·</span>
              <span>{pr.changedFiles} files</span>
            </div>
          </RailSection>

          <button
            onClick={() => onToggleRead?.(pr.id)}
            style={{ ...btnSecondaryStyle(t), width: '100%', justifyContent: 'center', marginTop: 4 }}
          >
            Mark as unread
          </button>
        </div>
      </div>
    </div>
  );
}

// Lightweight stub for PRs that don't have a hand-written timeline.
function StubTimeline({ pr }) {
  const t = useTheme();
  const merged = pr.state === 'MERGED';
  const items = [
    { type: 'opened', actor: pr.author, at: pr.opened, title: 'opened this pull request' },
    ...(pr.reviewers || []).filter(r => r.state && r.state !== 'PENDING').map(r => ({
      type: 'review', actor: r.login, state: r.state, at: pr.lastActivity,
      body: r.state === 'APPROVED'
        ? 'Looks good to me.'
        : r.state === 'CHANGES_REQUESTED'
          ? 'Left some review comments — see inline.'
          : 'Left a comment on the diff.',
      seen: true,
    })),
    ...(merged ? [{
      type: 'status', at: pr.mergedAt, title: `Merged into ${pr.base} by ${(USERS[pr.author]||{}).name || pr.author}`,
      seen: true,
    }] : []),
  ];
  return (
    <div style={{ position: 'relative' }}>
      <div style={{
        position: 'absolute', left: 13, top: 4, bottom: 4,
        width: 1, background: t.hairline,
      }} />
      {items.map((ev, i) => (
        <TimelineItem key={i} ev={ev} isLast={i === items.length - 1} />
      ))}
      <div style={{
        marginTop: 6, marginLeft: 38, fontSize: 11.5, color: t.textFaint,
        fontStyle: 'italic',
      }}>
        Older activity…
      </div>
    </div>
  );
}

// ─── Mail-app shell ────────────────────────────────────────────
function PRMailApp({ initialTheme = 'light', initialOpts = {}, initialFilter = 'all', initialSelectedId = null }) {
  const [theme, setTheme] = React.useState(initialTheme);
  const [opts, setOptsState] = React.useState({ ...MAIL_DEFAULT_OPTS, ...initialOpts });
  const [activeFilter, setActiveFilter] = React.useState(initialFilter);
  const [readMap, setReadMap] = React.useState({});
  const [isRefreshing, setRefreshing] = React.useState(false);
  const [lastUpdated, setLastUpdated] = React.useState('just now');
  const [tweaksOpen, setTweaksOpen] = React.useState(false);

  const tokens = THEMES[theme];
  const repo = REPOS.find(r => r.id === 'spark-ios');
  const repoPRs = PULL_REQUESTS.filter(p => p.repo === 'spark-ios');

  // Tweaks handshake
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

  const counts = {
    review:    repoPRs.filter(p => p.needsMyReview).length,
    attention: repoPRs.filter(p => p.needsMyAttention).length,
    mine:      repoPRs.filter(p => p.mine && p.state === 'OPEN').length,
    involved:  repoPRs.filter(p => p.involved).length,
    mentions:  repoPRs.filter(p => p.mention).length,
    recent:    repoPRs.filter(p => p.state === 'MERGED').length,
  };

  const filtered = filterPRs(repoPRs, activeFilter);

  // Selected PR — default to first item in the current filter, fall back to attention/5107.
  const defaultSelectedId = initialSelectedId ?? filtered[0]?.id ?? 5107;
  const [selectedId, setSelectedId] = React.useState(defaultSelectedId);

  // Keep selection valid when filter changes
  React.useEffect(() => {
    if (!filtered.find(p => p.id === selectedId)) {
      setSelectedId(filtered[0]?.id ?? null);
    }
  }, [activeFilter]); // eslint-disable-line

  const selectedPR = repoPRs.find(p => p.id === selectedId);

  const toggleRead = (id) => {
    setReadMap(prev => {
      const pr = PULL_REQUESTS.find(p => p.id === id);
      const current = prev[id] ?? !pr.unread;
      return { ...prev, [id]: !current };
    });
  };
  const openPR = (pr) => { setSelectedId(pr.id); setReadMap(prev => ({ ...prev, [pr.id]: true })); };
  const refresh = () => { setRefreshing(true); setTimeout(() => { setRefreshing(false); setLastUpdated('just now'); }, 900); };

  return (
    <ThemeCtx.Provider value={tokens}>
      <MacShell width={1280} height={820}>
        <SourceList
          prs={filtered}
          activeFilter={activeFilter}
          onFilterChange={setActiveFilter}
          counts={counts}
          selectedId={selectedId}
          onOpen={openPR}
          onToggleRead={toggleRead}
          readMap={readMap}
          opts={opts}
          repo={repo}
        />
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, position: 'relative' }}>
          {selectedPR ? (
            <MailDetail
              pr={selectedPR}
              theme={theme}
              onThemeToggle={() => setTheme(x => x === 'light' ? 'dark' : 'light')}
              onRefresh={refresh}
              isRefreshing={isRefreshing}
              lastUpdated={lastUpdated}
              onToggleRead={toggleRead}
            />
          ) : (
            <MailEmpty />
          )}
          <MailTweaks opts={opts} setOpts={setOpts} visible={tweaksOpen} />
        </div>
      </MacShell>
    </ThemeCtx.Provider>
  );
}

// ─── Tweaks panel for mail variant ────────────────────────────
function MailTweaks({ opts, setOpts, visible }) {
  const t = useTheme();
  if (!visible) return null;
  const palettes = [
    { id: 'current', label: 'Roles' },
    { id: 'saturated', label: 'Saturated' },
    { id: 'muted', label: 'Muted' },
    { id: 'semantic', label: 'Urgency' },
  ];
  return (
    <div style={{
      position: 'absolute', right: 14, bottom: 14,
      width: 240, padding: 12, borderRadius: 10,
      background: t.cardBg, border: `0.5px solid ${t.borderStrong}`,
      boxShadow: '0 8px 24px rgba(0,0,0,0.18)',
      fontSize: 12, color: t.text, zIndex: 20,
    }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: t.textFaint, textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8 }}>Tweaks</div>

      <div style={{ marginBottom: 10 }}>
        <div style={{ fontSize: 11, color: t.textMuted, marginBottom: 4 }}>Rail palette</div>
        <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
          {palettes.map(p => (
            <button key={p.id} onClick={() => setOpts({ palette: p.id })}
              style={{
                fontSize: 11, padding: '3px 8px', borderRadius: 999,
                border: `0.5px solid ${opts.palette === p.id ? t.accent : t.border}`,
                background: opts.palette === p.id ? t.accentBg : t.contentBg,
                color: opts.palette === p.id ? t.accentText : t.text,
                fontWeight: 600, cursor: 'pointer',
              }}>{p.label}</button>
          ))}
        </div>
      </div>

      <label style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', cursor: 'pointer' }}>
        <input type="checkbox" checked={opts.showGauge} onChange={e => setOpts({ showGauge: e.target.checked })} />
        <span>Show CI gauge dots in list</span>
      </label>
      <label style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', cursor: 'pointer' }}>
        <input type="checkbox" checked={opts.showHints} onChange={e => setOpts({ showHints: e.target.checked })} />
        <span>Show preview snippet</span>
      </label>
    </div>
  );
}

Object.assign(window, { PRMailApp, MailRow, SourceList, FilterPills, MailDetail, MAIL_DEFAULT_OPTS });

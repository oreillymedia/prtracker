// Feed Variant C (polished) — Priority Lanes
// Supports tweakable: gauge style, density, color system, grouping, status
// emphasis (always vs hover), collapsible sections, author/branch placement.

// ─── Color systems ──────────────────────────────────────────────
const LANE_COLORS = {
  current: {
    review: '#0a84ff', attention: '#ff9500', mine: '#30b94d',
    involved: '#8e8e93', mentions: '#bf5af2', recent: '#8250df',
  },
  saturated: {
    review: '#2563eb', attention: '#ea580c', mine: '#16a34a',
    involved: '#64748b', mentions: '#9333ea', recent: '#7c3aed',
  },
  muted: {
    review: '#64748b', attention: '#64748b', mine: '#64748b',
    involved: '#94a3b8', mentions: '#64748b', recent: '#64748b',
  },
  semantic: {
    // encode urgency only: red/yellow/green/gray
    review: '#eab308', attention: '#dc2626', mine: '#16a34a',
    involved: '#94a3b8', mentions: '#eab308', recent: '#94a3b8',
  },
};

function priorityFor(section, palette = 'current') {
  const colors = LANE_COLORS[palette] || LANE_COLORS.current;
  const labels = {
    review: 'Awaiting review', attention: 'Action needed',
    mine: 'Authored', involved: 'Involved',
    mentions: 'Mentioned', recent: 'Merged',
  };
  return { color: colors[section] || '#8e8e93', label: labels[section] || '' };
}

// ─── Stage computation ──────────────────────────────────────────
function computeStages(pr) {
  const reviewOk = pr.review === 'APPROVED';
  const reviewBad = pr.review === 'CHANGES_REQUESTED';
  const reviewRun = pr.review === 'PENDING';
  const ciOk = pr.ci?.fail === 0 && pr.ci?.running === 0 && pr.ci?.pass === pr.ci?.total && pr.ci?.total > 0;
  const ciBad = pr.ci?.fail > 0;
  const ciRun = pr.ci?.running > 0;
  const mergeOk = pr.mergeable === 'CLEAN';
  const mergeBad = pr.mergeable === 'CONFLICTS';
  const mergeBlocked = pr.mergeable === 'BLOCKED';
  return [
    { key: 'review', label: 'Review', ok: reviewOk, bad: reviewBad, running: reviewRun },
    { key: 'ci', label: 'CI', ok: ciOk, bad: ciBad, running: ciRun },
    { key: 'merge', label: 'Merge', ok: mergeOk, bad: mergeBad, running: mergeBlocked },
  ];
}

// ─── Gauge renderers ────────────────────────────────────────────
function GaugePills({ stages }) {
  const t = useTheme();
  return (
    <div style={{ display: 'flex', gap: 4 }}>
      {stages.map(s => {
        let color = t.textFaint, fill = 'transparent', icon = null;
        if (s.ok) { color = t.approved; fill = t.approvedBg; icon = I.check(10, t.approved); }
        else if (s.bad) { color = t.changes; fill = t.changesBg; icon = I.x(10, t.changes); }
        else if (s.running) { color = t.pending; fill = t.pendingBg; icon = I.spinner(10, t.pending); }
        else { icon = I.dot(8, t.textFaint); }
        return (
          <div key={s.key} style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '2px 8px 2px 6px', borderRadius: 999,
            background: fill, color,
            fontSize: 10.5, fontWeight: 600,
            border: (s.ok || s.bad || s.running) ? 'none' : `0.5px dashed ${t.border}`,
          }}>{icon}{s.label}</div>
        );
      })}
    </div>
  );
}

function GaugeBar({ stages }) {
  const t = useTheme();
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      {stages.map((s, i) => {
        let color = t.hairline;
        if (s.ok) color = t.approved;
        else if (s.bad) color = t.changes;
        else if (s.running) color = t.pending;
        return (
          <React.Fragment key={s.key}>
            <div style={{
              display: 'flex', flexDirection: 'column', gap: 3, alignItems: 'center',
            }}>
              <div style={{
                width: 34, height: 4, borderRadius: 2,
                background: color,
                position: 'relative', overflow: 'hidden',
              }}>
                {s.running && (
                  <div style={{
                    position: 'absolute', inset: 0,
                    background: `linear-gradient(90deg, transparent, ${t.contentBg}aa, transparent)`,
                    animation: 'pr-shimmer 1.4s linear infinite',
                  }} />
                )}
              </div>
              <span style={{
                fontSize: 9.5, fontWeight: 600, letterSpacing: 0.2,
                color: (s.ok || s.bad || s.running) ? color : t.textFaint,
                textTransform: 'uppercase',
              }}>{s.label}</span>
            </div>
          </React.Fragment>
        );
      })}
    </div>
  );
}

function GaugeDots({ stages }) {
  const t = useTheme();
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      {stages.map((s, i) => {
        let color = t.textFaint;
        if (s.ok) color = t.approved;
        else if (s.bad) color = t.changes;
        else if (s.running) color = t.pending;
        return (
          <div key={s.key} style={{
            display: 'flex', alignItems: 'center', gap: 5,
          }}>
            <div style={{
              width: 8, height: 8, borderRadius: '50%',
              background: (s.ok || s.bad || s.running) ? color : 'transparent',
              border: (s.ok || s.bad || s.running) ? 'none' : `1.5px solid ${t.borderStrong}`,
              boxShadow: s.running ? `0 0 0 2.5px ${color}22` : 'none',
            }} className={s.running ? 'pr-pulse' : ''} />
            <span style={{
              fontSize: 10.5, fontWeight: 600, color,
              letterSpacing: 0.1,
            }}>{s.label}</span>
            {i < stages.length - 1 && (
              <div style={{ width: 10, height: 1, background: t.hairline, marginLeft: 2 }} />
            )}
          </div>
        );
      })}
    </div>
  );
}

function Gauge({ stages, style }) {
  if (style === 'bar') return <GaugeBar stages={stages} />;
  if (style === 'dots') return <GaugeDots stages={stages} />;
  return <GaugePills stages={stages} />;
}

// ─── Density presets ────────────────────────────────────────────
const DENSITY = {
  compact:     { padY: 7,  padX: 12, gap: 6,  gapOuter: 4, titleSize: 13,   metaTop: 5, rail: 3 },
  comfortable: { padY: 11, padX: 14, gap: 8,  gapOuter: 7, titleSize: 13.5, metaTop: 8, rail: 4 },
  spacious:    { padY: 14, padX: 16, gap: 10, gapOuter: 10, titleSize: 14,  metaTop: 10, rail: 5 },
};

// ─── Lane row ───────────────────────────────────────────────────
function PRLaneRow({ pr, read, section, onOpen, onToggleRead, opts }) {
  const t = useTheme();
  const [hover, setHover] = React.useState(false);
  const merged = pr.state === 'MERGED';
  const pri = priorityFor(section, opts.palette);
  const D = DENSITY[opts.density] || DENSITY.comfortable;
  const stages = computeStages(pr);
  const showStatusAlways = opts.statusEmphasis !== 'hover';

  const authorInMeta = opts.authorPlacement !== 'leading';
  const showBranch = opts.density !== 'compact';

  const hoverActions = (
    <div
      className="pr-row-actions"
      style={{
        opacity: 0, transition: 'opacity 0.15s',
        display: 'flex', gap: 4, marginLeft: 6,
      }}
    >
      <button
        onClick={(e) => { e.stopPropagation(); onToggleRead?.(pr.id); }}
        title={read ? 'Mark unread' : 'Mark read'}
        style={{
          width: 24, height: 24, borderRadius: 5,
          border: `0.5px solid ${t.border}`,
          background: t.cardBg, color: t.textMuted,
          cursor: 'pointer', display: 'inline-flex',
          alignItems: 'center', justifyContent: 'center',
        }}
      >{read ? I.eye(12, t.textMuted) : I.eyeOff(12, t.textMuted)}</button>
    </div>
  );

  return (
    <div
      className="pr-row-hover"
      onClick={() => onOpen?.(pr)}
      onContextMenu={(e) => { e.preventDefault(); onToggleRead?.(pr.id); }}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        background: t.cardBg,
        border: `0.5px solid ${hover ? t.borderStrong : t.border}`,
        borderRadius: 10,
        boxShadow: t.cardShadow,
        cursor: 'pointer',
        opacity: read ? 0.5 : 1,
        transition: 'opacity 0.18s, border-color 0.12s',
        display: 'flex', overflow: 'hidden',
      }}
    >
      {/* Priority rail */}
      <div style={{ width: D.rail, background: pri.color, flexShrink: 0 }} />

      <div style={{ flex: 1, padding: `${D.padY}px ${D.padX}px`, minWidth: 0 }}>
        {/* Top row: unread · number · title · age */}
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <UnreadDot on={!read} />
          {opts.authorPlacement === 'leading' && (
            <div style={{ alignSelf: 'center', marginRight: 2 }}>
              <Avatar user={pr.author} size={18} />
            </div>
          )}
          <span style={{ fontSize: 11.5, fontWeight: 600, color: t.textMuted, fontVariantNumeric: 'tabular-nums' }}>
            #{pr.number}
          </span>
          <div style={{
            fontSize: D.titleSize, fontWeight: read ? 500 : 600, color: t.text,
            flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{pr.title}</div>

          {/* Inline gauge on compact density (replaces meta row) */}
          {opts.density === 'compact' && showStatusAlways && !merged && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Gauge stages={stages} style={opts.gaugeStyle} />
            </div>
          )}

          <span style={{ fontSize: 10.5, color: t.textFaint, fontVariantNumeric: 'tabular-nums', marginLeft: 4 }}>
            {relTime(pr.lastActivity)}
          </span>
        </div>

        {/* Meta row (hidden when compact) */}
        {opts.density !== 'compact' && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: D.gap,
            marginTop: D.metaTop, minHeight: 22,
          }}>
            {authorInMeta && (
              <>
                <Avatar user={pr.author} size={opts.density === 'spacious' ? 20 : 18} />
                <span style={{ fontSize: 11.5, color: t.text, fontWeight: 500 }}>
                  {(USERS[pr.author] || {}).name || pr.author}
                </span>
              </>
            )}
            {!authorInMeta && (
              <span style={{ fontSize: 11.5, color: t.text, fontWeight: 500 }}>
                {(USERS[pr.author] || {}).name || pr.author}
              </span>
            )}
            {showBranch && (
              <>
                <span style={{ color: t.textFaint, fontSize: 11 }}>·</span>
                <span style={{
                  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                  fontSize: 10.5, color: t.textFaint,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 280,
                }}>{pr.branch}</span>
              </>
            )}

            <div style={{ flex: 1 }} />

            {!merged && (
              showStatusAlways ? (
                <Gauge stages={stages} style={opts.gaugeStyle} />
              ) : (
                <div style={{
                  opacity: hover ? 1 : 0, transition: 'opacity 0.15s',
                }}>
                  <Gauge stages={stages} style={opts.gaugeStyle} />
                </div>
              )
            )}
            {merged && (
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                fontSize: 11, fontWeight: 600, color: '#8250df',
                padding: '2px 8px', borderRadius: 999, background: 'rgba(130,80,223,0.12)',
              }}>
                {I.merged(11, '#8250df')} Merged {pr.mergedAt ? relTime(pr.mergedAt) : ''}
              </span>
            )}

            {hoverActions}
          </div>
        )}

        {/* Hint bubble */}
        {(pr.attentionHint || pr.mentionHint || pr.involvedHint) && opts.density !== 'compact' && (
          <div style={{
            marginTop: D.gap, padding: '6px 10px', borderRadius: 6,
            background: t.newHighlight,
            fontSize: 11.5, color: t.text, lineHeight: 1.45,
            textWrap: 'pretty',
          }}>
            {pr.attentionHint || pr.mentionHint || pr.involvedHint}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Collapsible section ────────────────────────────────────────
function LaneSection({ sectionKey, title, prs, readMap, onOpen, onToggleRead, opts, unified }) {
  const t = useTheme();
  const [collapsed, setCollapsed] = React.useState(false);
  const pri = priorityFor(sectionKey, opts.palette);
  const D = DENSITY[opts.density] || DENSITY.comfortable;

  if (unified || prs.length === 0 && !unified) {
    // In unified mode, we render flat (no section grouping)
  }

  if (prs.length === 0) {
    return (
      <div style={{ padding: '4px 20px 12px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '8px 0',
        }}>
          <div style={{ width: 8, height: 8, borderRadius: 2, background: pri.color, opacity: 0.5 }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: t.textMuted, letterSpacing: 0.1 }}>{title}</span>
          <span style={{ fontSize: 11, color: t.textFaint, fontStyle: 'italic' }}>— None</span>
        </div>
      </div>
    );
  }

  return (
    <div style={{ padding: '0 20px', marginBottom: 14 }}>
      <div
        onClick={() => setCollapsed(c => !c)}
        style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '6px 4px 8px', cursor: 'pointer', userSelect: 'none',
        }}
      >
        <span style={{
          color: t.textMuted, transition: 'transform 0.15s',
          transform: collapsed ? 'rotate(-90deg)' : 'rotate(0deg)',
          display: 'flex',
        }}>{I.chevD(11, t.textMuted)}</span>
        <div style={{ width: 8, height: 8, borderRadius: 2, background: pri.color }} />
        <span style={{ fontSize: 12.5, fontWeight: 700, color: t.text, letterSpacing: 0.1 }}>{title}</span>
        <span style={{
          fontSize: 10.5, fontWeight: 600, color: t.textMuted,
          padding: '1px 6px', borderRadius: 10, background: t.hairline,
        }}>{prs.length}</span>
      </div>
      {!collapsed && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: D.gapOuter }}>
          {prs.map(pr => {
            const read = readMap[pr.id] ?? !pr.unread;
            return (
              <PRLaneRow
                key={pr.id} pr={pr} read={read} section={sectionKey}
                onOpen={onOpen} onToggleRead={onToggleRead} opts={opts}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─── Main feed ──────────────────────────────────────────────────
function FeedLanes({ groupedSections, readMap, onOpen, onToggleRead, opts, unified, unifiedList }) {
  const t = useTheme();

  if (unified) {
    // Flat list sorted by lastActivity desc, no section headers
    const D = DENSITY[opts.density] || DENSITY.comfortable;
    return (
      <div style={{ padding: '8px 20px 20px', display: 'flex', flexDirection: 'column', gap: D.gapOuter }}>
        {unifiedList.map(({ pr, sectionKey }) => {
          const read = readMap[pr.id] ?? !pr.unread;
          return (
            <PRLaneRow
              key={pr.id} pr={pr} read={read} section={sectionKey}
              onOpen={onOpen} onToggleRead={onToggleRead} opts={opts}
            />
          );
        })}
      </div>
    );
  }

  return (
    <div style={{ paddingTop: 8, paddingBottom: 20 }}>
      {groupedSections.map(({ key, title, prs }) => (
        <LaneSection
          key={key} sectionKey={key} title={title} prs={prs}
          readMap={readMap} onOpen={onOpen} onToggleRead={onToggleRead}
          opts={opts}
        />
      ))}
    </div>
  );
}

// Inject shimmer keyframe (idempotent)
if (typeof document !== 'undefined' && !document.getElementById('pr-shimmer')) {
  const s = document.createElement('style');
  s.id = 'pr-shimmer';
  s.textContent = `@keyframes pr-shimmer { 0% { transform: translateX(-100%); } 100% { transform: translateX(100%); } }`;
  document.head.appendChild(s);
}

Object.assign(window, { FeedLanes, PRLaneRow, LaneSection, Gauge, LANE_COLORS, DENSITY, priorityFor, computeStages });

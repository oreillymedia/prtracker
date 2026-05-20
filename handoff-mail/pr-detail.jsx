// PR Detail view — timeline, comments, CI breakdown, quick reply.
// Seen items are visually faded; unseen items have a subtle highlight bar.

function PRDetail({ pr, onClose, readMap, onToggleRead }) {
  const t = useTheme();
  const timeline = window.TIMELINE_5107; // only have data for #5107 in demo
  const [reply, setReply] = React.useState('');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: t.contentBg }}>
      {/* Header */}
      <div style={{
        padding: '16px 24px 14px',
        borderBottom: `0.5px solid ${t.border}`,
        background: t.panelBg,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
          <button
            onClick={onClose}
            style={{
              height: 26, padding: '0 10px 0 6px', borderRadius: 6,
              border: `0.5px solid ${t.border}`, background: t.cardBg,
              color: t.text, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 3,
              fontSize: 12, fontWeight: 500,
            }}
          >
            {I.chevL(12, t.textMuted)}
            Feed
          </button>
          <span style={{ color: t.textFaint, fontSize: 11.5 }}>spark-ios</span>
          <span style={{ color: t.textFaint }}>/</span>
          <span style={{ fontSize: 11.5, color: t.textMuted, fontVariantNumeric: 'tabular-nums' }}>#{pr.number}</span>
          <div style={{ flex: 1 }} />
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            fontSize: 11, fontWeight: 600, color: t.approved,
            padding: '2px 8px', borderRadius: 999, background: t.approvedBg,
          }}>
            {I.pr(11, t.approved)} Open
          </span>
        </div>
        <h1 style={{
          margin: 0, fontSize: 18, fontWeight: 700, color: t.text,
          letterSpacing: -0.2, textWrap: 'pretty',
        }}>{pr.title}</h1>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10, marginTop: 8,
          fontSize: 12, color: t.textMuted,
        }}>
          <Avatar user={pr.author} size={18} />
          <span style={{ color: t.text, fontWeight: 500 }}>{(USERS[pr.author] || {}).name}</span>
          <span>wants to merge into</span>
          <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: t.text, background: t.hairline, padding: '1px 6px', borderRadius: 4 }}>{pr.base}</span>
          <span>from</span>
          <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: t.text, background: t.hairline, padding: '1px 6px', borderRadius: 4 }}>{pr.branch}</span>
          <span style={{ color: t.textFaint }}>·</span>
          <span>opened {relTime(pr.opened)}</span>
        </div>
      </div>

      {/* Two-column body */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Timeline */}
        <div style={{ flex: 1, overflow: 'auto', padding: '18px 24px 24px' }}>
          <div style={{ position: 'relative' }}>
            {/* Vertical rail */}
            <div style={{
              position: 'absolute', left: 13, top: 4, bottom: 4,
              width: 1, background: t.hairline,
            }} />
            {timeline.map((ev, i) => (
              <TimelineItem key={ev.id} ev={ev} isLast={i === timeline.length - 1} />
            ))}
          </div>

          {/* Quick reply */}
          <div style={{
            marginTop: 20, padding: 12, borderRadius: 10,
            background: t.cardBg, border: `0.5px solid ${t.border}`,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <Avatar user={ME.login} size={22} />
              <span style={{ fontSize: 12, fontWeight: 600, color: t.text }}>Reply as {ME.name}</span>
            </div>
            <textarea
              value={reply}
              onChange={e => setReply(e.target.value)}
              placeholder="Write a comment…"
              style={{
                width: '100%', minHeight: 70, padding: 10,
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

        {/* Right rail */}
        <div style={{
          width: 260, borderLeft: `0.5px solid ${t.border}`,
          padding: '18px 18px', overflow: 'auto',
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
                <span style={{ fontSize: 12, color: t.text, flex: 1 }}>
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
              <span><span style={{ color: t.approved, fontWeight: 600 }}>+{pr.additions}</span></span>
              <span><span style={{ color: t.changes, fontWeight: 600 }}>−{pr.deletions}</span></span>
              <span>·</span>
              <span>{pr.changedFiles} files</span>
            </div>
          </RailSection>

          <div style={{ marginTop: 16 }}>
            <button
              onClick={() => onToggleRead?.(pr.id)}
              style={{ ...btnSecondaryStyle(t), width: '100%', justifyContent: 'center' }}
            >
              Mark all as unread
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function RailSection({ title, children }) {
  const t = useTheme();
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{
        fontSize: 10.5, fontWeight: 700, color: t.textFaint,
        textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 8,
      }}>{title}</div>
      {children}
    </div>
  );
}

function RailRow({ label, value }) {
  const t = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '4px 0',
    }}>
      <span style={{ fontSize: 12, color: t.textMuted }}>{label}</span>
      {value}
    </div>
  );
}

function CIBreakdown({ ci }) {
  const t = useTheme();
  const rows = [
    { label: 'Build', state: 'pass', time: '2m 14s' },
    { label: 'Unit tests', state: 'pass', time: '3m 48s' },
    { label: 'SwiftLint', state: 'pass', time: '21s' },
    { label: 'Snapshot tests', state: 'pass', time: '1m 52s' },
    { label: 'UI tests', state: 'pass', time: '6m 01s' },
    { label: 'ASC: TestFlight upload', state: 'running', time: '3m' },
    { label: 'ASC: Validation', state: 'running', time: '1m' },
    { label: 'ASC: Symbolication', state: 'running', time: '—' },
    { label: 'ASC: Provisioning', state: 'running', time: '—' },
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {rows.map(r => (
        <div key={r.label} style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '3px 0',
        }}>
          {r.state === 'pass' ? I.check(11, t.ciPass) :
           r.state === 'fail' ? I.x(11, t.ciFail) :
           r.state === 'running' ? I.spinner(11, t.ciRunning) :
           I.dot(9, t.textFaint)}
          <span style={{ fontSize: 11.5, color: t.text, flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {r.label}
          </span>
          <span style={{ fontSize: 10.5, color: t.textFaint, fontVariantNumeric: 'tabular-nums' }}>{r.time}</span>
        </div>
      ))}
    </div>
  );
}

// ─── Timeline item ──────────────────────────────────────────
function TimelineItem({ ev, isLast }) {
  const t = useTheme();
  const seen = ev.seen;
  const user = USERS[ev.actor];

  // Dot color by type
  let dotColor = t.textFaint, dotBg = t.contentBg, innerIcon = null;
  if (ev.type === 'commit')      { dotColor = t.textMuted; innerIcon = I.commit(11, t.textMuted); }
  else if (ev.type === 'review') {
    if (ev.state === 'APPROVED') { dotColor = t.approved; innerIcon = I.check(11, '#fff'); dotBg = t.approved; }
    else if (ev.state === 'CHANGES_REQUESTED') { dotColor = t.changes; innerIcon = I.x(11, '#fff'); dotBg = t.changes; }
    else { dotColor = t.commented; innerIcon = I.comment(11, '#fff'); dotBg = t.commented; }
  }
  else if (ev.type === 'comment') { dotColor = t.accent; innerIcon = I.comment(11, '#fff'); dotBg = t.accent; }
  else if (ev.type === 'status')  { dotColor = t.pending; innerIcon = I.spinner(11, '#fff'); dotBg = t.pending; }
  else if (ev.type === 'opened')  { dotColor = t.approved; innerIcon = I.pr(11, '#fff'); dotBg = t.approved; }

  return (
    <div style={{
      position: 'relative', paddingLeft: 38, paddingBottom: isLast ? 0 : 14,
      opacity: seen ? 0.48 : 1,
      transition: 'opacity 0.2s',
    }}>
      {/* Dot */}
      <div style={{
        position: 'absolute', left: 4, top: 0,
        width: 20, height: 20, borderRadius: '50%',
        background: dotBg, border: `2px solid ${t.contentBg}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: ev.isNew ? `0 0 0 3px ${t.accent}22` : 'none',
      }}>
        {innerIcon}
      </div>

      {/* New indicator */}
      {ev.isNew && (
        <div style={{
          position: 'absolute', left: -4, top: -4, width: 4,
          height: 28, background: t.accent, borderRadius: 2,
        }} />
      )}

      {/* Content */}
      {(ev.type === 'comment' || ev.type === 'review') ? (
        <div style={{
          background: ev.isNew ? t.newHighlight : t.cardBg,
          border: `0.5px solid ${ev.isNew ? t.accent + '44' : t.border}`,
          borderRadius: 8, padding: '10px 12px',
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6,
          }}>
            <Avatar user={ev.actor} size={20} />
            <span style={{ fontSize: 12, fontWeight: 600, color: t.text }}>
              {user?.name || ev.actor}
            </span>
            {ev.type === 'review' && <ReviewPill state={ev.state} compact />}
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 10.5, color: t.textFaint }}>{relTime(ev.at)}</span>
          </div>
          <div style={{
            fontSize: 13, color: t.text, lineHeight: 1.5,
            textWrap: 'pretty',
          }}>{ev.body}</div>
        </div>
      ) : (
        <div style={{ paddingTop: 2 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5, color: t.text }}>
            {user && <Avatar user={ev.actor} size={18} />}
            <span style={{ color: t.textMuted }}>
              {user && <span style={{ color: t.text, fontWeight: 600 }}>{user.name}</span>}
              {user && ' '}
              {ev.type === 'commit' && 'pushed'}
              {ev.type === 'opened' && ev.title}
              {ev.type === 'status' && ev.title}
            </span>
            {ev.type === 'commit' && (
              <>
                <span style={{ color: t.text }}>{ev.title}</span>
                <span style={{
                  fontFamily: 'ui-monospace, monospace', fontSize: 10.5,
                  color: t.textFaint, background: t.hairline,
                  padding: '1px 5px', borderRadius: 3,
                }}>{ev.sha}</span>
              </>
            )}
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 10.5, color: t.textFaint }}>{relTime(ev.at)}</span>
          </div>
          {ev.details && (
            <ul style={{
              marginTop: 6, marginBottom: 0, paddingLeft: 26,
              fontSize: 11.5, color: t.textMuted, lineHeight: 1.55,
            }}>
              {ev.details.map(d => <li key={d}>{d}</li>)}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function btnPrimaryStyle(t) {
  return {
    height: 28, padding: '0 14px', borderRadius: 6,
    border: 'none', background: t.accent, color: '#fff',
    fontSize: 12.5, fontWeight: 600, cursor: 'pointer',
  };
}
function btnSecondaryStyle(t) {
  return {
    height: 28, padding: '0 12px', borderRadius: 6,
    border: `0.5px solid ${t.border}`, background: t.cardBg, color: t.text,
    fontSize: 12.5, fontWeight: 500, cursor: 'pointer',
    display: 'inline-flex', alignItems: 'center', gap: 4,
  };
}

Object.assign(window, { PRDetail });

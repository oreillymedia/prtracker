// Mail-style two-pane variant, todo-centric.
// Each PR is a todo list. Each non-mine message in a thread is a todo;
// the thread resolves when all non-mine messages are checked. A new
// non-mine message arriving in a resolved thread re-opens it.
//
// "Read/unread" is gone — completion state is the primary signal.

const MAIL_DEFAULT_OPTS = /*EDITMODE-BEGIN*/{
  "palette": "current",
  "ringStyle": "ring",
  "groupResolved": true,
  "showWhere": true
}/*EDITMODE-END*/;

const MAIL_FILTERS = [
  { id: 'all',       label: 'All' },
  { id: 'awaiting',  label: 'Awaiting me' },
  { id: 'open',      label: 'Open' },
  { id: 'mentions',  label: 'Mentions' },
  { id: 'mine',      label: 'Mine' },
  { id: 'done',      label: 'Done' },
  { id: 'merged',    label: 'Merged' },
];

// ─── Filter logic ──────────────────────────────────────────────
// "Awaiting me" = the PR has at least one open non-mine thread AND
// that thread's most recent message is NOT mine — i.e. the ball is
// in my court.
function ballInMyCourt(pr) {
  return (pr.threads || []).some(th => {
    if (threadIsResolved(th)) return false;
    const last = th.messages[th.messages.length - 1];
    return last && !last.isMine;
  });
}

function filterPRs(prs, filterId) {
  if (filterId === 'awaiting') return prs.filter(ballInMyCourt);
  if (filterId === 'open')     return prs.filter(p => prTodoCounts(p).open > 0);
  if (filterId === 'mine')     return prs.filter(p => p.mine && p.state === 'OPEN');
  if (filterId === 'mentions') return prs.filter(p => p.mention);
  if (filterId === 'done')     return prs.filter(p => p.state === 'OPEN' && prTodoCounts(p).open === 0 && prTodoCounts(p).total > 0);
  if (filterId === 'merged')   return prs.filter(p => p.state === 'MERGED');
  // 'all'
  return prs.slice().sort((a, b) => new Date(b.lastActivity) - new Date(a.lastActivity));
}

// Counts shown next to each filter pill.
function filterCounts(prs) {
  return {
    all:       prs.length,
    awaiting:  prs.filter(ballInMyCourt).length,
    open:      prs.filter(p => prTodoCounts(p).open > 0).length,
    mentions:  prs.filter(p => p.mention).length,
    mine:      prs.filter(p => p.mine && p.state === 'OPEN').length,
    done:      prs.filter(p => p.state === 'OPEN' && prTodoCounts(p).open === 0 && prTodoCounts(p).total > 0).length,
    merged:    prs.filter(p => p.state === 'MERGED').length,
  };
}

// Bucket for priority-rail color (purely visual — still useful)
function bucketFor(pr) {
  if (pr.state === 'MERGED')              return 'recent';
  if (ballInMyCourt(pr))                  return 'attention';
  if (pr.needsMyReview)                   return 'review';
  if (pr.mention)                         return 'mentions';
  if (pr.mine && pr.state === 'OPEN')     return 'mine';
  return 'involved';
}

// ─── Progress ring ──────────────────────────────────────────────
function TodoRing({ done, total, size = 24, awaiting = false, resolved = false }) {
  const t = useTheme();
  const stroke = 2.5;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = total === 0 ? 0 : done / total;
  const offset = c * (1 - pct);

  // Color logic:
  //  - all done → solid green check
  //  - any open + ball in my court → accent blue with progress
  //  - any open but waiting on someone else → muted with progress
  const ringTrack = t.hairline;
  let ringColor = t.textMuted;
  let label = `${done}/${total}`;
  if (resolved && total > 0) {
    ringColor = t.approved;
    label = '✓';
  } else if (awaiting) {
    ringColor = t.accent;
  } else {
    ringColor = t.textFaint;
  }

  return (
    <div style={{
      position: 'relative', width: size, height: size, flexShrink: 0,
    }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size/2} cy={size/2} r={r} stroke={ringTrack} strokeWidth={stroke} fill="none" />
        {total > 0 && (
          <circle cx={size/2} cy={size/2} r={r} stroke={ringColor} strokeWidth={stroke}
                  fill="none" strokeLinecap="round"
                  strokeDasharray={c} strokeDashoffset={offset}
                  style={{ transition: 'stroke-dashoffset 0.35s ease' }} />
        )}
      </svg>
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: size <= 18 ? 9 : (label === '✓' ? size * 0.55 : 10),
        fontWeight: 700,
        color: resolved ? t.approved : (awaiting ? t.accent : t.textMuted),
        fontVariantNumeric: 'tabular-nums',
        letterSpacing: -0.3,
        lineHeight: 1,
      }}>
        {total === 0 ? <span style={{ color: t.textFaint, fontSize: 11 }}>·</span> : label}
      </div>
    </div>
  );
}

// ─── Source list row ───────────────────────────────────────────
function MailRow({ pr, selected, onOpen, opts }) {
  const t = useTheme();
  const [hover, setHover] = React.useState(false);
  const merged = pr.state === 'MERGED';
  const counts = prTodoCounts(pr);
  const awaiting = ballInMyCourt(pr);
  const resolved = counts.total > 0 && counts.open === 0;
  const bucket = bucketFor(pr);
  const pri = priorityFor(bucket, opts.palette);

  // Dim if: PR is merged, or all threads resolved and not waiting on me
  const dim = (merged || resolved) && !selected;

  // Latest unresolved non-mine message preview
  let preview = null;
  for (const th of pr.threads || []) {
    if (threadIsResolved(th)) continue;
    const lastOpen = [...th.messages].reverse().find(m => !m.isMine && !m.done);
    if (lastOpen) {
      preview = { actor: lastOpen.actor, body: lastOpen.body, where: th.where };
      break;
    }
  }
  if (!preview && pr.attentionHint) preview = { body: pr.attentionHint };

  return (
    <div
      onClick={() => onOpen?.(pr)}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        padding: '10px 12px 11px 14px',
        cursor: 'pointer',
        background: selected ? t.rowSelect : (hover ? t.rowHover : 'transparent'),
        borderBottom: `0.5px solid ${t.hairline}`,
        opacity: dim ? 0.55 : 1,
        transition: 'background 0.1s, opacity 0.18s',
      }}
    >
      {/* Priority rail */}
      <div style={{
        position: 'absolute', left: 0, top: 6, bottom: 6,
        width: 3, borderRadius: 2, background: pri.color,
        opacity: dim ? 0.5 : 1,
      }} />

      <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
        {/* Progress ring */}
        <div style={{ paddingTop: 1 }}>
          <TodoRing
            done={counts.done}
            total={counts.total}
            size={24}
            awaiting={awaiting}
            resolved={resolved}
          />
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          {/* Top line: title · time */}
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
            <span style={{
              fontSize: 13,
              fontWeight: awaiting ? 700 : (resolved || merged ? 500 : 600),
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

          {/* Second line: avatar · author · #num · status chip */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 4 }}>
            <Avatar user={pr.author} size={15} />
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
            ) : resolved && counts.total > 0 ? (
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 3,
                fontSize: 10.5, fontWeight: 600, color: t.approved,
              }}>{I.check(11, t.approved)} Caught up</span>
            ) : awaiting ? (
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                fontSize: 10.5, fontWeight: 700, color: t.accent,
                padding: '1px 7px', borderRadius: 999, background: t.accentBg,
              }}>
                <span style={{ width: 5, height: 5, borderRadius: '50%', background: t.accent }} className="pr-pulse" />
                {counts.open === 1 ? '1 for me' : `${counts.openMessages} for me`}
              </span>
            ) : counts.open > 0 ? (
              <span style={{
                fontSize: 10.5, fontWeight: 500, color: t.textMuted,
              }}>waiting on others</span>
            ) : null}
          </div>

          {/* Preview line */}
          {preview && !resolved && !merged && (
            <div style={{
              marginTop: 5,
              fontSize: 11.5, color: t.textMuted, lineHeight: 1.4,
              overflow: 'hidden', textOverflow: 'ellipsis',
              display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
            }}>
              {preview.actor && (
                <span style={{ color: t.text, fontWeight: 500 }}>
                  {(USERS[preview.actor] || {}).name?.split(' ')[0] || preview.actor}:
                </span>
              )}{preview.actor ? ' ' : ''}
              {preview.body}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Filter pills strip ─────────────────────────────────────────
function FilterPills({ active, onChange, counts }) {
  const t = useTheme();
  return (
    <div style={{
      display: 'flex', gap: 6, padding: '8px 12px 10px',
      borderBottom: `0.5px solid ${t.hairline}`,
      overflowX: 'auto',
      scrollbarWidth: 'none',
    }}>
      {MAIL_FILTERS.map(f => {
        const n = counts[f.id] || 0;
        const isActive = active === f.id;
        const isAwaiting = f.id === 'awaiting' && n > 0;
        return (
          <button
            key={f.id}
            onClick={() => onChange(f.id)}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '4px 9px 4px 10px',
              borderRadius: 999,
              border: `0.5px solid ${isActive ? 'transparent' : t.border}`,
              background: isActive
                ? (isAwaiting ? t.accent : t.text)
                : (isAwaiting ? t.accentBg : t.cardBg),
              color: isActive
                ? '#fff'
                : (isAwaiting ? t.accent : t.text),
              fontSize: 11.5, fontWeight: isAwaiting ? 700 : 600, cursor: 'pointer',
              whiteSpace: 'nowrap',
              transition: 'all 0.1s',
            }}
          >
            {f.label}
            {n > 0 && (
              <span style={{
                fontSize: 10, fontWeight: 700,
                color: isActive ? '#fff' : (isAwaiting ? t.accent : t.textMuted),
                opacity: isActive ? 0.85 : 1,
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
function SourceList({ prs, activeFilter, onFilterChange, counts, selectedId, onOpen, opts, repo }) {
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

      <FilterPills active={activeFilter} onChange={onFilterChange} counts={counts} />

      <div style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
        {prs.length === 0 ? (
          <div style={{
            padding: 40, textAlign: 'center',
            fontSize: 12.5, color: t.textFaint, fontStyle: 'italic',
          }}>Nothing in this filter.</div>
        ) : (
          prs.map(pr => (
            <MailRow
              key={pr.id}
              pr={pr}
              selected={selectedId === pr.id}
              onOpen={onOpen}
              opts={opts}
            />
          ))
        )}
      </div>

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

// ─── Checkbox ─────────────────────────────────────────────────
function TodoCheckbox({ checked, onChange, size = 18, color }) {
  const t = useTheme();
  const fill = color || t.approved;
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onChange?.(!checked); }}
      style={{
        width: size, height: size, borderRadius: size * 0.28,
        border: checked ? 'none' : `1.5px solid ${t.borderStrong}`,
        background: checked ? fill : 'transparent',
        cursor: 'pointer', padding: 0, flexShrink: 0,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        transition: 'background 0.15s, border-color 0.15s',
      }}
      aria-checked={checked}
    >
      {checked && I.check(size - 6, '#fff')}
    </button>
  );
}

// ─── Message inside a thread ───────────────────────────────────
function ThreadMessage({ msg, threadDone, onToggle }) {
  const t = useTheme();
  const user = USERS[msg.actor] || { name: msg.actor };
  const isMine = msg.isMine;
  const showCheckbox = !isMine;
  const done = !!msg.done;
  const isNew = msg.isNew && !done;

  return (
    <div style={{
      display: 'flex', gap: 10, alignItems: 'flex-start',
      padding: '10px 12px',
      background: isNew ? t.newHighlight : 'transparent',
      borderLeft: isNew ? `3px solid ${t.accent}` : '3px solid transparent',
      opacity: done && !isMine ? 0.5 : 1,
      transition: 'opacity 0.2s, background 0.2s',
    }}>
      {showCheckbox ? (
        <div style={{ paddingTop: 1 }}>
          <TodoCheckbox checked={done} onChange={() => onToggle?.(msg.id)} size={18} />
        </div>
      ) : (
        <div style={{
          width: 18, height: 18, paddingTop: 1, flexShrink: 0,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <span style={{
            fontSize: 9, fontWeight: 700, color: t.textFaint,
            letterSpacing: 0.4, textTransform: 'uppercase',
          }}>↳</span>
        </div>
      )}
      <Avatar user={msg.actor} size={22} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginBottom: 3 }}>
          <span style={{
            fontSize: 12, fontWeight: 600, color: t.text,
            textDecoration: done && !isMine ? 'line-through' : 'none',
            textDecorationColor: t.textFaint,
          }}>{user.name}</span>
          {isMine && (
            <span style={{
              fontSize: 9.5, fontWeight: 600, color: t.textMuted,
              padding: '1px 5px', borderRadius: 3,
              background: t.hairline, textTransform: 'uppercase', letterSpacing: 0.3,
            }}>You</span>
          )}
          {isNew && (
            <span style={{
              fontSize: 9.5, fontWeight: 700, color: t.accent,
              padding: '1px 6px', borderRadius: 3,
              background: t.accentBg, textTransform: 'uppercase', letterSpacing: 0.4,
            }}>New</span>
          )}
          <span style={{ flex: 1 }} />
          <span style={{ fontSize: 10.5, color: t.textFaint }}>{relTime(msg.at)}</span>
        </div>
        <div style={{
          fontSize: 13, color: t.text, lineHeight: 1.5,
          textWrap: 'pretty',
          textDecoration: done && !isMine ? 'line-through' : 'none',
          textDecorationColor: t.textFaint + '99',
        }}>{msg.body}</div>
      </div>
    </div>
  );
}

// ─── Thread card ───────────────────────────────────────────────
function ThreadCard({ thread, onToggle, onAddReply, onResolveAll }) {
  const t = useTheme();
  const resolved = threadIsResolved(thread);
  const openCount = threadOpenCount(thread);
  const totalNonMine = thread.messages.filter(m => !m.isMine).length;
  const doneNonMine = totalNonMine - openCount;
  const isReviewComment = thread.kind === 'review-comment';
  const hasNew = threadHasNew(thread);

  const [collapsed, setCollapsed] = React.useState(resolved);
  // Reflect external resolution changes
  React.useEffect(() => { setCollapsed(resolved); }, [resolved]);

  const [replying, setReplying] = React.useState(false);
  const [reply, setReply] = React.useState('');

  // Border + accent for the card
  const accent = hasNew ? t.accent : (resolved ? t.approved : (thread.kindLabel === 'Changes requested' ? t.changes : t.textMuted));

  return (
    <div style={{
      borderRadius: 10,
      border: `0.5px solid ${hasNew ? t.accent + '66' : (resolved ? t.border : t.border)}`,
      background: t.cardBg,
      overflow: 'hidden',
      boxShadow: resolved ? 'none' : t.cardShadow,
      transition: 'border-color 0.2s, opacity 0.2s',
      opacity: resolved ? 0.78 : 1,
    }}>
      {/* Header */}
      <div
        onClick={() => setCollapsed(c => !c)}
        style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '10px 12px',
          background: resolved ? t.hairline : 'transparent',
          borderBottom: collapsed ? 'none' : `0.5px solid ${t.hairline}`,
          cursor: 'pointer',
          userSelect: 'none',
        }}
      >
        {/* Thread-state icon */}
        <div style={{
          width: 22, height: 22, borderRadius: 6,
          background: resolved ? t.approved : (hasNew ? t.accent : t.hairline),
          color: '#fff',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          {resolved
            ? I.check(13, '#fff')
            : <span style={{
                fontSize: 10, fontWeight: 700, color: hasNew ? '#fff' : t.textMuted,
                fontVariantNumeric: 'tabular-nums',
              }}>{doneNonMine}/{totalNonMine}</span>}
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
            {thread.kindLabel && (
              <span style={{
                fontSize: 10, fontWeight: 700,
                color: thread.kindLabel === 'Changes requested' ? t.changes : t.textMuted,
                textTransform: 'uppercase', letterSpacing: 0.5,
              }}>{thread.kindLabel}</span>
            )}
            {thread.kindLabel && <span style={{ color: t.textFaint }}>·</span>}
            <span style={{
              fontSize: 12.5, fontWeight: 600, color: t.text,
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              fontFamily: thread.where && thread.where !== 'general'
                ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : 'inherit',
            }}>
              {thread.where === 'general' ? 'Discussion' : thread.where}
            </span>
          </div>
          <div style={{ marginTop: 2, fontSize: 11, color: t.textMuted }}>
            {resolved ? 'Resolved' : `${openCount} open · ${thread.messages.length} message${thread.messages.length === 1 ? '' : 's'}`}
          </div>
        </div>

        {!resolved && totalNonMine > 1 && (
          <button
            onClick={(e) => { e.stopPropagation(); onResolveAll?.(thread.id); }}
            style={{
              fontSize: 11, fontWeight: 600, color: t.textMuted,
              padding: '3px 8px', borderRadius: 5,
              border: `0.5px solid ${t.border}`, background: t.contentBg,
              cursor: 'pointer',
            }}
            title="Mark all messages in this thread as addressed"
          >Resolve all</button>
        )}

        <span style={{
          color: t.textFaint,
          transform: collapsed ? 'rotate(-90deg)' : 'rotate(0deg)',
          transition: 'transform 0.15s',
          display: 'flex',
        }}>{I.chevD(11, t.textFaint)}</span>
      </div>

      {/* Body */}
      {!collapsed && (
        <div>
          {thread.messages.map(msg => (
            <ThreadMessage key={msg.id} msg={msg} threadDone={resolved} onToggle={(id) => onToggle?.(thread.id, id)} />
          ))}

          {/* Reply */}
          <div style={{
            padding: '8px 12px 10px',
            borderTop: `0.5px solid ${t.hairline}`,
            background: t.panelBg,
          }}>
            {replying ? (
              <div>
                <textarea
                  value={reply}
                  onChange={e => setReply(e.target.value)}
                  placeholder="Reply…"
                  autoFocus
                  style={{
                    width: '100%', minHeight: 54, padding: 8,
                    borderRadius: 6, border: `0.5px solid ${t.border}`,
                    background: t.contentBg, color: t.text,
                    fontSize: 12.5, fontFamily: 'inherit', resize: 'vertical',
                    outline: 'none', boxSizing: 'border-box',
                  }}
                />
                <div style={{ display: 'flex', gap: 6, marginTop: 6, justifyContent: 'flex-end' }}>
                  <button
                    onClick={() => { setReplying(false); setReply(''); }}
                    style={btnSecondaryStyle(t)}
                  >Cancel</button>
                  <button
                    onClick={() => { onAddReply?.(thread.id, reply); setReply(''); setReplying(false); }}
                    style={btnPrimaryStyle(t)}
                    disabled={!reply.trim()}
                  >Reply & resolve</button>
                </div>
              </div>
            ) : (
              <button
                onClick={() => setReplying(true)}
                style={{
                  fontSize: 11.5, color: t.textMuted, fontWeight: 500,
                  padding: '4px 8px', borderRadius: 5,
                  border: `0.5px dashed ${t.border}`, background: 'transparent',
                  cursor: 'pointer',
                  display: 'inline-flex', alignItems: 'center', gap: 5,
                }}
              >
                {I.comment(11, t.textMuted)}
                Reply
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Detail header ─────────────────────────────────────────────
function MailDetailHeader({ pr, theme, onThemeToggle, onRefresh, isRefreshing, lastUpdated, todoCounts }) {
  const t = useTheme();
  const merged = pr.state === 'MERGED';
  const resolved = todoCounts.total > 0 && todoCounts.open === 0;

  return (
    <div style={{
      padding: '10px 18px 12px',
      borderBottom: `0.5px solid ${t.border}`,
      background: t.panelBg,
      backdropFilter: 'blur(40px) saturate(180%)',
      WebkitBackdropFilter: 'blur(40px) saturate(180%)',
    }}>
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
        <button onClick={onRefresh} disabled={isRefreshing} style={iconBtnStyle(t)} title="Refresh">
          <span style={{ animation: isRefreshing ? 'pr-spin 1s linear infinite' : 'none', display: 'flex' }}>
            {I.refresh(12, t.textMuted)}
          </span>
        </button>
        <button onClick={onThemeToggle} style={iconBtnStyle(t)}>
          {theme === 'dark' ? I.sun(12, t.textMuted) : I.moon(12, t.textMuted)}
        </button>
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
        <span style={branchPill(t)}>{pr.base}</span>
        <span>from</span>
        <span style={branchPill(t)}>{pr.branch}</span>
        <span style={{ color: t.textFaint }}>·</span>
        <span>opened {relTime(pr.opened)}</span>
      </div>

      {/* Todo summary bar */}
      {todoCounts.total > 0 && (
        <div style={{
          marginTop: 12,
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '8px 10px', borderRadius: 8,
          background: resolved ? t.approvedBg : t.accentBg,
          border: `0.5px solid ${resolved ? t.approved + '44' : t.accent + '33'}`,
        }}>
          <TodoRing
            done={todoCounts.done}
            total={todoCounts.total}
            size={32}
            awaiting={!resolved && todoCounts.open > 0}
            resolved={resolved}
          />
          <div style={{ flex: 1 }}>
            <div style={{
              fontSize: 13, fontWeight: 700,
              color: resolved ? t.approved : t.accentText,
            }}>
              {resolved
                ? 'All caught up'
                : `${todoCounts.done} of ${todoCounts.total} threads resolved`}
            </div>
            <div style={{ fontSize: 11.5, color: t.textMuted, marginTop: 1 }}>
              {resolved
                ? 'No outstanding feedback. Ready when CI is.'
                : `${todoCounts.openMessages} open ${todoCounts.openMessages === 1 ? 'message' : 'messages'} to address`}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function branchPill(t) {
  return {
    fontFamily: 'ui-monospace, monospace', fontSize: 10.5,
    color: t.text, background: t.hairline,
    padding: '1px 5px', borderRadius: 4,
  };
}
function iconBtnStyle(t) {
  return {
    height: 24, width: 24, borderRadius: 5,
    border: `0.5px solid ${t.border}`,
    background: t.cardBg, color: t.textMuted, cursor: 'pointer',
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
  };
}

// ─── Detail body — thread list ─────────────────────────────────
function MailDetail({ pr, theme, onThemeToggle, onRefresh, isRefreshing, lastUpdated, threadOverrides, onToggleMessage, onResolveThread, opts }) {
  const t = useTheme();
  const threads = (pr.threads || []).map(th => applyOverrides(th, threadOverrides));
  const todoCounts = {
    total: threads.length,
    done: threads.filter(threadIsResolved).length,
    open: threads.filter(th => !threadIsResolved(th)).length,
    openMessages: threads.reduce((s, th) => s + threadOpenCount(th), 0),
  };

  const openThreads = threads.filter(th => !threadIsResolved(th));
  const resolvedThreads = threads.filter(threadIsResolved);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minWidth: 0, background: t.contentBg }}>
      <MailDetailHeader pr={pr} theme={theme} onThemeToggle={onThemeToggle} onRefresh={onRefresh} isRefreshing={isRefreshing} lastUpdated={lastUpdated} todoCounts={todoCounts} />

      <div style={{ flex: 1, display: 'flex', overflow: 'hidden', minHeight: 0 }}>
        <div style={{ flex: 1, overflow: 'auto', padding: '14px 20px 22px', minWidth: 0 }}>
          {threads.length === 0 && (
            <div style={{
              padding: 24, borderRadius: 10,
              background: t.cardBg, border: `0.5px solid ${t.border}`,
              fontSize: 13, color: t.textMuted, textAlign: 'center',
            }}>
              No threads on this PR yet.
            </div>
          )}

          {openThreads.length > 0 && (
            <>
              <SectionHeading
                label="Open"
                count={openThreads.length}
                accent={t.accent}
              />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 18 }}>
                {openThreads.map(th => (
                  <ThreadCard
                    key={th.id}
                    thread={th}
                    onToggle={onToggleMessage}
                    onResolveAll={onResolveThread}
                    onAddReply={(threadId, body) => {
                      // The prototype doesn't persist the body — just resolves the thread
                      onResolveThread?.(threadId);
                    }}
                  />
                ))}
              </div>
            </>
          )}

          {resolvedThreads.length > 0 && (
            <>
              <SectionHeading
                label="Resolved"
                count={resolvedThreads.length}
                accent={t.approved}
                collapsible
              />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {resolvedThreads.map(th => (
                  <ThreadCard
                    key={th.id}
                    thread={th}
                    onToggle={onToggleMessage}
                  />
                ))}
              </div>
            </>
          )}
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
        </div>
      </div>
    </div>
  );
}

function SectionHeading({ label, count, accent, collapsible }) {
  const t = useTheme();
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', gap: 8,
      padding: '8px 2px 10px',
    }}>
      <div style={{ width: 6, height: 6, borderRadius: '50%', background: accent }} />
      <span style={{
        fontSize: 11, fontWeight: 700, color: t.text,
        textTransform: 'uppercase', letterSpacing: 0.6,
      }}>{label}</span>
      <span style={{
        fontSize: 11, fontWeight: 600, color: t.textMuted,
        padding: '1px 6px', borderRadius: 10, background: t.hairline,
      }}>{count}</span>
      <div style={{ flex: 1 }} />
    </div>
  );
}

// Apply user toggle overrides to a thread
function applyOverrides(thread, overrides) {
  if (!overrides) return thread;
  const myOverrides = overrides[thread.id];
  if (!myOverrides) return thread;
  return {
    ...thread,
    messages: thread.messages.map(m => {
      if (myOverrides[m.id] != null) return { ...m, done: myOverrides[m.id] };
      return m;
    }),
  };
}

// ─── Mail-app shell ────────────────────────────────────────────
function PRMailApp({ initialTheme = 'light', initialOpts = {}, initialFilter = 'all', initialSelectedId = null }) {
  const [theme, setTheme] = React.useState(initialTheme);
  const [opts, setOptsState] = React.useState({ ...MAIL_DEFAULT_OPTS, ...initialOpts });
  const [activeFilter, setActiveFilter] = React.useState(initialFilter);
  // threadOverrides: { [threadId]: { [messageId]: bool } } — local toggles
  const [threadOverrides, setThreadOverrides] = React.useState({});
  const [isRefreshing, setRefreshing] = React.useState(false);
  const [lastUpdated, setLastUpdated] = React.useState('just now');
  const [tweaksOpen, setTweaksOpen] = React.useState(false);

  const tokens = THEMES[theme];
  const repo = REPOS.find(r => r.id === 'spark-ios');
  const baseRepoPRs = PULL_REQUESTS.filter(p => p.repo === 'spark-ios');

  // Apply overrides for every PR so derived counts reflect the user's toggles
  const repoPRs = React.useMemo(() => baseRepoPRs.map(pr => ({
    ...pr,
    threads: (pr.threads || []).map(th => applyOverrides(th, threadOverrides)),
  })), [threadOverrides]);

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

  const counts = filterCounts(repoPRs);
  const filtered = filterPRs(repoPRs, activeFilter);

  // Sort filtered: awaiting-me first, then by activity desc
  const sortedFiltered = React.useMemo(() => {
    return filtered.slice().sort((a, b) => {
      const aw = ballInMyCourt(a) ? 0 : 1;
      const bw = ballInMyCourt(b) ? 0 : 1;
      if (aw !== bw) return aw - bw;
      return new Date(b.lastActivity) - new Date(a.lastActivity);
    });
  }, [filtered]);

  const defaultSelectedId = initialSelectedId ?? sortedFiltered[0]?.id ?? 5107;
  const [selectedId, setSelectedId] = React.useState(defaultSelectedId);

  React.useEffect(() => {
    if (!sortedFiltered.find(p => p.id === selectedId)) {
      setSelectedId(sortedFiltered[0]?.id ?? null);
    }
  }, [activeFilter]); // eslint-disable-line

  const selectedPR = repoPRs.find(p => p.id === selectedId);

  // Toggle a single message
  const onToggleMessage = (threadId, messageId) => {
    const pr = baseRepoPRs.find(p => p.threads?.some(th => th.id === threadId));
    if (!pr) return;
    const thread = pr.threads.find(th => th.id === threadId);
    const msg = thread.messages.find(m => m.id === messageId);
    if (!msg || msg.isMine) return;
    const currentOverride = threadOverrides[threadId]?.[messageId];
    const currentDone = currentOverride != null ? currentOverride : !!msg.done;
    setThreadOverrides(prev => ({
      ...prev,
      [threadId]: { ...(prev[threadId] || {}), [messageId]: !currentDone },
    }));
  };

  // Resolve every non-mine message in a thread
  const onResolveThread = (threadId) => {
    const pr = baseRepoPRs.find(p => p.threads?.some(th => th.id === threadId));
    if (!pr) return;
    const thread = pr.threads.find(th => th.id === threadId);
    const updates = {};
    thread.messages.forEach(m => { if (!m.isMine) updates[m.id] = true; });
    setThreadOverrides(prev => ({
      ...prev,
      [threadId]: { ...(prev[threadId] || {}), ...updates },
    }));
  };

  const refresh = () => { setRefreshing(true); setTimeout(() => { setRefreshing(false); setLastUpdated('just now'); }, 900); };

  return (
    <ThemeCtx.Provider value={tokens}>
      <MacShell width={1280} height={820}>
        <SourceList
          prs={sortedFiltered}
          activeFilter={activeFilter}
          onFilterChange={setActiveFilter}
          counts={counts}
          selectedId={selectedId}
          onOpen={(pr) => setSelectedId(pr.id)}
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
              threadOverrides={threadOverrides}
              onToggleMessage={onToggleMessage}
              onResolveThread={onResolveThread}
              opts={opts}
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
        <input type="checkbox" checked={opts.groupResolved} onChange={e => setOpts({ groupResolved: e.target.checked })} />
        <span>Group resolved threads</span>
      </label>
      <label style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', cursor: 'pointer' }}>
        <input type="checkbox" checked={opts.showWhere} onChange={e => setOpts({ showWhere: e.target.checked })} />
        <span>Show file/line on threads</span>
      </label>
    </div>
  );
}

Object.assign(window, { PRMailApp, MailRow, SourceList, FilterPills, MailDetail, ThreadCard, TodoRing, MAIL_DEFAULT_OPTS });

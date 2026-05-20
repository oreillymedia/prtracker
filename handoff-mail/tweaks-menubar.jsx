// Tweaks panel (floating) + menu-bar preview.
// - Tweaks: gauge style, density, palette, grouping, status emphasis,
//           author placement. Persists via __edit_mode_set_keys.
// - MenuBarPreview: a small macOS menu-bar strip with PR tracker icon + badge,
//   and an optional dropdown panel showing quick counts.

function TweaksPanel({ opts, setOpts, visible }) {
  const t = useTheme();
  if (!visible) return null;

  const Row = ({ label, children }) => (
    <div style={{ marginBottom: 12 }}>
      <div style={{
        fontSize: 10.5, fontWeight: 700, color: t.textFaint,
        textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6,
      }}>{label}</div>
      {children}
    </div>
  );

  const Seg = ({ value, options, onChange }) => (
    <div style={{
      display: 'flex', background: t.hairline, borderRadius: 6, padding: 2,
      gap: 2,
    }}>
      {options.map(o => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          style={{
            flex: 1, padding: '5px 8px', borderRadius: 4,
            border: 'none', cursor: 'pointer',
            background: value === o.value ? t.cardBg : 'transparent',
            color: value === o.value ? t.text : t.textMuted,
            boxShadow: value === o.value ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            fontSize: 11, fontWeight: 600,
            whiteSpace: 'nowrap',
          }}
        >{o.label}</button>
      ))}
    </div>
  );

  return (
    <div style={{
      position: 'absolute', right: 16, top: 60, zIndex: 30,
      width: 260, padding: 14, borderRadius: 12,
      background: t.cardBg, border: `0.5px solid ${t.border}`,
      boxShadow: '0 8px 30px rgba(0,0,0,0.18), 0 2px 6px rgba(0,0,0,0.08)',
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6, marginBottom: 12,
      }}>
        <span style={{ fontSize: 13, fontWeight: 700, color: t.text }}>Tweaks</span>
        <span style={{ fontSize: 10.5, color: t.textFaint }}>Option C · Priority Lanes</span>
      </div>

      <Row label="Gauge style">
        <Seg value={opts.gaugeStyle} onChange={v => setOpts({ gaugeStyle: v })} options={[
          { value: 'pills', label: 'Pills' },
          { value: 'bar', label: 'Bars' },
          { value: 'dots', label: 'Dots' },
        ]} />
      </Row>

      <Row label="Density">
        <Seg value={opts.density} onChange={v => setOpts({ density: v })} options={[
          { value: 'compact', label: 'Compact' },
          { value: 'comfortable', label: 'Comfy' },
          { value: 'spacious', label: 'Spacious' },
        ]} />
      </Row>

      <Row label="Color">
        <Seg value={opts.palette} onChange={v => setOpts({ palette: v })} options={[
          { value: 'current', label: 'Color' },
          { value: 'saturated', label: 'Sat' },
          { value: 'muted', label: 'Mute' },
          { value: 'semantic', label: 'Urgency' },
        ]} />
      </Row>

      <Row label="Grouping">
        <Seg value={opts.grouping} onChange={v => setOpts({ grouping: v })} options={[
          { value: 'sections', label: 'Sections' },
          { value: 'unified', label: 'Unified' },
        ]} />
      </Row>

      <Row label="Status emphasis">
        <Seg value={opts.statusEmphasis} onChange={v => setOpts({ statusEmphasis: v })} options={[
          { value: 'always', label: 'Always' },
          { value: 'hover', label: 'On hover' },
        ]} />
      </Row>

      <Row label="Author avatar">
        <Seg value={opts.authorPlacement} onChange={v => setOpts({ authorPlacement: v })} options={[
          { value: 'meta', label: 'In meta' },
          { value: 'leading', label: 'Leading title' },
        ]} />
      </Row>
    </div>
  );
}

// ─── Menu-bar preview ─────────────────────────────────────────
function MenuBarPreview({ dark = false, showDropdown = true, attentionCount = 3, reviewCount = 2 }) {
  const t = dark ? THEMES.dark : THEMES.light;
  const bg = dark
    ? 'linear-gradient(180deg, rgba(40,40,44,0.92), rgba(30,30,34,0.92))'
    : 'linear-gradient(180deg, rgba(255,255,255,0.86), rgba(245,245,248,0.86))';

  return (
    <div style={{
      width: 520, background: dark ? '#3a3a42' : '#e9e7e1',
      borderRadius: 8, padding: 14,
      fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
    }}>
      {/* Mac menu bar */}
      <div style={{
        height: 26, background: bg,
        backdropFilter: 'blur(40px) saturate(180%)',
        WebkitBackdropFilter: 'blur(40px) saturate(180%)',
        borderRadius: 6,
        display: 'flex', alignItems: 'center', gap: 16, padding: '0 12px',
        fontSize: 12.5, color: dark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.8)',
        border: dark ? '0.5px solid rgba(255,255,255,0.08)' : '0.5px solid rgba(0,0,0,0.08)',
      }}>
        {/* Left: apple + app menu */}
        <span style={{ fontWeight: 600 }}></span>
        <span style={{ fontWeight: 700 }}>PR Tracker</span>
        <span style={{ opacity: 0.7 }}>File</span>
        <span style={{ opacity: 0.7 }}>View</span>
        <span style={{ opacity: 0.7 }}>Window</span>
        <span style={{ opacity: 0.7 }}>Help</span>
        <div style={{ flex: 1 }} />
        {/* Status icons */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          {/* PR Tracker icon with badge */}
          <div style={{ position: 'relative', display: 'flex' }}>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <circle cx="4" cy="4" r="1.6" stroke={dark ? '#fff' : '#000'} strokeOpacity="0.85" strokeWidth="1.3"/>
              <circle cx="4" cy="12" r="1.6" stroke={dark ? '#fff' : '#000'} strokeOpacity="0.85" strokeWidth="1.3"/>
              <circle cx="12" cy="12" r="1.6" stroke={dark ? '#fff' : '#000'} strokeOpacity="0.85" strokeWidth="1.3"/>
              <path d="M4 5.6v4.8M12 10.4V6a2 2 0 0 0-2-2H7.3M7.3 4l1.4-1.5M7.3 4l1.4 1.5" stroke={dark ? '#fff' : '#000'} strokeOpacity="0.85" strokeWidth="1.3" strokeLinecap="round"/>
            </svg>
            {attentionCount > 0 && (
              <div style={{
                position: 'absolute', top: -4, right: -6,
                minWidth: 13, height: 13, padding: '0 3px',
                borderRadius: 7, background: '#ff3b30',
                color: '#fff', fontSize: 9, fontWeight: 700,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: '0 0 0 1.5px ' + (dark ? '#3a3a42' : '#e9e7e1'),
              }}>{attentionCount}</div>
            )}
          </div>
          <span style={{ opacity: 0.7, fontSize: 11.5 }}>🔋 82%</span>
          <span style={{ opacity: 0.7, fontSize: 11.5 }}>Thu 10:55 AM</span>
        </div>
      </div>

      {/* Dropdown */}
      {showDropdown && (
        <div style={{ marginTop: 6, display: 'flex', justifyContent: 'flex-end' }}>
          <div style={{
            width: 320, background: dark ? 'rgba(44,44,46,0.94)' : 'rgba(255,255,255,0.96)',
            backdropFilter: 'blur(40px) saturate(200%)',
            WebkitBackdropFilter: 'blur(40px) saturate(200%)',
            borderRadius: 10, padding: '8px 0',
            border: dark ? '0.5px solid rgba(255,255,255,0.1)' : '0.5px solid rgba(0,0,0,0.08)',
            boxShadow: '0 16px 40px rgba(0,0,0,0.28), 0 2px 8px rgba(0,0,0,0.1)',
            fontSize: 12.5,
            color: dark ? 'rgba(255,255,255,0.92)' : 'rgba(0,0,0,0.88)',
            position: 'relative',
          }}>
            {/* Arrow */}
            <div style={{
              position: 'absolute', top: -5, right: 40,
              width: 10, height: 10,
              background: dark ? 'rgba(44,44,46,0.94)' : 'rgba(255,255,255,0.96)',
              transform: 'rotate(45deg)',
              borderTop: dark ? '0.5px solid rgba(255,255,255,0.1)' : '0.5px solid rgba(0,0,0,0.08)',
              borderLeft: dark ? '0.5px solid rgba(255,255,255,0.1)' : '0.5px solid rgba(0,0,0,0.08)',
            }} />
            <div style={{
              padding: '6px 14px 8px', fontSize: 11,
              color: dark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.5)',
              display: 'flex', justifyContent: 'space-between',
            }}>
              <span style={{ fontWeight: 600 }}>spark-ios</span>
              <span>Updated just now</span>
            </div>
            <MenuItem icon="dot" color="#ff9500" label="Needs my attention" count={attentionCount} dark={dark} />
            <MenuItem icon="eye" color="#0a84ff" label="Needs my review" count={reviewCount} dark={dark} />
            <MenuItem icon="pr" color="#30b94d" label="My open PRs" count={2} dark={dark} />
            <MenuItem icon="at" color="#bf5af2" label="Mentions" count={1} dark={dark} />
            <Divider dark={dark} />
            <MenuItem icon="highlight" label="#5107 Fetch badge data…" sub='Iris: "Testing on device now!"' dark={dark} />
            <Divider dark={dark} />
            <MenuItem label="Open PR Tracker" dark={dark} />
            <MenuItem label="Refresh now" hint="⌘R" dark={dark} />
            <MenuItem label="Preferences…" hint="⌘," dark={dark} />
            <Divider dark={dark} />
            <MenuItem label="Quit" hint="⌘Q" dark={dark} />
          </div>
        </div>
      )}
    </div>
  );
}

function MenuItem({ icon, color, label, count, sub, hint, dark }) {
  const [hover, setHover] = React.useState(false);
  const text = dark ? 'rgba(255,255,255,0.92)' : 'rgba(0,0,0,0.88)';
  const muted = dark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.5)';
  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '5px 14px', cursor: 'default',
        background: hover ? (dark ? '#0a84ff' : '#0a84ff') : 'transparent',
        color: hover ? '#fff' : text,
      }}
    >
      {icon === 'dot' && <div style={{ width: 8, height: 8, borderRadius: '50%', background: hover ? '#fff' : color }} />}
      {icon === 'eye' && <span style={{ color: hover ? '#fff' : color, display: 'flex' }}>{I.eye(12, hover ? '#fff' : color)}</span>}
      {icon === 'pr' && <span style={{ color: hover ? '#fff' : color, display: 'flex' }}>{I.pr(12, hover ? '#fff' : color)}</span>}
      {icon === 'at' && <span style={{ color: hover ? '#fff' : color, display: 'flex' }}>{I.at(12, hover ? '#fff' : color)}</span>}
      {icon === 'highlight' && <div style={{ width: 6, height: 6, borderRadius: '50%', background: hover ? '#fff' : '#0a84ff' }} />}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12.5, fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</div>
        {sub && <div style={{ fontSize: 10.5, color: hover ? 'rgba(255,255,255,0.8)' : muted, fontStyle: 'italic', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{sub}</div>}
      </div>
      {count != null && (
        <span style={{
          fontSize: 11, fontWeight: 600,
          color: hover ? '#fff' : muted,
        }}>{count}</span>
      )}
      {hint && (
        <span style={{ fontSize: 11, color: hover ? 'rgba(255,255,255,0.8)' : muted }}>{hint}</span>
      )}
    </div>
  );
}

function Divider({ dark }) {
  return (
    <div style={{
      height: 0.5, margin: '4px 10px',
      background: dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)',
    }} />
  );
}

Object.assign(window, { TweaksPanel, MenuBarPreview });

import { useState } from 'react';
import { useStore, applyColorMode } from '../store';

type SettingsPage = null | 'appearance' | 'rules' | 'style' | 'handle';

interface Props {
  onClose: () => void;
  onOpenTutorial: () => void;
}

export function SettingsPanel({ onClose, onOpenTutorial }: Props) {
  const {
    colorMode, setColorMode,
    customRules, addRule, removeRule, updateRule,
  } = useStore();

  const [page, setPage] = useState<SettingsPage>(null);
  const [handle, setHandle] = useState(() => localStorage.getItem('userHandle') || '');
  const [styleProfile, setStyleProfile] = useState(() => localStorage.getItem('styleProfile') || '');

  const saveHandle = (v: string) => {
    setHandle(v);
    localStorage.setItem('userHandle', v);
  };

  const saveStyle = (v: string) => {
    setStyleProfile(v);
    localStorage.setItem('styleProfile', v);
  };

  const menuItems = [
    { key: 'handle' as const, icon: '👤', label: 'Your Handle', sub: handle ? `@${handle}` : 'Set your IG handle' },
    { key: 'appearance' as const, icon: '🎨', label: 'Appearance', sub: colorMode === 'dark' ? 'Dark' : colorMode === 'day' ? 'Day' : 'System' },
    { key: 'rules' as const, icon: '📋', label: 'The Rules', sub: `${customRules.length} rules` },
    { key: 'style' as const, icon: '✍️', label: 'AI Style Profile', sub: styleProfile.trim() ? 'Trained' : 'Not set' },
  ];

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 500,
        background: 'var(--bg)', display: 'flex', flexDirection: 'column',
      }}
    >
      {/* Header */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '16px 20px',
        borderBottom: '1px solid var(--border2)',
        position: 'relative',
      }}>
        {page ? (
          <button
            onClick={() => setPage(null)}
            style={{
              background: 'none', border: 'none', cursor: 'pointer',
              color: 'var(--gold)', fontSize: 20, lineHeight: 1, padding: '4px 8px 4px 0',
            }}
          >←</button>
        ) : (
          <div style={{ width: 32 }} />
        )}
        <p style={{
          fontSize: 13, fontWeight: 700, letterSpacing: '0.14em',
          color: 'var(--text)', textTransform: 'uppercase',
        }}>
          {page === 'handle' ? 'Your Handle' :
           page === 'appearance' ? 'Appearance' :
           page === 'rules' ? 'The Rules' :
           page === 'style' ? 'AI Style Profile' :
           'Settings'}
        </p>
        <button
          onClick={onClose}
          style={{
            background: 'none', border: 'none', cursor: 'pointer',
            color: 'var(--text3)', fontSize: 22, lineHeight: 1, padding: '4px 0 4px 8px',
          }}
        >×</button>
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
        {!page && (
          <>
            {menuItems.map(item => (
              <button
                key={item.key}
                onClick={() => setPage(item.key)}
                style={{
                  width: '100%', display: 'flex', alignItems: 'center',
                  gap: 16, padding: '16px 20px',
                  background: 'none', border: 'none', cursor: 'pointer',
                  borderBottom: '1px solid var(--border)',
                  textAlign: 'left',
                }}
                onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg2)')}
                onMouseLeave={e => (e.currentTarget.style.background = 'none')}
              >
                <span style={{ fontSize: 20, width: 28, textAlign: 'center' }}>{item.icon}</span>
                <div style={{ flex: 1 }}>
                  <p style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)', marginBottom: 2 }}>{item.label}</p>
                  <p style={{ fontSize: 11, color: 'var(--text3)' }}>{item.sub}</p>
                </div>
                <span style={{ color: 'var(--text3)', fontSize: 16 }}>›</span>
              </button>
            ))}

            <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

            <button
              onClick={() => { onOpenTutorial(); onClose(); }}
              style={{
                width: '100%', display: 'flex', alignItems: 'center', gap: 16,
                padding: '16px 20px', background: 'none', border: 'none', cursor: 'pointer',
                borderBottom: '1px solid var(--border)',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg2)')}
              onMouseLeave={e => (e.currentTarget.style.background = 'none')}
            >
              <span style={{ fontSize: 20, width: 28, textAlign: 'center' }}>👁️</span>
              <div style={{ flex: 1 }}>
                <p style={{ fontSize: 14, fontWeight: 600, color: 'var(--gold)' }}>View Tutorial</p>
              </div>
              <span style={{ color: 'var(--text3)', fontSize: 16 }}>›</span>
            </button>
          </>
        )}

        {/* ── Appearance page ─────────────────────────────────────────────── */}
        {page === 'appearance' && (
          <div style={{ padding: '20px' }}>
            <p style={{ fontSize: 11, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.12em', marginBottom: 12 }}>COLOR MODE</p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {([
                { key: 'dark', label: 'Dark', desc: 'Black & gold' },
                { key: 'day', label: 'Day', desc: 'Warm tan' },
                { key: 'system', label: 'System', desc: 'Follows your device' },
              ] as const).map(m => (
                <button
                  key={m.key}
                  onClick={() => { setColorMode(m.key); applyColorMode(m.key); }}
                  style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                    padding: '14px 16px', borderRadius: 10, cursor: 'pointer',
                    background: colorMode === m.key ? 'var(--gold-dim)' : 'var(--bg2)',
                    border: `1px solid ${colorMode === m.key ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                  }}
                >
                  <div style={{ textAlign: 'left' }}>
                    <p style={{ fontSize: 14, fontWeight: 600, color: colorMode === m.key ? 'var(--gold)' : 'var(--text)' }}>{m.label}</p>
                    <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>{m.desc}</p>
                  </div>
                  {colorMode === m.key && <span style={{ color: 'var(--gold)', fontSize: 18 }}>✓</span>}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* ── Rules page ──────────────────────────────────────────────────── */}
        {page === 'rules' && (
          <div style={{ padding: '20px' }}>
            <p style={{ fontSize: 11, color: 'var(--text3)', lineHeight: 1.6, marginBottom: 16 }}>
              These rules guide how dumps are built and scored.
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 16 }}>
              {customRules.map((rule, i) => (
                <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                  <input
                    value={rule}
                    onChange={e => updateRule(i, e.target.value)}
                    placeholder={`Rule ${i + 1}`}
                    style={{
                      flex: 1, background: 'var(--bg2)', border: '1px solid var(--border2)',
                      borderRadius: 8, padding: '10px 12px', color: 'var(--text)',
                      fontSize: 13, fontFamily: 'var(--font)', outline: 'none',
                    }}
                    onFocus={e => (e.currentTarget.style.borderColor = 'var(--gold)')}
                    onBlur={e => (e.currentTarget.style.borderColor = 'var(--border2)')}
                  />
                  <button
                    onClick={() => removeRule(i)}
                    style={{
                      background: 'var(--bg2)', border: '1px solid var(--border2)',
                      borderRadius: 8, width: 36, height: 40, cursor: 'pointer',
                      color: 'var(--text3)', fontSize: 18, flexShrink: 0,
                    }}
                  >×</button>
                </div>
              ))}
            </div>
            <button
              onClick={() => addRule('')}
              style={{
                width: '100%', padding: '12px 0', borderRadius: 8, fontSize: 13, fontWeight: 600,
                background: 'var(--bg2)', border: '1px solid var(--border2)',
                color: 'var(--gold)', cursor: 'pointer',
              }}
            >+ Add Rule</button>
          </div>
        )}

        {/* ── Handle page ─────────────────────────────────────────────────── */}
        {page === 'handle' && (
          <div style={{ padding: '20px' }}>
            <p style={{ fontSize: 11, color: 'var(--text3)', lineHeight: 1.6, marginBottom: 16 }}>
              Your Instagram handle. Used for captions and sharing.
            </p>
            <div style={{
              display: 'flex', alignItems: 'center',
              background: 'var(--bg2)', border: '1px solid var(--border2)',
              borderRadius: 10, padding: '0 12px', marginBottom: 12,
            }}>
              <span style={{ color: 'var(--text3)', fontSize: 16, marginRight: 4 }}>@</span>
              <input
                value={handle}
                onChange={e => saveHandle(e.target.value.replace(/^@/, ''))}
                placeholder="geniusscott2"
                autoCapitalize="none"
                autoCorrect="off"
                style={{
                  flex: 1, background: 'transparent', border: 'none', outline: 'none',
                  color: 'var(--text)', fontSize: 16, padding: '14px 0',
                  fontFamily: 'var(--font)',
                }}
              />
            </div>
            {handle && (
              <p style={{ fontSize: 12, color: 'var(--gold)' }}>✓ Handle saved: @{handle}</p>
            )}
          </div>
        )}

        {/* ── Style Profile page ──────────────────────────────────────────── */}
        {page === 'style' && (
          <div style={{ padding: '20px' }}>
            <p style={{ fontSize: 11, color: 'var(--text3)', lineHeight: 1.6, marginBottom: 16 }}>
              Describe your aesthetic. The AI uses this when generating dump titles and captions.
            </p>
            <textarea
              value={styleProfile}
              onChange={e => saveStyle(e.target.value)}
              placeholder="I shoot quiet luxury, street culture, nightlife, cars, and fashion. My aesthetic is dark, cinematic, and minimal — high-end but not sterile. Think W Magazine meets car culture meets late-night Miami. Captions should feel editorial and intentional, never basic or influencer-coded."
              rows={8}
              style={{
                width: '100%', padding: '12px', borderRadius: 10, boxSizing: 'border-box',
                background: 'var(--bg2)', border: '1px solid var(--border2)',
                color: 'var(--text)', fontSize: 13, lineHeight: 1.6,
                fontFamily: 'var(--font)', resize: 'vertical', outline: 'none',
              }}
              onFocus={e => (e.currentTarget.style.borderColor = 'var(--gold)')}
              onBlur={e => (e.currentTarget.style.borderColor = 'var(--border2)')}
            />
            {styleProfile.trim() && (
              <p style={{ fontSize: 11, color: 'var(--gold)', marginTop: 8 }}>✓ AI trained on your style</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

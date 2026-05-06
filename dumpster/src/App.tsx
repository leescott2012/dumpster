import { useState, useEffect, useRef, useCallback } from 'react';
import './index.css';
import { useStore, applyColorMode, loadPhotosFromServer } from './store';
import DumpCard from './components/DumpCard';
import PhotoPool from './components/PhotoPool';
import Lightbox from './components/Lightbox';
import { InstallPrompt } from './components/InstallPrompt';
import { Onboarding } from './components/Onboarding';

// Accent colour presets
const ACCENT_PRESETS = [
  { label: 'Gold',    value: '#C8A96E' },
  { label: 'Coral',   value: '#E0715C' },
  { label: 'Sky',     value: '#5BA4CF' },
  { label: 'Mint',    value: '#5CC8A9' },
  { label: 'Lavender',value: '#9B8BD4' },
  { label: 'Rose',    value: '#D4698B' },
];

function setAccentColor(hex: string) {
  document.documentElement.style.setProperty('--accent', hex);
  // Rebuild rgba dims from the hex
  const r = parseInt(hex.slice(1,3),16);
  const g = parseInt(hex.slice(3,5),16);
  const b = parseInt(hex.slice(5,7),16);
  document.documentElement.style.setProperty('--accent-dim',  `rgba(${r},${g},${b},0.15)`);
  document.documentElement.style.setProperty('--accent-dim2', `rgba(${r},${g},${b},0.08)`);
  localStorage.setItem('dumpster_accent', hex);
}

function loadSavedAccent() {
  const saved = localStorage.getItem('dumpster_accent');
  if (saved) setAccentColor(saved);
}

export default function App() {
  const {
    dumps, photos, activeDumpId, colorMode,
    newDump, setActiveDump, undo, redo, canUndo, canRedo,
    setColorMode,
  } = useStore();

  const [mainMenuOpen, setMainMenuOpen] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [accentHex, setAccentHex] = useState(() => localStorage.getItem('dumpster_accent') ?? '#C8A96E');
  const mainMenuRef = useRef<HTMLDivElement>(null);
  const usedIds = new Set(dumps.flatMap((d) => d.photos));
  const usedCount = usedIds.size;
  const poolCount = photos.filter((p) => !usedIds.has(p.id)).length;

  const applyAccent = useCallback((hex: string) => {
    setAccentHex(hex);
    setAccentColor(hex);
  }, []);

  // Apply color mode on load
  useEffect(() => {
    loadSavedAccent();
    applyColorMode(colorMode);
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => { if (colorMode === 'system') applyColorMode('system'); };
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, [colorMode]);

  // Load server photos if pool is empty
  useEffect(() => {
    if (photos.length === 0) loadPhotosFromServer();
  }, []);

  // Show onboarding on first visit
  useEffect(() => {
    const completed = localStorage.getItem('onboardingCompleted');
    if (!completed && dumps.length === 0) {
      setShowOnboarding(true);
    }
  }, [dumps.length]);

  // Close main menu on outside click
  useEffect(() => {
    if (!mainMenuOpen) return;
    const handler = (e: MouseEvent) => {
      if (mainMenuRef.current && !mainMenuRef.current.contains(e.target as Node))
        setMainMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [mainMenuOpen]);

  // Keyboard undo/redo
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
        e.preventDefault();
        if (e.shiftKey) redo(); else undo();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [undo, redo]);

  return (
    <div style={{ background: 'var(--bg)', minHeight: '100vh' }}>
      <Lightbox />
      <InstallPrompt />
      {showOnboarding && <Onboarding onComplete={() => setShowOnboarding(false)} />}
      <div style={{ maxWidth: 1100, margin: '0 auto', padding: '0 32px' }}>

        {/* ── Header ──────────────────────────────────────── */}
        <header style={{ paddingTop: 48, paddingBottom: 32 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>

            {/* Brand wordmark */}
            <div>
              <p style={{
                fontSize: 10, letterSpacing: '0.22em', color: 'var(--accent)',
                textTransform: 'uppercase', fontWeight: 800, marginBottom: 0,
              }}>DUMPSTER</p>
            </div>

            {/* Top-right controls */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {/* Undo / Redo */}
              {(canUndo() || canRedo()) && <>
                <button onClick={undo} disabled={!canUndo()} title="Undo (⌘Z)" style={undoRedoStyle(!canUndo())}>←</button>
                <button onClick={redo} disabled={!canRedo()} title="Redo (⌘⇧Z)" style={undoRedoStyle(!canRedo())}>→</button>
              </>}

              {/* Main hamburger */}
              <div ref={mainMenuRef} style={{ position: 'relative' }}>
                <button
                  onClick={() => setMainMenuOpen(o => !o)}
                  style={{
                    width: 36, height: 36, borderRadius: 20,
                    background: mainMenuOpen ? 'var(--accent-dim)' : 'var(--bg2)',
                    border: `1px solid ${mainMenuOpen ? 'var(--accent)' : 'var(--border2)'}`,
                    cursor: 'pointer', display: 'flex', flexDirection: 'column',
                    alignItems: 'center', justifyContent: 'center', gap: 4,
                    transition: 'all 0.15s',
                  }}
                >
                  {[0, 1, 2].map(i => (
                    <div key={i} style={{ width: 14, height: 1.5, background: mainMenuOpen ? 'var(--accent)' : 'var(--text3)', borderRadius: 1, transition: 'background 0.15s' }} />
                  ))}
                </button>

                {mainMenuOpen && (
                  <div style={{
                    position: 'absolute', top: 44, right: 0, zIndex: 200,
                    background: '#1a1a1a', border: '1px solid var(--border2)',
                    borderRadius: 14, padding: 16, minWidth: 240,
                    boxShadow: '0 16px 48px rgba(0,0,0,0.7)',
                    animation: 'slideDown 0.18s ease',
                  }}>
                    {/* Accent colour */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.14em', marginBottom: 10 }}>ACCENT COLOR</p>
                    <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
                      {ACCENT_PRESETS.map(({ label, value }) => (
                        <button
                          key={value}
                          title={label}
                          onClick={() => applyAccent(value)}
                          style={{
                            width: 26, height: 26, borderRadius: '50%', border: 'none',
                            background: value, cursor: 'pointer', flexShrink: 0,
                            outline: accentHex === value ? `2px solid ${value}` : 'none',
                            outlineOffset: 2,
                            boxShadow: accentHex === value ? `0 0 0 1px #1a1a1a, 0 0 0 3px ${value}` : 'none',
                            transition: 'box-shadow 0.15s',
                          }}
                        />
                      ))}
                    </div>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Color mode */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.14em', marginBottom: 10 }}>COLOR MODE</p>
                    <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
                      {(['dark', 'day', 'system'] as const).map(m => (
                        <button key={m} onClick={() => { setColorMode(m); }} style={{
                          flex: 1, padding: '7px 0', borderRadius: 20, fontSize: 10, fontWeight: 600,
                          background: colorMode === m ? 'var(--accent-dim)' : 'var(--bg3)',
                          border: `1px solid ${colorMode === m ? 'var(--accent)' : 'var(--border2)'}`,
                          color: colorMode === m ? 'var(--accent)' : 'var(--text3)', cursor: 'pointer',
                          textTransform: 'capitalize', transition: 'all 0.15s',
                        }}>{m}</button>
                      ))}
                    </div>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Stats */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.14em', marginBottom: 8 }}>POOL STATS</p>
                    <p style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 4 }}>
                      {poolCount} available · {usedCount} in dumps
                    </p>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Formula info */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.14em', marginBottom: 8 }}>THE FORMULA</p>
                    <p style={{ fontSize: 10, color: 'var(--text3)', lineHeight: 1.7 }}>
                      Peak: 10–12 slides ★<br />
                      Hook → Contrast → Detail → Fashion<br />
                      Never same category back-to-back
                    </p>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Tutorial button */}
                    <button
                      onClick={() => { setShowOnboarding(true); setMainMenuOpen(false); }}
                      style={{
                        width: '100%', padding: '10px 12px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                        background: 'var(--accent-dim)', border: '1px solid var(--accent)',
                        color: 'var(--accent)', cursor: 'pointer', marginTop: 8, transition: 'all 0.15s',
                        fontFamily: 'var(--font)',
                      }}
                      onMouseEnter={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'var(--accent)';
                        (e.currentTarget as HTMLButtonElement).style.color = '#000';
                      }}
                      onMouseLeave={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'var(--accent-dim)';
                        (e.currentTarget as HTMLButtonElement).style.color = 'var(--accent)';
                      }}
                    >View Tutorial</button>
                  </div>
                )}
              </div>
            </div>
          </div>

          <h1 style={{
            fontSize: 50, fontWeight: 800, color: 'var(--text)', lineHeight: 1.05,
            marginBottom: 12, letterSpacing: '-0.02em', marginTop: 16,
          }}>
            Build Your{' '}
            <span style={{ color: 'var(--accent)' }}>Dumps</span>
          </h1>
          <p style={{ fontSize: 14, color: 'var(--text3)', lineHeight: 1.6, marginBottom: 24, maxWidth: 540 }}>
            Drag to reorder · double-click to enlarge · tap + to add from pool
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <StatPill num={dumps.length} label="Dumps" />
            <StatPill num={usedCount} label="Photos Used" />
            <StatPill num={poolCount} label="In Pool" />
          </div>
        </header>

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 48 }} />

        {/* ── Dump Cards ───────────────────────────────────── */}
        {dumps.map((dump) => (
          <DumpCard
            key={dump.id}
            dump={dump}
            active={dump.id === activeDumpId}
            onActivate={() => setActiveDump(dump.id)}
          />
        ))}

        {/* ── New Dump ─────────────────────────────────────── */}
        <div style={{ display: 'flex', gap: 10, marginBottom: 72, marginTop: 8 }}>
          <button
            onClick={newDump}
            style={{
              display: 'flex', alignItems: 'center', gap: 7,
              background: 'transparent',
              border: '1.5px solid var(--accent)',
              borderRadius: 999, padding: '10px 22px',
              color: 'var(--accent)',
              fontSize: 11, fontWeight: 800, letterSpacing: '0.12em',
              textTransform: 'uppercase', cursor: 'pointer',
              transition: 'all 0.18s', fontFamily: 'var(--font)',
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.background = 'var(--accent)';
              (e.currentTarget as HTMLButtonElement).style.color = '#000';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
              (e.currentTarget as HTMLButtonElement).style.color = 'var(--accent)';
            }}
          >
            <span style={{ fontSize: 15, lineHeight: 1 }}>+</span>
            New Dump
          </button>
        </div>

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 48 }} />

        {/* ── Photo Pool ───────────────────────────────────── */}
        <PhotoPool />

        <div style={{ height: 80 }} />
      </div>
    </div>
  );
}

// ─── helpers ─────────────────────────────────────────────────────────────────

function undoRedoStyle(disabled: boolean): React.CSSProperties {
  return {
    width: 32, height: 32, borderRadius: 6, fontSize: 14, fontWeight: 700,
    background: 'var(--bg2)', border: '1px solid var(--border2)',
    color: disabled ? 'var(--border3)' : 'var(--text2)',
    cursor: disabled ? 'default' : 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    transition: 'all 0.15s',
    opacity: disabled ? 0.4 : 1,
  };
}

function StatPill({ num, label }: { num: number; label: string }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 6,
      background: 'var(--bg2)', border: '1px solid var(--border2)',
      borderRadius: 999, padding: '6px 14px',
    }}>
      <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)' }}>{num}</span>
      <span style={{ fontSize: 12, color: 'var(--text3)' }}>{label}</span>
    </div>
  );
}

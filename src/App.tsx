import { useState, useEffect, useRef } from 'react';
import './index.css';
import { useStore, applyColorMode, loadPhotosFromServer } from './store';
import DumpCard from './components/DumpCard';
import PhotoPool from './components/PhotoPool';
import CaptionPool from './components/CaptionPool';
import Lightbox from './components/Lightbox';
import { InstallPrompt } from './components/InstallPrompt';
import { Onboarding } from './components/Onboarding';

export default function App() {
  const {
    dumps, photos, activeDumpId, colorMode,
    newDump, setActiveDump, undo, redo, canUndo, canRedo,
    setColorMode,
  } = useStore();

  const [mainMenuOpen, setMainMenuOpen] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [activePool, setActivePool] = useState<'photos' | 'captions'>('photos');
  const mainMenuRef = useRef<HTMLDivElement>(null);
  const usedIds = new Set(dumps.flatMap((d) => d.photos));
  const usedCount = usedIds.size;
  const poolCount = photos.filter((p) => !usedIds.has(p.id)).length;

  // Apply color mode on load
  useEffect(() => {
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
        <header style={{ paddingTop: 52, paddingBottom: 36 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <p style={{
              fontSize: 11, letterSpacing: '0.18em', color: 'var(--text3)',
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 14,
            }}>DUMPSTER</p>

            {/* Top-right controls */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {/* Undo / Redo */}
              <button
                onClick={undo} disabled={!canUndo()}
                title="Undo (⌘Z)"
                style={undoRedoStyle(!canUndo())}
              >←</button>
              <button
                onClick={redo} disabled={!canRedo()}
                title="Redo (⌘⇧Z)"
                style={undoRedoStyle(!canRedo())}
              >→</button>

              {/* Main hamburger */}
              <div ref={mainMenuRef} style={{ position: 'relative' }}>
                <button
                  onClick={() => setMainMenuOpen(o => !o)}
                  style={{
                    width: 36, height: 36, borderRadius: 8,
                    background: mainMenuOpen ? 'var(--gold-dim)' : 'var(--bg2)',
                    border: `1px solid ${mainMenuOpen ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                    cursor: 'pointer', display: 'flex', flexDirection: 'column',
                    alignItems: 'center', justifyContent: 'center', gap: 4,
                    transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                    transform: mainMenuOpen ? 'rotate(90deg)' : 'rotate(0deg)',
                  }}
                >
                  {[0, 1, 2].map(i => (
                    <div key={i} style={{
                      width: 14, height: 1.5, borderRadius: 1,
                      background: mainMenuOpen ? 'var(--gold)' : 'var(--text3)',
                      transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                    }} />
                  ))}
                </button>

                {mainMenuOpen && (
                  <div className="menu-dropdown" style={{
                    position: 'absolute', top: 42, right: 0, zIndex: 200,
                    background: 'var(--menu-bg)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
                    border: '1px solid var(--border2)',
                    borderRadius: 12, padding: 16, minWidth: 220,
                    boxShadow: '0 12px 40px rgba(0,0,0,0.3)',
                  }}>
                    {/* Color mode */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.12em', marginBottom: 10 }}>COLOR MODE</p>
                    <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
                      {(['dark', 'day', 'system'] as const).map(m => (
                        <button key={m} onClick={() => { setColorMode(m); setMainMenuOpen(false); }} style={{
                          flex: 1, padding: '7px 0', borderRadius: 6, fontSize: 10, fontWeight: 600,
                          background: colorMode === m ? 'var(--gold-dim)' : 'var(--bg3)',
                          border: `1px solid ${colorMode === m ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                          color: colorMode === m ? 'var(--gold)' : 'var(--text3)', cursor: 'pointer',
                          textTransform: 'capitalize',
                        }}>{m}</button>
                      ))}
                    </div>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Used photos */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.12em', marginBottom: 8 }}>USED PHOTOS</p>
                    <p style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 16 }}>
                      {usedCount} photos currently in dumps
                    </p>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Formula info */}
                    <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.12em', marginBottom: 8 }}>THE FORMULA</p>
                    <p style={{ fontSize: 10, color: 'var(--text3)', lineHeight: 1.6 }}>
                      Peak: 10–12 slides ★<br />
                      Hook → Contrast → Detail → Fashion<br />
                      Never same category back-to-back
                    </p>

                    <div style={{ borderTop: '1px solid var(--border2)', margin: '8px 0' }} />

                    {/* Tutorial button */}
                    <button
                      onClick={() => { setShowOnboarding(true); setMainMenuOpen(false); }}
                      style={{
                        width: '100%', padding: '10px 12px', borderRadius: 6, fontSize: 12, fontWeight: 600,
                        background: 'var(--gold-dim)', border: '1px solid rgba(200,169,110,0.4)',
                        color: 'var(--gold)', cursor: 'pointer', marginTop: 8
                      }}
                      onMouseEnter={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'var(--gold)';
                        (e.currentTarget as HTMLButtonElement).style.color = '#000';
                      }}
                      onMouseLeave={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'var(--gold-dim)';
                        (e.currentTarget as HTMLButtonElement).style.color = 'var(--gold)';
                      }}
                    >
                      👁️ View Tutorial
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>

          <h1 style={{
            fontSize: 52, fontWeight: 800, color: 'var(--text)', lineHeight: 1.05,
            marginBottom: 14, letterSpacing: '-0.02em',
          }}>
            Build Your{' '}
            <span style={{ color: 'var(--gold)' }}>Dumps</span>
          </h1>
          <p style={{ fontSize: 14, color: 'var(--text3)', lineHeight: 1.6, marginBottom: 28, maxWidth: 560 }}>
            Double-tap a photo to enlarge. Drag to reorder. Tap + to add from the pool.
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <StatPill num={dumps.length} label="Dumps" />
            <StatPill num={usedCount} label="Photos Used" />
            <StatPill num={poolCount} label="In Pool" />
          </div>
        </header>

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 48 }} />

        {/* ── Dump Cards ───────────────────────────────────── */}
        <div style={{ overflow: 'hidden', position: 'relative', zIndex: 1 }}>
          {dumps.map((dump) => (
            <DumpCard
              key={dump.id}
              dump={dump}
              active={dump.id === activeDumpId}
              onActivate={() => setActiveDump(dump.id)}
            />
          ))}
        </div>

        {/* ── Actions ──────────────────────────────────────── */}
        <div style={{ display: 'flex', gap: 10, marginBottom: 72, marginTop: 8 }}>
          <ActionButton icon="+" label="New Dump" onClick={newDump} />
        </div>

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 48 }} />

        {/* ── Pool Toggle ──────────────────────────────────── */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 32 }}>
          <div style={{
            display: 'flex', width: 260, height: 40,
            borderRadius: 20, background: 'var(--bg2)',
            border: '1px solid var(--border2)', position: 'relative',
            overflow: 'hidden', cursor: 'pointer',
          }}>
            {/* Sliding pill */}
            <div style={{
              position: 'absolute', top: 3, bottom: 3,
              width: '50%', borderRadius: 17,
              background: 'var(--gold-dim)', border: '1px solid rgba(200,169,110,0.3)',
              transition: 'transform 0.35s cubic-bezier(0.16, 1, 0.3, 1)',
              transform: activePool === 'photos' ? 'translateX(3px)' : 'translateX(calc(100% - 3px))',
            }} />
            <button
              onClick={() => setActivePool('photos')}
              style={{
                flex: 1, zIndex: 1, background: 'transparent', border: 'none',
                fontSize: 11, fontWeight: 700, letterSpacing: '0.08em',
                color: activePool === 'photos' ? 'var(--gold)' : 'var(--text3)',
                cursor: 'pointer', transition: 'color 0.2s',
                textTransform: 'uppercase', fontFamily: 'var(--font)',
              }}
            >Photos</button>
            <button
              onClick={() => setActivePool('captions')}
              style={{
                flex: 1, zIndex: 1, background: 'transparent', border: 'none',
                fontSize: 11, fontWeight: 700, letterSpacing: '0.08em',
                color: activePool === 'captions' ? 'var(--gold)' : 'var(--text3)',
                cursor: 'pointer', transition: 'color 0.2s',
                textTransform: 'uppercase', fontFamily: 'var(--font)',
              }}
            >Captions</button>
          </div>
        </div>

        {/* ── Photo Pool / Caption Pool ──────────────────── */}
        <div className="pool-section" key={activePool} style={{ position: 'relative', zIndex: 2 }}>
          {activePool === 'photos' ? <PhotoPool /> : <CaptionPool />}
        </div>

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
    transition: 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
    opacity: disabled ? 0.4 : 1,
    transform: 'scale(1)',
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

function ActionButton({ icon, label, onClick, gold }: { icon: string; label: string; onClick: () => void; gold?: boolean }) {
  return (
    <button
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 6,
        background: gold ? 'var(--gold-dim)' : 'var(--bg2)',
        border: `1px solid ${gold ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
        borderRadius: 8, padding: '10px 18px',
        color: gold ? 'var(--gold)' : 'var(--text2)',
        fontSize: 13, fontWeight: 500, transition: 'all 0.15s',
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--gold)';
        (e.currentTarget as HTMLButtonElement).style.color = 'var(--gold)';
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLButtonElement).style.borderColor = gold ? 'rgba(200,169,110,0.4)' : 'var(--border2)';
        (e.currentTarget as HTMLButtonElement).style.color = gold ? 'var(--gold)' : 'var(--text2)';
      }}
    >
      <span style={{ fontSize: 15 }}>{icon}</span>
      {label}
    </button>
  );
}

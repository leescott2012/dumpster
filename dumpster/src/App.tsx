import { useState, useEffect, useRef, useCallback } from 'react';
import './index.css';
import { useStore, applyColorMode, loadPhotosFromServer } from './store';
import DumpCard from './components/DumpCard';
import PhotoPool from './components/PhotoPool';
import CaptionsView from './components/CaptionsView';
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
  const [mainTab, setMainTab] = useState<'photos' | 'captions'>('photos');
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

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 32 }} />

        {/* ── Photos / Captions segmented pill ─────────────── */}
        <div style={{
          display: 'flex', justifyContent: 'center', marginBottom: 40,
        }}>
          <div style={{
            display: 'flex', padding: 4, gap: 0,
            background: 'var(--bg2)', border: '1px solid var(--border2)',
            borderRadius: 999,
          }}>
            {(['photos', 'captions'] as const).map(tab => (
              <button
                key={tab}
                onClick={() => setMainTab(tab)}
                style={{
                  padding: '8px 24px', borderRadius: 999, border: 'none',
                  fontSize: 11, fontWeight: 800, letterSpacing: '0.1em',
                  textTransform: 'uppercase', cursor: 'pointer',
                  background: mainTab === tab ? 'var(--accent)' : 'transparent',
                  color: mainTab === tab ? '#000' : 'var(--text3)',
                  transition: 'all 0.2s', fontFamily: 'var(--font)',
                }}
              >{tab}</button>
            ))}
          </div>
        </div>

        {/* ── PHOTOS TAB ───────────────────────────────────── */}
        {mainTab === 'photos' && (
          <>
            {dumps.map((dump) => (
              <DumpCard
                key={dump.id}
                dump={dump}
                active={dump.id === activeDumpId}
                onActivate={() => setActiveDump(dump.id)}
              />
            ))}

            {/* New Dump */}
            <div style={{ display: 'flex', gap: 10, marginBottom: 72, marginTop: 8 }}>
              <button
                onClick={newDump}
                style={{
                  display: 'flex', alignItems: 'center', gap: 7,
                  background: 'transparent', border: '1.5px solid var(--accent)',
                  borderRadius: 999, padding: '10px 22px',
                  color: 'var(--accent)', fontSize: 11, fontWeight: 800,
                  letterSpacing: '0.12em', textTransform: 'uppercase',
                  cursor: 'pointer', transition: 'all 0.18s', fontFamily: 'var(--font)',
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
            <PhotoPool />
          </>
        )}

        {/* ── CAPTIONS TAB ─────────────────────────────────── */}
        {mainTab === 'captions' && <CaptionsView />}

        {/* ── Footer ───────────────────────────────────────── */}
        <AppFooter />

        <div style={{ height: 48 }} />
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

// ─── Footer ───────────────────────────────────────────────────────────────────

function AppFooter() {
  const [showPrivacy, setShowPrivacy] = useState(false);
  const [showTerms, setShowTerms] = useState(false);

  return (
    <>
      {/* Privacy modal */}
      {showPrivacy && <LegalModal title="Privacy Policy" onClose={() => setShowPrivacy(false)}>
        <p>DUMPSTER ("we", "us") is committed to protecting your privacy.</p>
        <h3>Information We Collect</h3>
        <p>Photos and content you add are stored locally in your browser (localStorage). We do not upload your photos to any server. No personal data is collected, sold, or shared with third parties.</p>
        <h3>Local Storage</h3>
        <p>We use localStorage to save your dumps, captions, and preferences between sessions. You can clear this at any time via your browser settings.</p>
        <h3>Analytics</h3>
        <p>We may use anonymised analytics to understand how the app is used. No personally identifiable information is collected.</p>
        <h3>Contact</h3>
        <p>Questions? Email us at support@dumpster.app</p>
        <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 16 }}>Last updated: May 2026</p>
      </LegalModal>}

      {/* Terms modal */}
      {showTerms && <LegalModal title="Terms of Service" onClose={() => setShowTerms(false)}>
        <p>By using DUMPSTER you agree to the following terms.</p>
        <h3>Use of Service</h3>
        <p>DUMPSTER is provided for personal use to organise and sequence photos for social media carousels. You retain full ownership of any content you add.</p>
        <h3>Prohibited Use</h3>
        <p>You may not use DUMPSTER to store, distribute, or display illegal, harmful, or infringing content.</p>
        <h3>Disclaimer</h3>
        <p>DUMPSTER is provided "as is" without warranty of any kind. We are not liable for any loss of data or content.</p>
        <h3>Changes</h3>
        <p>We may update these terms at any time. Continued use after changes constitutes acceptance.</p>
        <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 16 }}>Last updated: May 2026</p>
      </LegalModal>}

      {/* App Store landing strip */}
      <div style={{
        borderTop: '1px solid var(--border2)', marginTop: 64, marginBottom: 0,
        padding: '56px 0', display: 'flex', flexDirection: 'column', alignItems: 'center',
        gap: 20, textAlign: 'center',
      }}>
        {/* Icon */}
        <div style={{
          width: 72, height: 72, borderRadius: 18,
          background: 'linear-gradient(135deg, #1a1a1a 0%, #0a0a0a 100%)',
          border: '1px solid var(--border2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
        }}>
          <span style={{ fontSize: 32, lineHeight: 1 }}>🗑️</span>
        </div>
        <div>
          <p style={{
            fontSize: 10, fontWeight: 800, letterSpacing: '0.2em',
            color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 8,
          }}>NATIVE IOS APP</p>
          <p style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.01em', marginBottom: 6 }}>
            Get DUMPSTER on iPhone
          </p>
          <p style={{ fontSize: 13, color: 'var(--text3)', maxWidth: 380, margin: '0 auto' }}>
            Full AI caption generation, StoreKit subscriptions, offline-first, and native photo picker — coming to the App Store.
          </p>
        </div>

        {/* App Store badge */}
        <a
          href="https://apps.apple.com"
          target="_blank"
          rel="noopener noreferrer"
          style={{ display: 'inline-block' }}
        >
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10,
            background: '#000', borderRadius: 12, padding: '11px 22px',
            border: '1px solid #333',
          }}>
            <svg width="22" height="22" viewBox="0 0 814 1000" fill="white">
              <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-38.8-155.5-127.4C46 790.7 0 663 0 541.8c0-207.5 135.4-317.3 268.5-317.3 99.8 0 165 52.5 221 52.5 53.7 0 128.1-55.5 239.7-55.5zM572.3 116.7c49.2-58.5 84.8-140.1 84.8-221.6 0-11.3-.9-22.6-2.7-33.9-80.2 3.1-176.5 53.5-233.8 123.3-43.5 50.8-85.5 132.9-85.5 215.3 0 12.6 2.2 25.2 3.1 29.5 5 .9 13.2 2.2 21.4 2.2 71.7 0 159.3-48.1 212.7-114.8z"/>
            </svg>
            <div style={{ textAlign: 'left' }}>
              <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.6)', lineHeight: 1, marginBottom: 2 }}>Download on the</p>
              <p style={{ fontSize: 16, fontWeight: 700, color: '#fff', lineHeight: 1 }}>App Store</p>
            </div>
          </div>
        </a>

        {/* Legal links */}
        <div style={{ display: 'flex', gap: 20, marginTop: 8 }}>
          <button
            onClick={() => setShowPrivacy(true)}
            style={{
              background: 'none', border: 'none', cursor: 'pointer',
              fontSize: 12, color: 'var(--text3)', fontFamily: 'var(--font)',
              transition: 'color 0.15s',
            }}
            onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--accent)')}
            onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--text3)')}
          >Privacy Policy</button>
          <button
            onClick={() => setShowTerms(true)}
            style={{
              background: 'none', border: 'none', cursor: 'pointer',
              fontSize: 12, color: 'var(--text3)', fontFamily: 'var(--font)',
              transition: 'color 0.15s',
            }}
            onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--accent)')}
            onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--text3)')}
          >Terms of Service</button>
        </div>
        <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 0 }}>
          © {new Date().getFullYear()} DUMPSTER. All rights reserved.
        </p>
      </div>
    </>
  );
}

// ─── Legal modal ──────────────────────────────────────────────────────────────

function LegalModal({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 1000,
        background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(8px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 24, animation: 'fadeIn 0.18s ease',
      }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: '#1a1a1a', border: '1px solid var(--border2)',
          borderRadius: 20, padding: 32, maxWidth: 560, width: '100%',
          maxHeight: '80vh', overflowY: 'auto',
          boxShadow: '0 24px 80px rgba(0,0,0,0.8)',
          animation: 'slideDown 0.2s ease',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: 'var(--text)' }}>{title}</h2>
          <button
            onClick={onClose}
            style={{
              width: 32, height: 32, borderRadius: '50%', border: 'none',
              background: 'var(--bg3)', color: 'var(--text3)', cursor: 'pointer', fontSize: 16,
            }}
          >✕</button>
        </div>
        <div style={{
          fontSize: 13, color: 'var(--text2)', lineHeight: 1.8,
          display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          {children}
        </div>
      </div>
    </div>
  );
}

// ─── StatPill ─────────────────────────────────────────────────────────────────

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

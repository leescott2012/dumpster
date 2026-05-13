import { useState, useEffect, useRef, useCallback } from 'react';
import './index.css';
import { useStore, applyColorMode, loadPhotosFromServer } from './store';
import type { Dump, Photo, ColorMode } from './types';
import { SLOT_LABELS, TEMPLATE_12, TEMPLATE_7 } from './formula';
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
    dumps, photos, captions, activeDumpId, colorMode,
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
      <div style={{ maxWidth: 1040, margin: '0 auto', padding: '0 28px' }}>

        {/* ── Header ──────────────────────────────────────── */}
        <header style={{ paddingTop: 48, paddingBottom: 32 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>

            {/* Brand wordmark */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <div style={{
                width: 28, height: 28, borderRadius: 7,
                background: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <span style={{ fontSize: 14, lineHeight: 1, fontWeight: 900, color: '#000', fontFamily: 'var(--font)' }}>D</span>
              </div>
              <p style={{
                fontSize: 11, letterSpacing: '0.2em', color: 'var(--text)',
                textTransform: 'uppercase', fontWeight: 800,
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
              <button
                onClick={() => setMainMenuOpen(o => !o)}
                style={{
                  width: 36, height: 36, borderRadius: 20,
                  background: mainMenuOpen ? 'var(--accent-dim)' : 'var(--bg2)',
                  border: `1px solid ${mainMenuOpen ? 'var(--accent)' : 'var(--border2)'}`,
                  cursor: 'pointer', display: 'flex', flexDirection: 'column',
                  alignItems: 'center', justifyContent: 'center', gap: 4, transition: 'all 0.15s',
                }}
              >
                {[0,1,2].map(i => (
                  <div key={i} style={{ width: 14, height: 1.5, background: mainMenuOpen ? 'var(--accent)' : 'var(--text3)', borderRadius: 1, transition: 'background 0.15s' }} />
                ))}
              </button>

              {/* Full-screen settings panel */}
              {mainMenuOpen && (
                <SettingsPanel
                  dumps={dumps}
                  photos={photos}
                  poolCount={poolCount}
                  usedCount={usedCount}
                  colorMode={colorMode}
                  accentHex={accentHex}
                  applyAccent={applyAccent}
                  setColorMode={setColorMode}
                  onShowOnboarding={() => { setShowOnboarding(true); setMainMenuOpen(false); }}
                  onClose={() => setMainMenuOpen(false)}
                  onNewDump={() => { newDump(); setMainMenuOpen(false); }}
                  onScrollToDump={(id) => { setActiveDump(id); setMainMenuOpen(false); setMainTab('photos'); }}
                  onResetAll={() => { useStore.getState().resetAll(); setMainMenuOpen(false); }}
                />
              )}
            </div>
          </div>

          <h1 style={{
            fontSize: 54, fontWeight: 400, color: 'var(--text)', lineHeight: 1.05,
            marginBottom: 14, letterSpacing: '-0.01em', marginTop: 18,
            fontFamily: 'var(--font-display)',
          }}>
            Build Your{' '}
            <span style={{ color: 'var(--accent)', fontStyle: 'italic' }}>Dumps</span>
          </h1>
          <p style={{ fontSize: 14, color: 'var(--text3)', lineHeight: 1.65, marginBottom: 24, maxWidth: 480 }}>
            Drag to reorder · double-click to enlarge · tap + to add from pool
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <StatPill num={dumps.length} label="Dumps" />
            <StatPill num={usedCount} label="Photos Used" />
            <StatPill num={poolCount} label="In Pool" />
          </div>
        </header>

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 32 }} />

        {/* ── Dumps always visible ─────────────────────────── */}
        {[...dumps].sort((a, b) => a.num - b.num).map((dump) => (
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

        <div style={{ borderTop: '1px solid var(--border2)', marginBottom: 40 }} />

        {/* ── Photos / Captions pill — above the pool ──────── */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 40 }}>
          <div style={{
            display: 'flex', padding: 4,
            background: 'var(--bg2)', border: '1px solid var(--border2)',
            borderRadius: 999, boxShadow: '0 2px 12px rgba(0,0,0,0.3)',
          }}>
            {([
              { key: 'photos',   label: 'Photos',   badge: null },
              { key: 'captions', label: 'Captions', badge: captions.length > 0 ? captions.length : null },
            ] as const).map(({ key, label, badge }) => (
              <button
                key={key}
                onClick={() => setMainTab(key)}
                style={{
                  padding: '9px 26px', borderRadius: 999, border: 'none',
                  fontSize: 11, fontWeight: 800, letterSpacing: '0.12em',
                  textTransform: 'uppercase', cursor: 'pointer',
                  background: mainTab === key ? 'var(--accent)' : 'transparent',
                  color: mainTab === key ? '#000' : 'var(--text3)',
                  transition: 'all 0.2s', fontFamily: 'var(--font)',
                  display: 'flex', alignItems: 'center', gap: 7,
                }}
              >
                {label}
                {badge !== null && (
                  <span style={{
                    fontSize: 9, fontWeight: 800, lineHeight: 1,
                    background: mainTab === key ? 'rgba(0,0,0,0.2)' : 'var(--accent-dim)',
                    color: mainTab === key ? '#000' : 'var(--accent)',
                    padding: '2px 6px', borderRadius: 999, minWidth: 18, textAlign: 'center',
                  }}>{badge}</span>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* ── PHOTOS TAB ───────────────────────────────────── */}
        {mainTab === 'photos' && <PhotoPool onShowCaptions={() => setMainTab('captions')} />}

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
      display: 'flex', alignItems: 'center', gap: 7,
      background: 'var(--bg2)', border: '1px solid var(--border2)',
      borderRadius: 999, padding: '7px 16px',
      boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
    }}>
      <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--text)', fontVariantNumeric: 'tabular-nums' }}>{num}</span>
      <span style={{ fontSize: 11, color: 'var(--text3)', letterSpacing: '0.03em' }}>{label}</span>
    </div>
  );
}

// ─── SettingsPanel ────────────────────────────────────────────────────────────

interface SettingsPanelProps {
  dumps: Dump[];
  photos?: Photo[];
  poolCount: number;
  usedCount: number;
  colorMode: ColorMode;
  accentHex: string;
  applyAccent: (hex: string) => void;
  setColorMode: (m: ColorMode) => void;
  onShowOnboarding: () => void;
  onClose: () => void;
  onNewDump: () => void;
  onScrollToDump: (id: string) => void;
  onResetAll: () => void;
}

const FORMULA_TEMPLATE_7 = TEMPLATE_7;
const FORMULA_TEMPLATE_12 = TEMPLATE_12;

const PLATFORM_PRESETS = [
  {
    id: 'instagram',
    label: 'Instagram',
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 100 12.324 6.162 6.162 0 000-12.324zM12 16a4 4 0 110-8 4 4 0 010 8zm6.406-11.845a1.44 1.44 0 100 2.881 1.44 1.44 0 000-2.881z"/>
      </svg>
    ),
    desc: '10–12 slides · square or portrait',
    color: '#E1306C',
    hint: 'Peak zone: 10–12 photos. Hook in slot 1, closer in slot 12.',
  },
  {
    id: 'tiktok',
    label: 'TikTok',
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
        <path d="M19.59 6.69a4.83 4.83 0 01-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 01-2.88 2.5 2.89 2.89 0 01-2.89-2.89 2.89 2.89 0 012.89-2.89c.28 0 .54.04.79.1V9.01a6.33 6.33 0 00-.79-.05 6.34 6.34 0 00-6.34 6.34 6.34 6.34 0 006.34 6.34 6.34 6.34 0 006.33-6.34V8.88a8.28 8.28 0 004.84 1.56V7.01a4.85 4.85 0 01-1.07-.32z"/>
      </svg>
    ),
    desc: '7–9 slides · vertical preferred',
    color: '#69C9D0',
    hint: 'Keep it tight: 7 photos, fast hook, punchy closer.',
  },
  {
    id: 'twitter',
    label: 'X / Twitter',
    icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.745l7.73-8.835L1.254 2.25H8.08l4.253 5.622zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
      </svg>
    ),
    desc: '4 slides max · landscape or square',
    color: '#1D9BF0',
    hint: 'Max 4 images on X. Use hook + 2 details + closer.',
  },
];

function SettingsPanel({
  dumps, poolCount, usedCount,
  colorMode, accentHex, applyAccent, setColorMode,
  onShowOnboarding, onClose, onNewDump, onScrollToDump, onResetAll,
}: SettingsPanelProps) {
  const [activeSection, setActiveSection] = useState<'dumps' | 'appearance' | 'platform' | 'formula' | 'about'>('dumps');
  const [confirmReset, setConfirmReset] = useState(false);

  const NAV_TABS = [
    { id: 'dumps',      label: 'My Dumps',   icon: '⊟' },
    { id: 'appearance', label: 'Look',        icon: '◑' },
    { id: 'platform',   label: 'Platform',    icon: '◈' },
    { id: 'formula',    label: 'Formula',     icon: '✦' },
    { id: 'about',      label: 'About',       icon: '○' },
  ] as const;

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={onClose}
        style={{
          position: 'fixed', inset: 0, zIndex: 200,
          background: 'rgba(0,0,0,0.55)', backdropFilter: 'blur(6px)',
          animation: 'fadeIn 0.18s ease',
        }}
      />

      {/* Panel */}
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          position: 'fixed', top: 0, right: 0, bottom: 0,
          width: 'min(420px, 92vw)', zIndex: 201,
          background: '#0e0e0e',
          borderLeft: '1px solid rgba(255,255,255,0.07)',
          display: 'flex', flexDirection: 'column',
          animation: 'slideInRight 0.22s cubic-bezier(0.16,1,0.3,1)',
          boxShadow: '-24px 0 80px rgba(0,0,0,0.7)',
        }}
      >
        {/* Header */}
        <div style={{
          padding: '20px 24px 16px',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          flexShrink: 0,
        }}>
          <div>
            <p style={{ fontSize: 9, fontWeight: 800, letterSpacing: '0.2em', color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 3 }}>
              DUMPSTER
            </p>
            <p style={{ fontSize: 18, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.01em' }}>
              Settings
            </p>
          </div>
          <button
            onClick={onClose}
            style={{
              width: 32, height: 32, borderRadius: '50%',
              background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.08)',
              color: 'var(--text3)', cursor: 'pointer', fontSize: 14,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              transition: 'all 0.15s',
            }}
            onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.12)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--text)'; }}
            onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.06)'; (e.currentTarget as HTMLButtonElement).style.color = 'var(--text3)'; }}
          >✕</button>
        </div>

        {/* Nav tabs */}
        <div style={{
          display: 'flex', padding: '12px 16px', gap: 4,
          borderBottom: '1px solid rgba(255,255,255,0.06)', flexShrink: 0,
          overflowX: 'auto',
        }}>
          {NAV_TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveSection(tab.id)}
              style={{
                display: 'flex', alignItems: 'center', gap: 5,
                padding: '7px 12px', borderRadius: 8, border: 'none',
                background: activeSection === tab.id ? 'var(--accent-dim)' : 'transparent',
                color: activeSection === tab.id ? 'var(--accent)' : 'var(--text3)',
                fontSize: 10, fontWeight: 700, letterSpacing: '0.08em',
                textTransform: 'uppercase', cursor: 'pointer',
                transition: 'all 0.15s', flexShrink: 0,
                fontFamily: 'var(--font)',
                outline: activeSection === tab.id ? '1px solid rgba(200,169,110,0.2)' : 'none',
              }}
            >
              <span style={{ fontSize: 12 }}>{tab.icon}</span>
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '20px 24px' }}>

          {/* ─── MY DUMPS ─── */}
          {activeSection === 'dumps' && (
            <div>
              <SectionLabel>Your Dumps</SectionLabel>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {dumps.length === 0 && (
                  <p style={{ fontSize: 13, color: 'var(--text3)', padding: '12px 0' }}>No dumps yet. Create one below.</p>
                )}
                {dumps.map((dump) => {
                  const count = dump.photos.length;
                  const inPeak = count >= 10 && count <= 12;
                  return (
                    <button
                      key={dump.id}
                      onClick={() => onScrollToDump(dump.id)}
                      style={{
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        padding: '12px 16px', borderRadius: 12,
                        background: 'rgba(255,255,255,0.03)',
                        border: '1px solid rgba(255,255,255,0.06)',
                        cursor: 'pointer', transition: 'all 0.15s', textAlign: 'left',
                        width: '100%',
                      }}
                      onMouseEnter={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'var(--accent-dim2)';
                        (e.currentTarget as HTMLButtonElement).style.borderColor = 'rgba(200,169,110,0.2)';
                      }}
                      onMouseLeave={(e) => {
                        (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.03)';
                        (e.currentTarget as HTMLButtonElement).style.borderColor = 'rgba(255,255,255,0.06)';
                      }}
                    >
                      <div>
                        <p style={{ fontSize: 8, fontWeight: 800, letterSpacing: '0.18em', color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 3 }}>
                          DUMP {String(dump.num).padStart(2, '0')}
                        </p>
                        <p style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)', fontFamily: 'var(--font-display)' }}>
                          {dump.title || 'Untitled'}
                        </p>
                      </div>
                      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                        <span style={{
                          fontSize: 9, fontWeight: 700, letterSpacing: '0.06em',
                          color: inPeak ? 'var(--accent)' : count === 0 ? 'var(--border3)' : 'var(--text3)',
                        }}>
                          {count}/20
                        </span>
                        {inPeak && (
                          <span style={{ fontSize: 7, fontWeight: 800, letterSpacing: '0.1em', color: 'var(--accent)', textTransform: 'uppercase' }}>
                            ★ PEAK
                          </span>
                        )}
                        {/* Mini photo bar */}
                        <div style={{ display: 'flex', gap: 2 }}>
                          {Array.from({ length: Math.min(count, 12) }).map((_, i) => (
                            <div key={i} style={{ width: 3, height: 12, borderRadius: 1, background: inPeak ? 'var(--accent)' : 'var(--text3)', opacity: 0.6 + (i / 20) * 0.4 }} />
                          ))}
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>

              {/* New dump CTA */}
              <button
                onClick={onNewDump}
                style={{
                  width: '100%', marginTop: 12, padding: '12px 16px',
                  borderRadius: 12, border: '1.5px dashed rgba(200,169,110,0.25)',
                  background: 'transparent', color: 'var(--accent)',
                  fontSize: 11, fontWeight: 800, letterSpacing: '0.12em',
                  textTransform: 'uppercase', cursor: 'pointer', transition: 'all 0.15s',
                  fontFamily: 'var(--font)',
                }}
                onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--accent)'; (e.currentTarget as HTMLButtonElement).style.background = 'var(--accent-dim2)'; }}
                onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.borderColor = 'rgba(200,169,110,0.25)'; (e.currentTarget as HTMLButtonElement).style.background = 'transparent'; }}
              >
                + New Dump
              </button>

              <div style={{ marginTop: 24, padding: '16px', borderRadius: 12, background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.05)' }}>
                <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.12em', color: 'var(--text3)', textTransform: 'uppercase', marginBottom: 10 }}>Pool Stats</p>
                <div style={{ display: 'flex', gap: 16 }}>
                  <div>
                    <p style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)' }}>{poolCount}</p>
                    <p style={{ fontSize: 10, color: 'var(--text3)' }}>In Pool</p>
                  </div>
                  <div>
                    <p style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)' }}>{usedCount}</p>
                    <p style={{ fontSize: 10, color: 'var(--text3)' }}>In Dumps</p>
                  </div>
                  <div>
                    <p style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)' }}>{dumps.length}</p>
                    <p style={{ fontSize: 10, color: 'var(--text3)' }}>Dumps</p>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* ─── APPEARANCE ─── */}
          {activeSection === 'appearance' && (
            <div>
              <SectionLabel>Accent Color</SectionLabel>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 28 }}>
                {ACCENT_PRESETS.map((p) => (
                  <button
                    key={p.value}
                    onClick={() => applyAccent(p.value)}
                    title={p.label}
                    style={{
                      width: 40, height: 40, borderRadius: 12,
                      background: p.value,
                      border: accentHex === p.value ? '3px solid #fff' : '3px solid transparent',
                      cursor: 'pointer', transition: 'all 0.15s',
                      boxShadow: accentHex === p.value ? `0 0 0 1px ${p.value}` : 'none',
                    }}
                  />
                ))}
                {/* Custom hex input */}
                <label title="Custom color" style={{
                  width: 40, height: 40, borderRadius: 12, overflow: 'hidden',
                  border: '1px solid rgba(255,255,255,0.12)', cursor: 'pointer',
                  position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'rgba(255,255,255,0.04)',
                }}>
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--text3)" strokeWidth="2">
                    <circle cx="13.5" cy="6.5" r=".5" fill="var(--text3)"/><circle cx="17.5" cy="10.5" r=".5" fill="var(--text3)"/><circle cx="8.5" cy="7.5" r=".5" fill="var(--text3)"/><circle cx="6.5" cy="12.5" r=".5" fill="var(--text3)"/>
                    <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 011.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"/>
                  </svg>
                  <input
                    type="color"
                    value={accentHex}
                    onChange={(e) => applyAccent(e.target.value)}
                    style={{ position: 'absolute', opacity: 0, width: '100%', height: '100%', cursor: 'pointer' }}
                  />
                </label>
              </div>

              <SectionLabel>Theme</SectionLabel>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {([
                  { id: 'dark',   label: 'Dark',   desc: 'OLED-black, always dark', icon: '●' },
                  { id: 'day',    label: 'Light',   desc: 'Clean, minimal light mode', icon: '○' },
                  { id: 'system', label: 'System',  desc: 'Follows your OS setting', icon: '◑' },
                ] as const).map((m) => (
                  <button
                    key={m.id}
                    onClick={() => setColorMode(m.id)}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 14,
                      padding: '14px 16px', borderRadius: 12, textAlign: 'left',
                      background: colorMode === m.id ? 'var(--accent-dim2)' : 'rgba(255,255,255,0.03)',
                      border: `1px solid ${colorMode === m.id ? 'rgba(200,169,110,0.25)' : 'rgba(255,255,255,0.06)'}`,
                      cursor: 'pointer', transition: 'all 0.15s', width: '100%',
                    }}
                  >
                    <span style={{ fontSize: 18, color: colorMode === m.id ? 'var(--accent)' : 'var(--text3)', lineHeight: 1 }}>{m.icon}</span>
                    <div>
                      <p style={{ fontSize: 13, fontWeight: 600, color: colorMode === m.id ? 'var(--accent)' : 'var(--text)' }}>{m.label}</p>
                      <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>{m.desc}</p>
                    </div>
                    {colorMode === m.id && (
                      <div style={{ marginLeft: 'auto' }}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" strokeWidth="2.5"><polyline points="20 6 9 17 4 12"/></svg>
                      </div>
                    )}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* ─── PLATFORM ─── */}
          {activeSection === 'platform' && (
            <div>
              <SectionLabel>Platform Presets</SectionLabel>
              <p style={{ fontSize: 12, color: 'var(--text3)', marginBottom: 16, lineHeight: 1.6 }}>
                Each platform has different optimal dump sizes. Build for the platform you're posting to.
              </p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {PLATFORM_PRESETS.map((plat) => (
                  <div
                    key={plat.id}
                    style={{
                      padding: '18px 20px', borderRadius: 14,
                      background: 'rgba(255,255,255,0.03)',
                      border: '1px solid rgba(255,255,255,0.06)',
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 }}>
                      <div style={{
                        width: 36, height: 36, borderRadius: 10,
                        background: `${plat.color}18`,
                        border: `1px solid ${plat.color}30`,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: plat.color, flexShrink: 0,
                      }}>
                        {plat.icon}
                      </div>
                      <div>
                        <p style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)' }}>{plat.label}</p>
                        <p style={{ fontSize: 10, color: 'var(--text3)', letterSpacing: '0.04em' }}>{plat.desc}</p>
                      </div>
                    </div>
                    <p style={{
                      fontSize: 11, color: 'var(--text3)', lineHeight: 1.6,
                      padding: '8px 10px', borderRadius: 8,
                      background: 'rgba(255,255,255,0.03)',
                    }}>
                      {plat.hint}
                    </p>
                  </div>
                ))}
              </div>

              <div style={{ marginTop: 20, padding: '16px', borderRadius: 12, background: 'var(--accent-dim2)', border: '1px solid rgba(200,169,110,0.15)' }}>
                <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.12em', color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 8 }}>
                  ✦ Pro Tip
                </p>
                <p style={{ fontSize: 12, color: 'var(--text3)', lineHeight: 1.65 }}>
                  Aim for the <strong style={{ color: 'var(--text2)' }}>Peak Zone (10–12)</strong> for Instagram. TikTok performs better with tight 7-photo edits. X/Twitter prefers a clean 4-photo set.
                </p>
              </div>
            </div>
          )}

          {/* ─── FORMULA ─── */}
          {activeSection === 'formula' && (
            <div>
              <SectionLabel>The Formula</SectionLabel>
              <p style={{ fontSize: 12, color: 'var(--text3)', marginBottom: 20, lineHeight: 1.65 }}>
                A proven 12-slot sequencing framework. Each slot has a role — put the right photo in the right position to maximise swipes.
              </p>

              <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.14em', color: 'var(--text3)', textTransform: 'uppercase', marginBottom: 10 }}>
                12-Slide Template
              </p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 24 }}>
                {FORMULA_TEMPLATE_12.map((role, i) => (
                  <div
                    key={role}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 10,
                      padding: '9px 14px', borderRadius: 10,
                      background: i === 0 ? 'var(--accent-dim2)' : 'rgba(255,255,255,0.02)',
                      border: `1px solid ${i === 0 ? 'rgba(200,169,110,0.18)' : 'rgba(255,255,255,0.04)'}`,
                    }}
                  >
                    <span style={{
                      fontSize: 9, fontWeight: 800, color: i === 0 ? 'var(--accent)' : 'var(--text3)',
                      letterSpacing: '0.1em', minWidth: 20, textAlign: 'right',
                    }}>{String(i + 1).padStart(2, '0')}</span>
                    <span style={{ fontSize: 12, color: i === 0 ? 'var(--accent)' : 'var(--text2)', fontWeight: i === 0 ? 700 : 500 }}>
                      {SLOT_LABELS[role]}
                    </span>
                  </div>
                ))}
              </div>

              <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.14em', color: 'var(--text3)', textTransform: 'uppercase', marginBottom: 10 }}>
                7-Slide Tight Edit
              </p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 24 }}>
                {FORMULA_TEMPLATE_7.map((role, i) => (
                  <div
                    key={role}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 10,
                      padding: '9px 14px', borderRadius: 10,
                      background: 'rgba(255,255,255,0.02)',
                      border: '1px solid rgba(255,255,255,0.04)',
                    }}
                  >
                    <span style={{ fontSize: 9, fontWeight: 800, color: 'var(--text3)', letterSpacing: '0.1em', minWidth: 20, textAlign: 'right' }}>
                      {String(i + 1).padStart(2, '0')}
                    </span>
                    <span style={{ fontSize: 12, color: 'var(--text2)', fontWeight: 500 }}>
                      {SLOT_LABELS[role]}
                    </span>
                  </div>
                ))}
              </div>

              <div style={{ padding: '16px', borderRadius: 12, background: 'var(--accent-dim2)', border: '1px solid rgba(200,169,110,0.15)' }}>
                <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.12em', color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 8 }}>Peak Zone</p>
                <p style={{ fontSize: 12, color: 'var(--text3)', lineHeight: 1.65 }}>
                  <strong style={{ color: 'var(--accent)' }}>10–12 photos</strong> is the sweet spot. Under 7 and you lose narrative depth. Over 15 and you lose attention. The gold bar in each dump card turns bright when you're in the zone.
                </p>
              </div>
            </div>
          )}

          {/* ─── ABOUT ─── */}
          {activeSection === 'about' && (
            <div>
              <SectionLabel>About DUMPSTER</SectionLabel>
              <div style={{ padding: '20px', borderRadius: 14, background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.05)', marginBottom: 16, textAlign: 'center' }}>
                <div style={{
                  width: 56, height: 56, borderRadius: 14,
                  background: 'linear-gradient(135deg, #1a1a1a 0%, #0a0a0a 100%)',
                  border: '1px solid var(--border2)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  margin: '0 auto 12px', fontSize: 26,
                }}>🗑️</div>
                <p style={{ fontSize: 18, fontWeight: 700, color: 'var(--text)', fontFamily: 'var(--font-display)', marginBottom: 4 }}>DUMPSTER</p>
                <p style={{ fontSize: 11, color: 'var(--text3)', letterSpacing: '0.06em' }}>v0.9 Beta · Web</p>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                <PanelRow icon="?" label="How to use" onClick={onShowOnboarding} />
                <PanelRow
                  icon="↗"
                  label="iOS App (coming soon)"
                  onClick={() => window.open('https://apps.apple.com', '_blank')}
                />
              </div>

              <div style={{ marginTop: 24 }}>
                <SectionLabel>Danger Zone</SectionLabel>
                {!confirmReset ? (
                  <button
                    onClick={() => setConfirmReset(true)}
                    style={{
                      width: '100%', padding: '12px 16px', borderRadius: 12,
                      background: 'rgba(224,92,92,0.06)', border: '1px solid rgba(224,92,92,0.2)',
                      color: 'var(--red)', fontSize: 12, fontWeight: 700,
                      cursor: 'pointer', transition: 'all 0.15s', fontFamily: 'var(--font)',
                    }}
                    onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(224,92,92,0.12)'; }}
                    onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(224,92,92,0.06)'; }}
                  >
                    Reset All Data
                  </button>
                ) : (
                  <div style={{ padding: '16px', borderRadius: 12, background: 'rgba(224,92,92,0.08)', border: '1px solid rgba(224,92,92,0.25)' }}>
                    <p style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 12, lineHeight: 1.55 }}>
                      This will delete all dumps, photos, and captions. <strong style={{ color: 'var(--red)' }}>This cannot be undone.</strong>
                    </p>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <button
                        onClick={() => setConfirmReset(false)}
                        style={{
                          flex: 1, padding: '9px', borderRadius: 8,
                          background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)',
                          color: 'var(--text3)', fontSize: 11, fontWeight: 700, cursor: 'pointer',
                          fontFamily: 'var(--font)',
                        }}
                      >Cancel</button>
                      <button
                        onClick={onResetAll}
                        style={{
                          flex: 1, padding: '9px', borderRadius: 8,
                          background: 'rgba(224,92,92,0.2)', border: '1px solid rgba(224,92,92,0.4)',
                          color: 'var(--red)', fontSize: 11, fontWeight: 800, cursor: 'pointer',
                          fontFamily: 'var(--font)',
                        }}
                      >Delete Everything</button>
                    </div>
                  </div>
                )}
              </div>

              <p style={{ fontSize: 11, color: 'var(--border3)', marginTop: 32, textAlign: 'center', lineHeight: 1.6 }}>
                © {new Date().getFullYear()} DUMPSTER. Photos stay local — nothing is uploaded.
              </p>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p style={{
      fontSize: 9, fontWeight: 800, letterSpacing: '0.18em',
      color: 'var(--text3)', textTransform: 'uppercase', marginBottom: 10,
      fontFamily: 'var(--font)',
    }}>{children}</p>
  );
}

function PanelRow({ icon, label, onClick }: { icon: string; label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 12, width: '100%',
        padding: '13px 16px', borderRadius: 12, border: 'none', textAlign: 'left',
        background: 'rgba(255,255,255,0.03)', cursor: 'pointer', transition: 'all 0.15s',
      }}
      onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.07)'; }}
      onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.03)'; }}
    >
      <span style={{ fontSize: 14, color: 'var(--text3)', width: 20, textAlign: 'center' }}>{icon}</span>
      <span style={{ fontSize: 13, color: 'var(--text)', fontWeight: 500 }}>{label}</span>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="var(--text3)" strokeWidth="2" style={{ marginLeft: 'auto' }}><polyline points="9 18 15 12 9 6"/></svg>
    </button>
  );
}

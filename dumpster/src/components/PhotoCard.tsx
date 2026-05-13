import { useState, useEffect, useRef } from 'react';
import type { Photo } from '../types';
import { useStore } from '../store';
import { getSlotRole, SLOT_LABELS } from '../formula';

interface PhotoCardProps {
  photo: Photo;
  index: number;
  used?: boolean;
  totalInDump?: number;
  // menu actions
  onToggleHuji: () => void;
  onToggleStar: () => void;
  onRemove: () => void;
  // optional click
  onClick?: () => void;
  // drag handles
  dragRef?: (el: HTMLDivElement | null) => void;
  dragStyle?: React.CSSProperties;
  dragAttributes?: Record<string, unknown>;
  dragListeners?: Record<string, unknown>;
  isDragging?: boolean;
  width?: number;
  height?: number;
  // pool selection mode
  selected?: boolean;
}

export default function PhotoCard({
  photo, index, used, totalInDump,
  onToggleHuji, onToggleStar, onRemove,
  onClick, dragRef, dragStyle, dragAttributes, dragListeners, isDragging,
  width = 175, height = 232,
  selected = false,
}: PhotoCardProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [editingLabel, setEditingLabel] = useState(false);
  const [labelInput, setLabelInput] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);
  const labelInputRef = useRef<HTMLInputElement>(null);
  const lastTapRef = useRef(0);
  const { setLightbox, addLabel, removeLabel, setCategory } = useStore();
  const [editingCategory, setEditingCategory] = useState(false);
  const [categoryInput, setCategoryInput] = useState(photo.category);

  const isVideo = /\.(mp4|mov|webm)$/i.test(photo.filename);

  // Close menu on outside click
  useEffect(() => {
    if (!menuOpen) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [menuOpen]);

  // Focus label input when editing
  useEffect(() => {
    if (editingLabel) labelInputRef.current?.focus();
  }, [editingLabel]);

  const handleClick = (e: React.MouseEvent) => {
    if (used) return;
    const now = Date.now();
    const delta = now - lastTapRef.current;
    lastTapRef.current = now;
    if (delta < 300) {
      // Double-tap → lightbox
      e.stopPropagation();
      setLightbox(photo.id);
    } else {
      onClick?.();
    }
  };

  const slotRole = totalInDump ? getSlotRole(index, totalInDump) : null;

  // Border logic: huji = red, selected = green, dragging = gold, default
  const borderColor = selected
    ? 'var(--green, #4CAF50)'
    : photo.isHuji
    ? 'rgba(190,60,45,0.8)'
    : isDragging
    ? 'var(--accent)'
    : 'var(--border)';

  return (
    <div
      ref={dragRef}
      className="photo-card"
      onClick={handleClick}
      style={{
        ...dragStyle,
        flexShrink: 0,
        width, height,
        borderRadius: 10,
        border: `2px solid ${borderColor}`,
        overflow: 'visible',
        position: 'relative',
        cursor: dragListeners ? (isDragging ? 'grabbing' : 'grab') : (onClick ? 'pointer' : 'default'),
        touchAction: dragListeners ? 'none' : 'auto',
        background: 'var(--bg2)',
        opacity: isDragging ? 0.45 : used ? 0.38 : 1,
        transition: 'border-color 0.15s, opacity 0.15s',
        pointerEvents: used ? 'none' : 'auto',
      }}
      onMouseEnter={(e) => {
        if (!used && !selected && !photo.isHuji)
          (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--accent)';
      }}
      onMouseLeave={(e) => {
        if (!selected && !photo.isHuji)
          (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border)';
      }}
      {...(dragAttributes || {})}
      {...(dragListeners || {})}
    >
      {/* Clipped inner area */}
      <div style={{ position: 'absolute', inset: 0, borderRadius: 10, overflow: 'hidden' }}>
        {isVideo ? (
          <video
            src={photo.url}
            style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
            muted playsInline preload="metadata"
          />
        ) : (
          <img
            src={photo.url}
            alt={photo.filename}
            style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
            draggable={false}
          />
        )}

        {/* Used checkmark overlay */}
        {used && (
          <div style={{
            position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.4)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 22, color: 'var(--accent)',
          }}>✓</div>
        )}

        {/* Selected overlay */}
        {selected && !used && (
          <div style={{
            position: 'absolute', inset: 0, background: 'rgba(76,175,80,0.15)',
          }} />
        )}

        {/* Video badge */}
        {isVideo && (
          <div style={{
            position: 'absolute', bottom: 28, left: 6,
            background: 'rgba(0,0,0,0.65)', borderRadius: 3,
            padding: '2px 5px', fontSize: 8, color: '#fff', fontWeight: 700, letterSpacing: '0.08em',
          }}>VIDEO</div>
        )}

        {/* Bottom gradient + category label (editable) */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          padding: '24px 8px 7px',
          background: 'linear-gradient(transparent, rgba(0,0,0,0.75))',
        }}>
          {editingCategory ? (
            <input
              value={categoryInput}
              onChange={e => setCategoryInput(e.target.value.toUpperCase())}
              onBlur={() => {
                if (categoryInput.trim()) setCategory(photo.id, categoryInput.trim().toUpperCase());
                setEditingCategory(false);
              }}
              onKeyDown={e => {
                if (e.key === 'Enter') { e.currentTarget.blur(); }
                if (e.key === 'Escape') { setEditingCategory(false); }
              }}
              autoFocus
              onClick={e => e.stopPropagation()}
              style={{
                fontSize: 7, fontWeight: 700, letterSpacing: '0.12em',
                background: 'transparent', border: 'none', outline: '1px solid var(--gold)',
                color: 'var(--accent)', width: '100%', padding: '1px 2px',
                fontFamily: 'var(--font)',
              }}
            />
          ) : (
            <span
              onClick={e => { e.stopPropagation(); setCategoryInput(photo.category); setEditingCategory(true); }}
              style={{
                fontSize: 7, fontWeight: 700, textTransform: 'uppercase',
                letterSpacing: '0.12em', color: 'rgba(255,255,255,0.75)',
                cursor: 'text', display: 'block',
              }}
              title="Click to edit category"
            >
              {photo.category}
            </span>
          )}
        </div>

        {/* Slot role ghost (shown when in dump and slot is known) */}
        {slotRole && (
          <div style={{
            position: 'absolute', top: 0, left: 0, right: 0,
            background: 'linear-gradient(rgba(0,0,0,0.5), transparent)',
            padding: '6px 6px 16px',
          }}>
            <span style={{
              fontSize: 6, fontWeight: 800, letterSpacing: '0.15em',
              color: 'rgba(200,169,110,0.7)', textTransform: 'uppercase',
            }}>
              {SLOT_LABELS[slotRole]}
            </span>
          </div>
        )}
      </div>

      {/* Number badge */}
      <div style={{
        position: 'absolute', top: 6, left: 6,
        background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)',
        borderRadius: 4, padding: '2px 6px',
        fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.9)',
        zIndex: 2, pointerEvents: 'none',
      }}>
        {String(index + 1).padStart(2, '0')}
      </div>

      {/* Top-right: HUJI badge + star badge (hidden when menu open) */}
      {!menuOpen && (
        <div style={{
          position: 'absolute', top: 6, right: 6,
          display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4,
          zIndex: 3, pointerEvents: 'none',
        }}>
          {photo.isHuji && (
            <span style={{
              fontSize: 7, background: 'rgba(190,60,45,0.92)', color: '#fff',
              padding: '2px 5px', borderRadius: 3, fontWeight: 700, letterSpacing: '0.1em',
            }}>HUJI</span>
          )}
          {photo.starred && (
            <span style={{
              fontSize: 9, color: 'var(--accent)',
              background: 'rgba(0,0,0,0.55)', borderRadius: 3, padding: '1px 3px',
            }}>★</span>
          )}
        </div>
      )}

      {/* Labels (below card) */}
      {photo.labels.length > 0 && (
        <div style={{
          position: 'absolute', bottom: -20, left: 0, right: 0,
          display: 'flex', flexWrap: 'wrap', gap: 3, justifyContent: 'center',
        }}>
          {photo.labels.slice(0, 3).map(l => (
            <span
              key={l}
              onClick={e => { e.stopPropagation(); removeLabel(photo.id, l); }}
              style={{
                fontSize: 7, background: 'var(--gold-dim)', color: 'var(--accent)',
                padding: '1px 4px', borderRadius: 2, fontWeight: 600, cursor: 'pointer',
              }}
            >{l}</span>
          ))}
        </div>
      )}

      {/* Three-dot menu */}
      <div
        ref={menuRef}
        className="photo-menu-wrap"
        style={{ position: 'absolute', top: 6, right: 6, zIndex: 10 }}
      >
        <button
          className="photo-menu-btn"
          onClick={(e) => { e.stopPropagation(); setMenuOpen(o => !o); }}
          style={{
            width: 28, height: 28, borderRadius: '50%',
            background: 'rgba(0,0,0,0.72)', backdropFilter: 'blur(8px)',
            border: '1px solid rgba(255,255,255,0.1)', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            opacity: menuOpen ? 1 : 0, transition: 'opacity 0.15s', padding: 0,
          }}
        >
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none">
            <circle cx="3" cy="8" r="1.5" fill="var(--accent)" />
            <circle cx="8" cy="8" r="1.5" fill="var(--accent)" />
            <circle cx="13" cy="8" r="1.5" fill="var(--accent)" />
          </svg>
        </button>

        {menuOpen && (
          <div
            onClick={e => e.stopPropagation()}
            style={{
              position: 'absolute', top: 34, right: 0,
              background: 'rgba(18,18,18,0.97)', backdropFilter: 'blur(20px)',
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: 14, overflow: 'hidden',
              minWidth: 200, boxShadow: '0 16px 48px rgba(0,0,0,0.7)', zIndex: 50,
              animation: 'slideDown 0.15s ease',
            }}
          >
            {/* Photo info header */}
            <div style={{ padding: '10px 14px 8px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
              <p style={{ fontSize: 10, color: 'var(--accent)', fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: 1 }}>{photo.category}</p>
              <p style={{ fontSize: 11, color: 'var(--text3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{photo.filename}</p>
            </div>

            {/* Lightbox */}
            <MenuItem
              icon={<IcoExpand />}
              label="Lightbox"
              onClick={() => { setLightbox(photo.id); setMenuOpen(false); }}
            />

            {/* Star */}
            <MenuItem
              icon={<IcoStar filled={photo.starred} />}
              label={photo.starred ? 'Unfavorite' : 'Favourite'}
              onClick={() => { onToggleStar(); setMenuOpen(false); }}
              accent={photo.starred}
            />

            {/* Huji */}
            <MenuItem
              icon={<IcoHuji active={photo.isHuji} />}
              label={photo.isHuji ? 'Unmark Huji' : 'Mark as Huji'}
              onClick={() => { onToggleHuji(); setMenuOpen(false); }}
              accent={photo.isHuji}
            />

            {/* Save / Download */}
            <MenuItem
              icon={<IcoDownload />}
              label="Save to Device"
              onClick={() => {
                const a = document.createElement('a');
                a.href = photo.url; a.download = photo.filename;
                document.body.appendChild(a); a.click(); document.body.removeChild(a);
                setMenuOpen(false);
              }}
            />

            {/* Rescan category */}
            <MenuItem
              icon={<IcoScan />}
              label="Rescan Category"
              onClick={() => {
                const cats = ['PORTRAIT','AUTOMOTIVE','STUDIO','NIGHTLIFE','FITNESS','ART','ARCHITECTURE','TRAVEL','FASHION','LIFESTYLE'];
                const next = cats[(cats.indexOf(photo.category) + 1) % cats.length];
                setCategory(photo.id, next);
                setMenuOpen(false);
              }}
            />

            {/* Move to dump (if not already in context) */}
            <MoveToDumpRow photo={photo} onClose={() => setMenuOpen(false)} />

            {/* Add label */}
            <div style={{ borderTop: '1px solid rgba(255,255,255,0.06)', marginTop: 2 }}>
              {editingLabel ? (
                <div style={{ padding: '8px 14px' }}>
                  <input
                    ref={labelInputRef}
                    value={labelInput}
                    onChange={e => setLabelInput(e.target.value)}
                    onKeyDown={e => {
                      if (e.key === 'Enter' && labelInput.trim()) {
                        addLabel(photo.id, labelInput.trim().toLowerCase());
                        setLabelInput(''); setEditingLabel(false); setMenuOpen(false);
                      }
                      if (e.key === 'Escape') setEditingLabel(false);
                    }}
                    placeholder="Add label…"
                    autoFocus
                    style={{
                      background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)',
                      borderRadius: 8, padding: '6px 10px', color: 'var(--text)',
                      fontSize: 13, width: '100%', fontFamily: 'var(--font)', outline: 'none',
                    }}
                  />
                </div>
              ) : (
                <MenuItem icon={<IcoLabel />} label="Add Label" onClick={() => setEditingLabel(true)} />
              )}
            </div>

            {/* Divider + Remove */}
            <div style={{ borderTop: '1px solid rgba(255,255,255,0.06)', marginTop: 2 }}>
              <MenuItem
                icon={<IcoTrash />}
                label={totalInDump !== undefined ? 'Remove from Dump' : 'Delete Photo'}
                danger
                onClick={() => { onRemove(); setMenuOpen(false); }}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Move-to-dump inline row ──────────────────────────────────────────────────

function MoveToDumpRow({ photo, onClose }: { photo: Photo; onClose: () => void }) {
  const { dumps, addPhotoToDump } = useStore();
  const [open, setOpen] = useState(false);
  const available = dumps.filter(d => !d.photos.includes(photo.id) && d.photos.length < 20);
  if (available.length === 0) return null;
  return (
    <div>
      <button
        onClick={(e) => { e.stopPropagation(); setOpen(o => !o); }}
        style={{
          display: 'flex', width: '100%', textAlign: 'left', alignItems: 'center',
          padding: '10px 14px', background: 'transparent', border: 'none',
          color: 'var(--text)', fontSize: 13, cursor: 'pointer', fontFamily: 'var(--font)',
          gap: 10, transition: 'background 0.1s',
        }}
        onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.05)')}
        onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
      >
        <IcoMove />
        <span style={{ flex: 1 }}>Add to Dump</span>
        <span style={{ fontSize: 10, color: 'var(--text3)' }}>{open ? '▲' : '▶'}</span>
      </button>
      {open && (
        <div style={{ background: 'rgba(255,255,255,0.03)', borderTop: '1px solid rgba(255,255,255,0.04)' }}>
          {available.map(d => (
            <button
              key={d.id}
              onClick={(e) => { e.stopPropagation(); addPhotoToDump(photo.id, d.id); onClose(); }}
              style={{
                display: 'flex', width: '100%', textAlign: 'left', alignItems: 'center',
                padding: '8px 14px 8px 38px', background: 'transparent', border: 'none',
                color: 'var(--text2)', fontSize: 12, cursor: 'pointer', fontFamily: 'var(--font)',
                gap: 8, transition: 'background 0.1s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.05)')}
              onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
            >
              <span style={{ fontSize: 9, color: 'var(--accent)', fontWeight: 800 }}>
                {String(d.num).padStart(2,'0')}
              </span>
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {d.title}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Menu item ────────────────────────────────────────────────────────────────

function MenuItem({ icon, label, onClick, danger, accent }: {
  icon: React.ReactNode; label: string; onClick: () => void; danger?: boolean; accent?: boolean;
}) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onClick(); }}
      style={{
        display: 'flex', width: '100%', textAlign: 'left', alignItems: 'center',
        padding: '10px 14px', background: 'transparent', border: 'none',
        color: danger ? 'var(--red)' : accent ? 'var(--accent)' : 'var(--text)',
        fontSize: 13, cursor: 'pointer', fontFamily: 'var(--font)',
        gap: 10, transition: 'background 0.1s',
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.05)')}
      onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
    >
      <span style={{ width: 16, height: 16, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{icon}</span>
      {label}
    </button>
  );
}

// ─── Icon components ──────────────────────────────────────────────────────────

const IcoExpand = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/>
    <line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/>
  </svg>
);
const IcoStar = ({ filled }: { filled?: boolean }) => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill={filled ? 'var(--accent)' : 'none'} stroke="currentColor" strokeWidth="2">
    <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
  </svg>
);
const IcoHuji = ({ active }: { active?: boolean }) => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill={active ? 'var(--red)' : 'none'} stroke={active ? 'var(--red)' : 'currentColor'} strokeWidth="2">
    <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>
  </svg>
);
const IcoDownload = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
    <polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>
  </svg>
);
const IcoScan = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/>
    <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
  </svg>
);
const IcoMove = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <line x1="12" y1="5" x2="12" y2="19"/><polyline points="19 12 12 19 5 12"/>
  </svg>
);
const IcoLabel = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/>
    <line x1="7" y1="7" x2="7.01" y2="7"/>
  </svg>
);
const IcoTrash = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
    <path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/>
  </svg>
);

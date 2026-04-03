import { useState, useEffect, useRef } from 'react';
import type { Photo } from '../types';
import { useStore } from '../store';
import { getSlotRole, SLOT_LABELS } from '../formula';
import CropEditor from './CropEditor';

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
  const [cropOpen, setCropOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const labelInputRef = useRef<HTMLInputElement>(null);
  const lastTapRef = useRef(0);
  const { setLightbox, addLabel, removeLabel, setCategory, cropPhoto } = useStore();
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
    ? 'var(--gold)'
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
        transition: 'border-color 0.25s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s cubic-bezier(0.16, 1, 0.3, 1), transform 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
        pointerEvents: used ? 'none' : 'auto',
      }}
      onMouseEnter={(e) => {
        if (!used && !selected && !photo.isHuji)
          (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)';
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
            fontSize: 22, color: 'var(--gold)',
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
                color: 'var(--gold)', width: '100%', padding: '1px 2px',
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
              fontSize: 9, color: 'var(--gold)',
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
                fontSize: 7, background: 'var(--gold-dim)', color: 'var(--gold)',
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
            width: 26, height: 26, borderRadius: '50%',
            background: 'rgba(0,0,0,0.65)', backdropFilter: 'blur(4px)',
            border: 'none', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            opacity: menuOpen ? 1 : 0, transition: 'opacity 0.15s', padding: 0,
          }}
        >
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
            <circle cx="3" cy="8" r="1.5" fill="#C8A96E" />
            <circle cx="8" cy="8" r="1.5" fill="#C8A96E" />
            <circle cx="13" cy="8" r="1.5" fill="#C8A96E" />
          </svg>
        </button>

        {menuOpen && (
          <div className="menu-dropdown" style={{
            position: 'absolute', top: 30, left: '50%', transform: 'translateX(-50%)',
            background: 'var(--menu-bg)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
            border: '1px solid var(--border2)',
            borderRadius: 10, overflow: 'hidden',
            minWidth: 160, boxShadow: '0 8px 32px rgba(0,0,0,0.25)', zIndex: 50,
          }}>
            <MenuItem label={photo.isHuji ? 'Unmark Huji' : 'Mark as Huji'}
              onClick={() => { onToggleHuji(); setMenuOpen(false); }} />
            <MenuItem label={photo.starred ? '★ Unfavorite' : '☆ Favorite'}
              onClick={() => { onToggleStar(); setMenuOpen(false); }} />
            <MenuItem label="🔍 Lightbox"
              onClick={() => { setLightbox(photo.id); setMenuOpen(false); }} />
            <MenuItem label="📐 Crop"
              onClick={() => { setCropOpen(true); setMenuOpen(false); }} />
            <MenuItem label="💾 Save to Photos"
              onClick={() => {
                const a = document.createElement('a');
                a.href = photo.url;
                a.download = photo.filename;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                setMenuOpen(false);
              }} />
            <div style={{ borderTop: '1px solid var(--border2)', margin: '4px 0' }} />
            {/* Add label */}
            {editingLabel ? (
              <div style={{ padding: '6px 14px' }} onClick={e => e.stopPropagation()}>
                <input
                  ref={labelInputRef}
                  value={labelInput}
                  onChange={e => setLabelInput(e.target.value)}
                  onKeyDown={e => {
                    if (e.key === 'Enter' && labelInput.trim()) {
                      addLabel(photo.id, labelInput.trim().toLowerCase());
                      setLabelInput('');
                      setEditingLabel(false);
                      setMenuOpen(false);
                    }
                    if (e.key === 'Escape') setEditingLabel(false);
                  }}
                  placeholder="Add label..."
                  style={{
                    background: 'var(--bg3)', border: '1px solid var(--border3)',
                    borderRadius: 4, padding: '4px 8px', color: 'var(--text)',
                    fontSize: 11, width: '100%', fontFamily: 'var(--font)',
                  }}
                />
              </div>
            ) : (
              <MenuItem label="+ Add Label"
                onClick={() => setEditingLabel(true)} />
            )}
            <div style={{ borderTop: '1px solid var(--border2)', margin: '4px 0' }} />
            <MenuItem label="Remove" danger onClick={() => { onRemove(); setMenuOpen(false); }} />
          </div>
        )}
      </div>

      {/* Crop Editor */}
      {cropOpen && (
        <CropEditor
          photoUrl={photo.url}
          onCropComplete={(croppedBlob) => {
            cropPhoto(photo.id, croppedBlob);
            setCropOpen(false);
          }}
          onCancel={() => setCropOpen(false)}
        />
      )}
    </div>
  );
}

function MenuItem({ label, onClick, danger }: { label: string; onClick: () => void; danger?: boolean }) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onClick(); }}
      style={{
        display: 'block', width: '100%', textAlign: 'left',
        padding: '9px 14px', background: 'transparent', border: 'none',
        color: danger ? 'var(--red)' : 'var(--text)',
        fontSize: 12, cursor: 'pointer', fontFamily: 'var(--font)', transition: 'background 0.1s',
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.06)')}
      onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
    >{label}</button>
  );
}

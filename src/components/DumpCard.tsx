import { useRef, useState } from 'react';
import {
  DndContext, DragOverlay, PointerSensor, useSensor, useSensors,
  closestCenter, type DragEndEvent, type DragStartEvent, type DragCancelEvent,
} from '@dnd-kit/core';
import {
  SortableContext, horizontalListSortingStrategy, useSortable,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import type { Dump, Photo } from '../types';
import { useStore } from '../store';
import { getSlotRole, SLOT_LABELS, CATEGORY_DISPLAY } from '../formula';
import PhotoCard from './PhotoCard';

interface Props {
  dump: Dump;
  active: boolean;
  onActivate: () => void;
}

export default function DumpCard({ dump, onActivate }: Props) {
  const {
    photos, removePhotoFromDump, reorderDumpPhotos, addPhotos,
    toggleStar, toggleHuji, deleteDump, checkDumpVibe, setAddingToDump,
    toggleDumpLike, approveDumpTitle, rejectDumpTitle,
  } = useStore();
  const fileRef = useRef<HTMLInputElement>(null);
  const [deleting, setDeleting] = useState(false);
  const [sharing, setSharing] = useState(false);
  const [draggingId, setDraggingId] = useState<string | null>(null);

  const handleShare = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (sharing || dumpPhotos.length === 0) return;
    setSharing(true);
    try {
      const imagePhotos = dumpPhotos.filter(p => !/\.(mp4|mov|webm)$/i.test(p.filename));
      const files: File[] = [];
      for (const photo of imagePhotos) {
        try {
          const res = await fetch(photo.url);
          const blob = await res.blob();
          files.push(new File([blob], photo.filename, { type: blob.type || 'image/jpeg' }));
        } catch { /* skip failed */ }
      }
      if (files.length > 0 && navigator.canShare?.({ files })) {
        await navigator.share({ files, title: dump.title });
      } else if (navigator.share) {
        await navigator.share({ title: dump.title, text: `${dump.title} · ${dumpPhotos.length} photos` });
      } else {
        // Desktop fallback: download first image
        const a = document.createElement('a');
        a.href = dumpPhotos[0].url;
        a.download = `${dump.title.replace(/\s+/g, '_')}.jpg`;
        a.click();
      }
    } catch { /* user cancelled or error */ }
    setSharing(false);
  };

  const dumpPhotos = dump.photos
    .map((id) => photos.find((p) => p.id === id))
    .filter(Boolean) as Photo[];

  // PointerSensor with 500ms delay: scroll works normally, drag only activates on hold
  // tolerance 12 gives more forgiveness for slight finger movement on iPhone
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { delay: 500, tolerance: 12 } }),
  );

  const scrollRowRef = useRef<HTMLDivElement>(null);

  const handleDragStart = (event: DragStartEvent) => {
    setDraggingId(event.active.id as string);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    setDraggingId(null);
    const { active, over } = event;
    if (over && active.id !== over.id)
      reorderDumpPhotos(dump.id, active.id as string, over.id as string);
  };

  const handleDragCancel = (_event: DragCancelEvent) => {
    setDraggingId(null);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    if (files.length) addPhotos(files);
    e.target.value = '';
  };

  const handleDelete = () => {
    setDeleting(true);
    setTimeout(() => deleteDump(dump.id), 350);
  };

  const fillRatio = dump.photos.length / 20;
  const draggingPhoto = draggingId ? dumpPhotos.find(p => p.id === draggingId) ?? null : null;

  return (
    <div
      className="dump-card-enter"
      onClick={onActivate}
      style={{
        marginBottom: 56, cursor: 'default',
        overflow: 'hidden',
        opacity: deleting ? 0 : 1,
        transform: deleting ? 'translateY(-8px) scale(0.98)' : 'none',
        transition: 'opacity 0.4s cubic-bezier(0.16, 1, 0.3, 1), transform 0.4s cubic-bezier(0.16, 1, 0.3, 1), outline-color 0.2s',
        outline: draggingId ? '2px dashed rgba(200,169,110,0.5)' : '2px solid transparent',
        outlineOffset: 6,
        borderRadius: 12,
      }}
    >
      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <p style={{
            fontSize: 10, fontWeight: 700, letterSpacing: '0.18em',
            color: 'var(--gold)', textTransform: 'uppercase',
          }}>
            DUMP {String(dump.num).padStart(2, '0')}
            {dump.vibeBadge === 'mismatch' && (
              <span style={{
                marginLeft: 8, fontSize: 8, background: 'rgba(224,92,92,0.15)',
                color: 'var(--red)', border: '1px solid rgba(224,92,92,0.3)',
                borderRadius: 3, padding: '1px 5px', letterSpacing: '0.1em',
              }}>⚠ VIBE MISMATCH</span>
            )}
          </p>
          {/* Heart — like this dump */}
          <button
            onPointerDown={e => e.stopPropagation()}
            onClick={(e) => { e.stopPropagation(); toggleDumpLike(dump.id); }}
            title={dump.liked ? 'Unlike dump' : 'Like dump'}
            style={{
              background: 'none', border: 'none', cursor: 'pointer', padding: '0 2px',
              display: 'flex', alignItems: 'center',
              transition: 'transform 0.15s',
              transform: dump.liked ? 'scale(1.2)' : 'scale(1)',
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24"
              fill={dump.liked ? '#e05c5c' : 'none'}
              stroke={dump.liked ? '#e05c5c' : 'var(--border3)'}
              strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
              style={{ transition: 'fill 0.2s, stroke 0.2s' }}>
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
          </button>
        </div>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <SmallBtn label="Check Vibe" onClick={(e) => { e.stopPropagation(); checkDumpVibe(dump.id); }} />
          <SmallBtn label={sharing ? '...' : '↑ Share'} onClick={handleShare} disabled={dumpPhotos.length === 0} />
          <SmallBtn label="✕ Delete" onClick={(e) => { e.stopPropagation(); handleDelete(); }} danger />
        </div>
      </div>

      {/* Title + thumbs */}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 4 }}>
        <div style={{ flex: 1 }}>
          <EditableTitle dump={dump} />
        </div>
        <div style={{ display: 'flex', gap: 4, paddingTop: 10, flexShrink: 0 }}>
          <button
            onPointerDown={e => e.stopPropagation()}
            onClick={(e) => { e.stopPropagation(); approveDumpTitle(dump.id); }}
            title="Keep this title"
            style={{
              background: dump.titleApproved === true ? 'rgba(80,180,80,0.15)' : 'var(--bg2)',
              border: `1px solid ${dump.titleApproved === true ? 'rgba(80,180,80,0.4)' : 'var(--border2)'}`,
              borderRadius: 6, padding: '5px 8px', cursor: 'pointer',
              transition: 'all 0.15s', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >
            <ThumbIcon up filled={dump.titleApproved === true} color={dump.titleApproved === true ? '#50b450' : 'var(--text3)'} />
          </button>
          <button
            onPointerDown={e => e.stopPropagation()}
            onClick={(e) => { e.stopPropagation(); rejectDumpTitle(dump.id); }}
            title="Regenerate title"
            style={{
              background: dump.titleApproved === false ? 'rgba(224,92,92,0.15)' : 'var(--bg2)',
              border: `1px solid ${dump.titleApproved === false ? 'rgba(224,92,92,0.4)' : 'var(--border2)'}`,
              borderRadius: 6, padding: '5px 8px', cursor: 'pointer',
              transition: 'all 0.15s', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >
            <ThumbIcon up={false} filled={dump.titleApproved === false} color={dump.titleApproved === false ? '#e05c5c' : 'var(--text3)'} />
          </button>
        </div>
      </div>

      {/* Subtitle: categories / count */}
      <p style={{
        fontSize: 13, color: 'var(--text3)', marginBottom: 20,
        fontStyle: 'italic', letterSpacing: '0.01em', lineHeight: 1.5,
      }}>
        {dumpPhotos.length > 0 && (() => {
          const unique = [...new Set(dumpPhotos.map(p => p.category.toUpperCase()))];
          return unique.map(cat => CATEGORY_DISPLAY[cat] ?? cat).join(' / ') + '\u2002\u2002';
        })()}
        <span style={{ fontStyle: 'normal' }}>
          {dump.photos.length === 0 ? 'No photos yet' : `${dump.photos.length}/20 photos`}
        </span>
        {dump.photos.length >= 10 && dump.photos.length <= 12 && (
          <span style={{ marginLeft: 8, color: 'var(--gold)', fontSize: 10, fontWeight: 700, fontStyle: 'normal' }}>★ PEAK ZONE</span>
        )}
      </p>

      {/* Sortable photo row */}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragStart={handleDragStart} onDragEnd={handleDragEnd} onDragCancel={handleDragCancel}>
        <SortableContext items={dump.photos} strategy={horizontalListSortingStrategy}>
          <div
            ref={scrollRowRef}
            className="dump-photos-row"
            style={{
              display: 'flex', gap: 8, overflowX: 'auto', overflowY: 'hidden', paddingBottom: 24,
              WebkitTouchCallout: 'none', userSelect: 'none', WebkitUserSelect: 'none',
            } as React.CSSProperties}
          >
            {dumpPhotos.map((photo, idx) => (
              <SortableSlot
                key={photo.id}
                photo={photo}
                index={idx}
                totalInDump={dumpPhotos.length}
                isDragActive={draggingId !== null}
                onRemoveFromDump={() => removePhotoFromDump(photo.id, dump.id)}
                onToggleStar={() => toggleStar(photo.id)}
                onToggleHuji={() => toggleHuji(photo.id)}
              />
            ))}

            {/* Add slot — always at the end */}
            {dump.photos.length < 20 && (
              <div
                onClick={(e) => {
                  e.stopPropagation();
                  setAddingToDump(dump.id);
                  document.getElementById('photo-pool')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }}
                style={{
                  flexShrink: 0, width: 175, height: 232,
                  borderRadius: 10, border: '1.5px dashed var(--border3)',
                  background: 'rgba(255,255,255,0.02)',
                  display: 'flex', flexDirection: 'column',
                  alignItems: 'center', justifyContent: 'center', gap: 8,
                  cursor: 'pointer', color: 'var(--text3)', transition: 'all 0.15s',
                  backdropFilter: 'blur(4px)',
                }}
                onMouseEnter={(e) => { (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)'; (e.currentTarget as HTMLDivElement).style.color = 'var(--gold)'; }}
                onMouseLeave={(e) => { (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)'; (e.currentTarget as HTMLDivElement).style.color = 'var(--text3)'; }}
              >
                <span style={{ fontSize: 22, lineHeight: 1 }}>+</span>
                <span style={{ fontSize: 8, letterSpacing: '0.12em', textTransform: 'uppercase', fontWeight: 600 }}>Add Photos</span>
                {(() => {
                  const nextSlot = getSlotRole(dump.photos.length, Math.max(dump.photos.length + 1, 7));
                  return nextSlot ? (
                    <span style={{ fontSize: 6, color: 'rgba(200,169,110,0.45)', letterSpacing: '0.1em', textAlign: 'center', padding: '0 8px' }}>
                      {SLOT_LABELS[nextSlot]}
                    </span>
                  ) : null;
                })()}
              </div>
            )}

            {/* File upload slot */}
            <div
              onClick={(e) => { e.stopPropagation(); fileRef.current?.click(); }}
              style={{
                flexShrink: 0, width: 175, height: 232,
                borderRadius: 10, border: '1.5px dashed var(--border3)',
                background: 'var(--bg2)', display: 'flex',
                flexDirection: 'column', alignItems: 'center',
                justifyContent: 'center', gap: 8,
                cursor: 'pointer', color: 'var(--text3)', transition: 'all 0.15s',
              }}
              onMouseEnter={(e) => { (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)'; (e.currentTarget as HTMLDivElement).style.color = 'var(--gold)'; }}
              onMouseLeave={(e) => { (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)'; (e.currentTarget as HTMLDivElement).style.color = 'var(--text3)'; }}
            >
              <span style={{ fontSize: 18, lineHeight: 1 }}>↑</span>
              <span style={{ fontSize: 8, letterSpacing: '0.12em', textTransform: 'uppercase', fontWeight: 600 }}>Upload</span>
            </div>
          </div>
        </SortableContext>

        {/* Floating drag thumbnail — follows finger */}
        <DragOverlay dropAnimation={null}>
          {draggingPhoto && (
            <div style={{
              width: 80, height: 107, borderRadius: 8,
              border: '2px solid var(--gold)',
              overflow: 'hidden',
              boxShadow: '0 8px 28px rgba(0,0,0,0.65)',
              opacity: 0.92,
              pointerEvents: 'none',
            }}>
              {/\.(mp4|mov|webm)$/i.test(draggingPhoto.filename) ? (
                <video src={draggingPhoto.url} style={{ width: '100%', height: '100%', objectFit: 'cover' }} muted playsInline />
              ) : (
                <img src={draggingPhoto.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} draggable={false} />
              )}
            </div>
          )}
        </DragOverlay>
      </DndContext>

      {/* Gold progress bar */}
      <div style={{ height: 2, background: 'var(--border2)', borderRadius: 1, position: 'relative', overflow: 'hidden', marginTop: 4 }}>
        <div style={{
          position: 'absolute', left: 0, top: 0, bottom: 0,
          width: `${fillRatio * 100}%`,
          background: dump.photos.length >= 10 && dump.photos.length <= 12 ? 'var(--gold)' : 'var(--text3)',
          borderRadius: 1, transition: 'width 0.3s ease',
        }} />
      </div>

      <input ref={fileRef} type="file" multiple accept="image/*,video/*"
        style={{ display: 'none' }} onChange={handleFileChange} />
    </div>
  );
}

// ─── Editable Title ───────────────────────────────────────────────────────────

function EditableTitle({ dump }: { dump: Dump }) {
  const { updateDumpTitle } = useStore();
  return (
    <input
      value={dump.title}
      onChange={(e) => updateDumpTitle(dump.id, e.target.value)}
      onClick={(e) => e.stopPropagation()}
      style={{
        display: 'block', width: '100%', background: 'transparent',
        border: 'none', outline: 'none', color: 'var(--text)',
        fontSize: 22, fontWeight: 700, letterSpacing: '-0.02em',
        lineHeight: 1.2, marginBottom: 6, padding: '0 0 2px',
        cursor: 'text', fontFamily: 'var(--font)',
      }}
    />
  );
}

// ─── Small Button ─────────────────────────────────────────────────────────────

function SmallBtn({ label, onClick, danger, disabled }: { label: string; onClick: (e: React.MouseEvent) => void; danger?: boolean; disabled?: boolean }) {
  return (
    <button
      onClick={disabled ? undefined : onClick}
      style={{
        fontSize: 9, fontWeight: 600, letterSpacing: '0.06em',
        padding: '4px 8px', borderRadius: 4,
        background: 'transparent',
        border: `1px solid ${danger ? 'rgba(224,92,92,0.3)' : 'var(--border2)'}`,
        color: disabled ? 'var(--border3)' : danger ? 'var(--red)' : 'var(--text3)',
        cursor: disabled ? 'default' : 'pointer', transition: 'all 0.15s',
        opacity: disabled ? 0.4 : 1,
      }}
      onMouseEnter={(e) => {
        if (disabled) return;
        (e.currentTarget as HTMLButtonElement).style.color = danger ? 'var(--red)' : 'var(--gold)';
        (e.currentTarget as HTMLButtonElement).style.borderColor = danger ? 'var(--red)' : 'var(--gold)';
      }}
      onMouseLeave={(e) => {
        if (disabled) return;
        (e.currentTarget as HTMLButtonElement).style.color = danger ? 'var(--red)' : 'var(--text3)';
        (e.currentTarget as HTMLButtonElement).style.borderColor = danger ? 'rgba(224,92,92,0.3)' : 'var(--border2)';
      }}
    >{label}</button>
  );
}

// ─── Sortable Slot ────────────────────────────────────────────────────────────

interface SlotProps {
  photo: Photo;
  index: number;
  totalInDump: number;
  isDragActive: boolean;
  onRemoveFromDump: () => void;
  onToggleStar: () => void;
  onToggleHuji: () => void;
}

function SortableSlot({ photo, index, totalInDump, isDragActive, onRemoveFromDump, onToggleStar, onToggleHuji }: SlotProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: photo.id });

  // When dragging: original slot stays full size but grayed out (DragOverlay shows the floating thumbnail)
  const dimmed = isDragActive && !isDragging;

  return (
    <PhotoCard
      photo={photo}
      index={index}
      totalInDump={totalInDump}
      dragRef={setNodeRef}
      dragStyle={{
        transform: CSS.Transform.toString(transform) ?? undefined,
        transition: transition ?? undefined,
        zIndex: isDragging ? 999 : 1,
        opacity: dimmed ? 0.45 : 1,
      }}
      dragAttributes={attributes as unknown as Record<string, unknown>}
      dragListeners={listeners as unknown as Record<string, unknown>}
      isDragging={isDragging}
      onToggleHuji={onToggleHuji}
      onToggleStar={onToggleStar}
      onRemove={onRemoveFromDump}
    />
  );
}

function ThumbIcon({ up, filled, color }: { up: boolean; filled: boolean; color: string }) {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill={filled ? color : 'none'} stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
      style={{ transform: up ? 'none' : 'scaleY(-1)', transition: 'fill 0.15s, stroke 0.15s' }}>
      <path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3H14z" />
      <path d="M7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3" />
    </svg>
  );
}

import { useRef, useState } from 'react';
import {
  DndContext, PointerSensor, useSensor, useSensors,
  closestCenter, type DragEndEvent,
} from '@dnd-kit/core';
import {
  SortableContext, horizontalListSortingStrategy, useSortable,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import type { Dump, Photo } from '../types';
import { useStore } from '../store';
import { getSlotRole, SLOT_LABELS } from '../formula';
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
  } = useStore();
  const fileRef = useRef<HTMLInputElement>(null);
  const [deleting, setDeleting] = useState(false);

  const dumpPhotos = dump.photos
    .map((id) => photos.find((p) => p.id === id))
    .filter(Boolean) as Photo[];

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (over && active.id !== over.id)
      reorderDumpPhotos(dump.id, active.id as string, over.id as string);
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

  return (
    <div
      onClick={onActivate}
      style={{
        marginBottom: 56, cursor: 'default',
        opacity: deleting ? 0 : 1,
        transform: deleting ? 'translateY(-8px) scale(0.98)' : 'none',
        transition: 'opacity 0.35s ease, transform 0.35s ease',
      }}
    >
      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 10 }}>
        <p style={{
          fontSize: 10, fontWeight: 800, letterSpacing: '0.18em',
          color: 'var(--accent)', textTransform: 'uppercase',
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
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <SmallBtn label="Check Vibe" onClick={(e) => { e.stopPropagation(); checkDumpVibe(dump.id); }} />
          <SmallBtn label="✕ Delete" onClick={(e) => { e.stopPropagation(); handleDelete(); }} danger />
        </div>
      </div>

      <EditableTitle dump={dump} />

      <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 28 }}>
        {dump.photos.length === 0 ? 'No photos yet' : `${dump.photos.length}/20 photos`}
        {dump.photos.length >= 10 && dump.photos.length <= 12 && (
          <span style={{ marginLeft: 8, color: 'var(--accent)', fontSize: 10, fontWeight: 700 }}>★ PEAK ZONE</span>
        )}
      </p>

      {/* Sortable photo row */}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={dump.photos} strategy={horizontalListSortingStrategy}>
          <div className="dump-photos-row" style={{ display: 'flex', gap: 8, overflowX: 'auto', paddingBottom: 24 }}>
            {dumpPhotos.map((photo, idx) => (
              <SortableSlot
                key={photo.id}
                photo={photo}
                index={idx}
                totalInDump={dumpPhotos.length}
                onRemoveFromDump={() => removePhotoFromDump(photo.id, dump.id)}
                onToggleStar={() => toggleStar(photo.id)}
                onToggleHuji={() => toggleHuji(photo.id)}
              />
            ))}

            {/* ── When dump is empty: show two onboarding cards ── */}
            {dump.photos.length === 0 && (
              <>
                {/* From Pool card */}
                <div
                  onClick={(e) => {
                    e.stopPropagation();
                    setAddingToDump(dump.id);
                    document.getElementById('photo-pool')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  }}
                  style={{
                    flexShrink: 0, width: 175, height: 232,
                    borderRadius: 12, border: '1.5px solid var(--border2)',
                    background: 'var(--accent-dim2)',
                    display: 'flex', flexDirection: 'column',
                    alignItems: 'center', justifyContent: 'center', gap: 10,
                    cursor: 'pointer', color: 'var(--accent)', transition: 'all 0.18s',
                    animation: 'slideDown 0.22s ease',
                  }}
                  onMouseEnter={(e) => {
                    (e.currentTarget as HTMLDivElement).style.background = 'var(--accent-dim)';
                    (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--accent)';
                  }}
                  onMouseLeave={(e) => {
                    (e.currentTarget as HTMLDivElement).style.background = 'var(--accent-dim2)';
                    (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border2)';
                  }}
                >
                  {/* Pool icon */}
                  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                    <rect x="3" y="3" width="18" height="18" rx="2"/>
                    <circle cx="8.5" cy="8.5" r="1.5"/>
                    <polyline points="21 15 16 10 5 21"/>
                  </svg>
                  <div style={{ textAlign: 'center', padding: '0 10px' }}>
                    <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.12em', textTransform: 'uppercase', marginBottom: 4 }}>
                      From Pool
                    </p>
                    <p style={{ fontSize: 9, color: 'var(--text3)', lineHeight: 1.5 }}>
                      Pick from your uploaded photos
                    </p>
                  </div>
                </div>

                {/* From Library card */}
                <div
                  onClick={(e) => { e.stopPropagation(); fileRef.current?.click(); }}
                  style={{
                    flexShrink: 0, width: 175, height: 232,
                    borderRadius: 12, border: '1.5px dashed var(--border3)',
                    background: 'var(--bg2)',
                    display: 'flex', flexDirection: 'column',
                    alignItems: 'center', justifyContent: 'center', gap: 10,
                    cursor: 'pointer', color: 'var(--text3)', transition: 'all 0.18s',
                    animation: 'slideDown 0.28s ease',
                  }}
                  onMouseEnter={(e) => {
                    (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--accent)';
                    (e.currentTarget as HTMLDivElement).style.color = 'var(--accent)';
                  }}
                  onMouseLeave={(e) => {
                    (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)';
                    (e.currentTarget as HTMLDivElement).style.color = 'var(--text3)';
                  }}
                >
                  {/* Upload icon */}
                  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                    <polyline points="16 16 12 12 8 16"/>
                    <line x1="12" y1="12" x2="12" y2="21"/>
                    <path d="M20.39 18.39A5 5 0 0018 9h-1.26A8 8 0 103 16.3"/>
                  </svg>
                  <div style={{ textAlign: 'center', padding: '0 10px' }}>
                    <p style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.12em', textTransform: 'uppercase', marginBottom: 4 }}>
                      From Device
                    </p>
                    <p style={{ fontSize: 9, color: 'var(--text3)', lineHeight: 1.5 }}>
                      Upload directly from your device
                    </p>
                  </div>
                </div>
              </>
            )}

            {/* When dump has photos: single compact + slot */}
            {dump.photos.length > 0 && dump.photos.length < 20 && (
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
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--accent)';
                  (e.currentTarget as HTMLDivElement).style.color = 'var(--accent)';
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)';
                  (e.currentTarget as HTMLDivElement).style.color = 'var(--text3)';
                }}
              >
                <span style={{ fontSize: 22, lineHeight: 1 }}>+</span>
                <span style={{ fontSize: 8, letterSpacing: '0.12em', textTransform: 'uppercase', fontWeight: 600 }}>
                  Add Photos
                </span>
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
          </div>
        </SortableContext>
      </DndContext>

      {/* Gold progress bar */}
      <div style={{ height: 2, background: 'var(--border2)', borderRadius: 1, position: 'relative', overflow: 'hidden', marginTop: 4 }}>
        <div style={{
          position: 'absolute', left: 0, top: 0, bottom: 0,
          width: `${fillRatio * 100}%`,
          background: dump.photos.length >= 10 && dump.photos.length <= 12 ? 'var(--accent)' : 'var(--text3)',
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
        fontSize: 36, fontWeight: 700, letterSpacing: '-0.02em',
        lineHeight: 1.1, marginBottom: 10, padding: '0 0 2px',
        cursor: 'text', fontFamily: 'var(--font)',
      }}
    />
  );
}

// ─── Small Button ─────────────────────────────────────────────────────────────

function SmallBtn({ label, onClick, danger }: { label: string; onClick: (e: React.MouseEvent) => void; danger?: boolean }) {
  return (
    <button
      onClick={onClick}
      style={{
        fontSize: 9, fontWeight: 600, letterSpacing: '0.06em',
        padding: '4px 8px', borderRadius: 4,
        background: 'transparent',
        border: `1px solid ${danger ? 'rgba(224,92,92,0.3)' : 'var(--border2)'}`,
        color: danger ? 'var(--red)' : 'var(--text3)',
        cursor: 'pointer', transition: 'all 0.15s',
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLButtonElement).style.color = danger ? 'var(--red)' : 'var(--accent)';
        (e.currentTarget as HTMLButtonElement).style.borderColor = danger ? 'var(--red)' : 'var(--accent)';
      }}
      onMouseLeave={(e) => {
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
  onRemoveFromDump: () => void;
  onToggleStar: () => void;
  onToggleHuji: () => void;
}

function SortableSlot({ photo, index, totalInDump, onRemoveFromDump, onToggleStar, onToggleHuji }: SlotProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: photo.id });
  return (
    <PhotoCard
      photo={photo}
      index={index}
      totalInDump={totalInDump}
      dragRef={setNodeRef}
      dragStyle={{ transform: CSS.Transform.toString(transform), transition, zIndex: isDragging ? 10 : 1 }}
      dragAttributes={attributes as unknown as Record<string, unknown>}
      dragListeners={listeners as unknown as Record<string, unknown>}
      isDragging={isDragging}
      onToggleHuji={onToggleHuji}
      onToggleStar={onToggleStar}
      onRemove={onRemoveFromDump}
    />
  );
}

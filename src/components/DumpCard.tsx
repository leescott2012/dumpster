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
      className="dump-card-enter"
      onClick={onActivate}
      style={{
        marginBottom: 56, cursor: 'default',
        overflow: 'hidden',
        opacity: deleting ? 0 : 1,
        transform: deleting ? 'translateY(-8px) scale(0.98)' : 'none',
        transition: 'opacity 0.4s cubic-bezier(0.16, 1, 0.3, 1), transform 0.4s cubic-bezier(0.16, 1, 0.3, 1)',
      }}
    >
      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 10 }}>
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
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <SmallBtn label="Check Vibe" onClick={(e) => { e.stopPropagation(); checkDumpVibe(dump.id); }} />
          <SmallBtn label="✕ Delete" onClick={(e) => { e.stopPropagation(); handleDelete(); }} danger />
        </div>
      </div>

      <EditableTitle dump={dump} />

      <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 10 }}>
        {dump.photos.length === 0 ? 'No photos yet' : `${dump.photos.length}/20 photos`}
        {dump.photos.length >= 10 && dump.photos.length <= 12 && (
          <span style={{ marginLeft: 8, color: 'var(--gold)', fontSize: 10, fontWeight: 700 }}>★ PEAK ZONE</span>
        )}
      </p>

      {/* Category label description */}
      {dumpPhotos.length > 0 && (() => {
        const unique = [...new Set(dumpPhotos.map(p => p.category.toUpperCase()))];
        const desc = unique.map(cat => CATEGORY_DISPLAY[cat] ?? cat).join(' / ');
        return (
          <p style={{
            fontSize: 11, color: 'var(--text3)', marginBottom: 20,
            letterSpacing: '0.04em', lineHeight: 1.6,
          }}>
            {dump.photos.length}/20 · {desc}
          </p>
        );
      })()}

      {/* Sortable photo row */}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={dump.photos} strategy={horizontalListSortingStrategy}>
          <div className="dump-photos-row" style={{ display: 'flex', gap: 8, overflowX: 'auto', overflowY: 'hidden', paddingBottom: 24 }}>
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
        (e.currentTarget as HTMLButtonElement).style.color = danger ? 'var(--red)' : 'var(--gold)';
        (e.currentTarget as HTMLButtonElement).style.borderColor = danger ? 'var(--red)' : 'var(--gold)';
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

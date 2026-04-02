import { useRef, useCallback, useState, useEffect } from 'react';
import { useStore } from '../store';
import type { Filter } from '../types';
import PhotoCard from './PhotoCard';

const FILTER_OPTIONS: { key: Filter; label: string }[] = [
  { key: 'starred', label: '★ Starred' },
  { key: 'huji', label: '⬤ Huji' },
  { key: 'videos', label: '▶ Videos' },
  { key: 'used', label: '✓ Used' },
];

const POOL_COLS: Record<string, number> = { small: 8, medium: 6, large: 4 };
const POOL_HEIGHTS: Record<string, number> = { small: 120, medium: 160, large: 220 };

export default function PhotoPool() {
  const {
    photos, dumps, filter, activeFilters, activeDumpId, poolSize, poolSearchQuery,
    addPhotos, addPhotoToDump, addPhotosToDump, toggleStar, toggleHuji, removePhoto,
    setFilter, toggleActiveFilter, setPoolSize, setPoolSearch,
    addingToDumpId, setAddingToDump,
  } = useStore();

  const fileRef = useRef<HTMLInputElement>(null);
  const dropRef = useRef<HTMLDivElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const menuRef = useRef<HTMLDivElement>(null);

  const usedIds = new Set(dumps.flatMap((d) => d.photos));
  const colCount = POOL_COLS[poolSize] ?? 6;
  const cardHeight = POOL_HEIGHTS[poolSize] ?? 160;
  const cardWidth = Math.floor(cardHeight * 0.75);

  // Reset selection when leaving add-mode
  useEffect(() => {
    if (!addingToDumpId) setSelectedIds(new Set());
  }, [addingToDumpId]);

  // Close menu on outside click
  useEffect(() => {
    if (!menuOpen) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [menuOpen]);

  const filtered = photos.filter((p) => {
    // Search
    if (poolSearchQuery) {
      const q = poolSearchQuery.toLowerCase();
      const matchLabel = p.labels.some(l => l.toLowerCase().includes(q));
      const matchCat = p.category.toLowerCase().includes(q);
      if (!matchLabel && !matchCat) return false;
    }
    // Active filters (multi-select)
    if (activeFilters.length > 0) {
      return activeFilters.every(f => {
        if (f === 'starred') return p.starred;
        if (f === 'huji') return p.isHuji;
        if (f === 'videos') return /\.(mp4|mov|webm)$/i.test(p.filename);
        if (f === 'used') return usedIds.has(p.id);
        return true;
      });
    }
    // Legacy single filter
    if (filter === 'starred') return p.starred;
    if (filter === 'huji') return p.isHuji;
    return true;
  });

  const poolPhotos = filtered.filter((p) => !usedIds.has(p.id));
  const usedPhotos = filtered.filter((p) => usedIds.has(p.id));
  const allFiltered = [...poolPhotos, ...usedPhotos];

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    if (files.length) addPhotos(files);
    e.target.value = '';
  };

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    dropRef.current?.classList.remove('drag-over');
    const files = Array.from(e.dataTransfer.files).filter(
      (f) => f.type.startsWith('image/') || f.type.startsWith('video/')
    );
    if (files.length) addPhotos(files);
  }, [addPhotos]);

  const handlePhotoClick = (photoId: string) => {
    if (addingToDumpId) {
      // Selection mode
      setSelectedIds(prev => {
        const next = new Set(prev);
        if (next.has(photoId)) next.delete(photoId);
        else next.add(photoId);
        return next;
      });
    } else if (activeDumpId) {
      addPhotoToDump(photoId, activeDumpId);
    }
  };

  const confirmAddToDump = () => {
    if (addingToDumpId && selectedIds.size > 0) {
      addPhotosToDump([...selectedIds], addingToDumpId);
      setSelectedIds(new Set());
    }
  };

  const sizeLabels = { small: 'S', medium: 'M', large: 'L' };

  return (
    <section id="photo-pool">
      {/* Header */}
      <p style={{
        fontSize: 10, fontWeight: 700, letterSpacing: '0.18em',
        color: 'var(--gold)', textTransform: 'uppercase', marginBottom: 10,
      }}>PHOTO POOL</p>

      <h2 style={{ fontSize: 36, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', marginBottom: 6 }}>
        Available Photos
      </h2>
      <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 20 }}>
        {poolPhotos.length} available · {usedIds.size} in dumps
      </p>

      {/* Filter bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 20, flexWrap: 'wrap' }}>

        {/* Hamburger menu */}
        <div ref={menuRef} style={{ position: 'relative' }}>
          <button
            onClick={() => setMenuOpen(o => !o)}
            style={{
              width: 32, height: 32, borderRadius: 6,
              background: menuOpen ? 'var(--gold-dim)' : 'var(--bg2)',
              border: `1px solid ${menuOpen ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
              cursor: 'pointer', display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center', gap: 3,
            }}
          >
            {[0, 1, 2].map(i => (
              <div key={i} style={{ width: 12, height: 1.5, background: menuOpen ? 'var(--gold)' : 'var(--text3)', borderRadius: 1 }} />
            ))}
          </button>

          <div
            className={`pool-filter-drawer ${menuOpen ? 'open' : ''}`}
            style={{
              position: 'absolute', top: 38, left: 0, zIndex: 100,
              background: 'var(--menu-bg)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
              border: '1px solid var(--border2)',
              borderRadius: 10, padding: menuOpen ? 12 : 0, minWidth: 180,
              boxShadow: menuOpen ? '0 8px 32px rgba(0,0,0,0.25)' : 'none',
              maxHeight: menuOpen ? 300 : 0,
              opacity: menuOpen ? 1 : 0,
              overflow: 'hidden',
              transform: menuOpen ? 'translateY(0)' : 'translateY(-8px)',
              transition: 'all 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
              pointerEvents: menuOpen ? 'auto' : 'none',
            }}
          >
            <p style={{ fontSize: 9, color: 'var(--text3)', fontWeight: 700, letterSpacing: '0.12em', marginBottom: 10 }}>FILTERS</p>
            {FILTER_OPTIONS.map(({ key, label }) => (
              <label key={key} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0', cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={activeFilters.includes(key)}
                  onChange={() => toggleActiveFilter(key)}
                  style={{ accentColor: 'var(--gold)' }}
                />
                <span style={{ fontSize: 12, color: 'var(--text2)' }}>{label}</span>
              </label>
            ))}
          </div>
        </div>

        {/* Active filter chips (scrollable) */}
        <div style={{ display: 'flex', gap: 6, overflowX: 'auto', flex: 1 }} className="dump-photos-row">
          <FilterChip label="All" active={activeFilters.length === 0} onClick={() => { setFilter('all'); useStore.getState().activeFilters.length && useStore.setState({ activeFilters: [] }); }} />
          {activeFilters.map(f => (
            <FilterChip
              key={f}
              label={FILTER_OPTIONS.find(o => o.key === f)?.label ?? f}
              active={true}
              onClick={() => toggleActiveFilter(f)}
            />
          ))}
        </div>

        {/* Search button */}
        <div style={{ position: 'relative' }}>
          <button
            onClick={() => { setSearchOpen(o => !o); if (searchOpen) setPoolSearch(''); }}
            style={{
              width: 32, height: 32, borderRadius: '50%',
              background: searchOpen ? 'var(--gold-dim)' : 'var(--bg2)',
              border: `1px solid ${searchOpen ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
              cursor: 'pointer', fontSize: 14,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: searchOpen ? 'var(--gold)' : 'var(--text3)',
              transition: 'all 0.15s',
            }}
          >🔍</button>
          {searchOpen && (
            <input
              autoFocus
              value={poolSearchQuery}
              onChange={e => setPoolSearch(e.target.value)}
              placeholder="Search labels..."
              style={{
                position: 'absolute', top: 0, right: 36,
                background: 'var(--bg2)', border: '1px solid var(--border2)',
                borderRadius: 8, padding: '6px 12px', color: 'var(--text)',
                fontSize: 12, width: 160, fontFamily: 'var(--font)',
                outline: 'none',
              }}
            />
          )}
        </div>

        {/* Size toggle */}
        <div style={{ display: 'flex', gap: 3 }}>
          {(['small', 'medium', 'large'] as const).map(s => (
            <button
              key={s}
              onClick={() => setPoolSize(s)}
              style={{
                width: 26, height: 26, borderRadius: 4, fontSize: 9, fontWeight: 700,
                background: poolSize === s ? 'var(--gold-dim)' : 'var(--bg2)',
                border: `1px solid ${poolSize === s ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                color: poolSize === s ? 'var(--gold)' : 'var(--text3)', cursor: 'pointer',
              }}
            >{sizeLabels[s]}</button>
          ))}
        </div>
      </div>

      {/* Adding-to-dump banner */}
      {addingToDumpId && (
        <div style={{
          background: 'rgba(76,175,80,0.1)', border: '1px solid rgba(76,175,80,0.3)',
          borderRadius: 10, padding: '12px 16px', marginBottom: 16,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <p style={{ fontSize: 13, color: '#4CAF50', fontWeight: 600 }}>
            Tap photos to select · {selectedIds.size} selected
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={confirmAddToDump}
              disabled={selectedIds.size === 0}
              style={{
                padding: '7px 16px', borderRadius: 6, fontSize: 11, fontWeight: 700,
                background: selectedIds.size > 0 ? '#4CAF50' : 'transparent',
                color: selectedIds.size > 0 ? '#fff' : '#4CAF50',
                border: '1px solid #4CAF50', cursor: selectedIds.size > 0 ? 'pointer' : 'default',
              }}
            >Add {selectedIds.size > 0 ? selectedIds.size : ''} Photos</button>
            <button
              onClick={() => setAddingToDump(null)}
              style={{
                padding: '7px 12px', borderRadius: 6, fontSize: 11,
                background: 'transparent', border: '1px solid var(--border2)',
                color: 'var(--text3)', cursor: 'pointer',
              }}
            >Cancel</button>
          </div>
        </div>
      )}

      {/* Drop zone */}
      <div
        ref={dropRef}
        onDrop={handleDrop}
        onDragOver={(e) => { e.preventDefault(); dropRef.current?.classList.add('drag-over'); }}
        onDragLeave={() => dropRef.current?.classList.remove('drag-over')}
        style={{ transition: 'background 0.2s', borderRadius: 12 }}
      >
        {/* Empty state */}
        {photos.length === 0 && (
          <div
            onClick={() => fileRef.current?.click()}
            style={{
              border: '1.5px dashed var(--border3)', borderRadius: 12,
              padding: '40px 24px', textAlign: 'center', cursor: 'pointer',
              marginBottom: 16, transition: 'all 0.2s',
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)';
              (e.currentTarget as HTMLDivElement).style.background = 'var(--gold-dim2)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)';
              (e.currentTarget as HTMLDivElement).style.background = 'transparent';
            }}
          >
            <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 4 }}>
              Drop photos & videos here or <span style={{ color: 'var(--gold)' }}>click to upload</span>
            </p>
            <p style={{ fontSize: 11, color: 'var(--text3)' }}>Supports JPG, PNG, GIF, MOV, MP4</p>
          </div>
        )}

        {/* Photo grid */}
        {allFiltered.length > 0 && (
          <div style={{
            display: 'grid',
            gridTemplateColumns: `repeat(${colCount}, 1fr)`,
            gap: 8, marginBottom: 16,
          }}>
            {allFiltered.map((photo, idx) => {
              const used = usedIds.has(photo.id);
              const isSelected = selectedIds.has(photo.id);
              return (
                <PhotoCard
                  key={photo.id}
                  photo={photo}
                  index={idx}
                  used={used && !addingToDumpId}
                  selected={isSelected}
                  width={cardWidth}
                  height={cardHeight}
                  onClick={used && !addingToDumpId ? undefined : () => handlePhotoClick(photo.id)}
                  onToggleStar={() => toggleStar(photo.id)}
                  onToggleHuji={() => toggleHuji(photo.id)}
                  onRemove={() => removePhoto(photo.id)}
                />
              );
            })}

            {/* Upload tile */}
            <div
              onClick={() => fileRef.current?.click()}
              style={{
                width: cardWidth, height: cardHeight, borderRadius: 10,
                border: '1.5px dashed var(--border3)', background: 'var(--bg2)',
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                justifyContent: 'center', gap: 6, cursor: 'pointer',
                color: 'var(--text3)', transition: 'all 0.15s',
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)';
                (e.currentTarget as HTMLDivElement).style.color = 'var(--gold)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)';
                (e.currentTarget as HTMLDivElement).style.color = 'var(--text3)';
              }}
            >
              <span style={{ fontSize: 20 }}>+</span>
              <span style={{ fontSize: 8, letterSpacing: '0.12em', textTransform: 'uppercase', fontWeight: 600 }}>
                Add
              </span>
            </div>
          </div>
        )}
      </div>

      <input ref={fileRef} type="file" multiple accept="image/*,video/*"
        style={{ display: 'none' }} onChange={handleFileChange} />
    </section>
  );
}

function FilterChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        flexShrink: 0, padding: '6px 14px', borderRadius: 999, fontSize: 11, fontWeight: 500,
        letterSpacing: '0.06em', whiteSpace: 'nowrap',
        border: active ? '1px solid rgba(200,169,110,0.4)' : '1px solid var(--border2)',
        background: active ? 'var(--gold-dim)' : 'transparent',
        color: active ? 'var(--gold)' : 'var(--text3)',
        cursor: 'pointer', transition: 'all 0.15s',
      }}
    >{label}</button>
  );
}

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

const POOL_COLS: Record<string, number> = { small: 6, medium: 4, large: 2 };

function FilterChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        padding: '6px 14px',
        borderRadius: 20,
        fontSize: 12,
        fontWeight: 600,
        background: active ? 'var(--gold)' : 'var(--bg2)',
        border: `1px solid ${active ? 'var(--gold)' : 'var(--border2)'}`,
        color: active ? '#000' : 'var(--text3)',
        cursor: 'pointer',
        transition: 'all 0.15s',
        whiteSpace: 'nowrap',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        height: 32,
      }}
    >
      {label}
    </button>
  );
}

export default function PhotoPool() {
  const {
    photos, dumps, filter, activeFilters, poolSize, poolSearchQuery,
    addPhotos, addPhotosToDump, toggleStar, toggleHuji, removePhoto,
    setFilter, toggleActiveFilter, setPoolSize, setPoolSearch,
    addingToDumpId, setAddingToDump, rescanPhoto,
  } = useStore();

  // Suppress unused variable warnings for build
  void toggleStar; void toggleHuji; void removePhoto;
  const [scanning, setScanning] = useState(false);
  const [scanProgress, setScanProgress] = useState({ done: 0, total: 0 });

  const fileRef = useRef<HTMLInputElement>(null);
  const dropRef = useRef<HTMLDivElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const menuRef = useRef<HTMLDivElement>(null);

  const usedIds = new Set(dumps.flatMap((d) => d.photos));
  const colCount = POOL_COLS[poolSize] ?? 2;


  // Reset selection when leaving add-mode
  useEffect(() => {
    if (!addingToDumpId) setSelectedIds(new Set());
  }, [addingToDumpId]);

  // Close menu on outside tap/click (pointerdown fires on both mouse and touch)
  useEffect(() => {
    if (!menuOpen) return;
    const handler = (e: PointerEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener('pointerdown', handler);
    return () => document.removeEventListener('pointerdown', handler);
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
      // Selection mode only — no auto-add on tap
      setSelectedIds(prev => {
        const next = new Set(prev);
        if (next.has(photoId)) next.delete(photoId);
        else next.add(photoId);
        return next;
      });
    }
    // Do nothing on normal tap — user must use Add Photos flow
  };

  const confirmAddToDump = () => {
    if (addingToDumpId && selectedIds.size > 0) {
      addPhotosToDump([...selectedIds], addingToDumpId);
      setSelectedIds(new Set());
    }
  };

  const handleRescanAll = async () => {
    const toScan = photos.filter(p => !/\.(mp4|mov|webm)$/i.test(p.filename));
    if (toScan.length === 0) return;
    setScanning(true);
    setScanProgress({ done: 0, total: toScan.length });
    for (let i = 0; i < toScan.length; i++) {
      await rescanPhoto(toScan[i].id);
      setScanProgress({ done: i + 1, total: toScan.length });
    }
    setScanning(false);
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
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
        <p style={{ fontSize: 13, color: 'var(--text3)' }}>
          {poolPhotos.length} available · {usedIds.size} in dumps
        </p>
        <button
          onClick={handleRescanAll}
          disabled={scanning}
          style={{
            fontSize: 11, fontWeight: 700, letterSpacing: '0.08em',
            padding: '7px 16px', borderRadius: 20,
            background: scanning ? 'var(--gold-dim)' : 'var(--bg2)',
            border: `1px solid ${scanning ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
            color: scanning ? 'var(--gold)' : 'var(--text)',
            cursor: scanning ? 'default' : 'pointer',
            transition: 'all 0.15s', whiteSpace: 'nowrap',
            display: 'flex', alignItems: 'center', gap: 6
          }}
        >
          {scanning && <span className="spinner" style={{ width: 12, height: 12, border: '2px solid currentColor', borderTopColor: 'transparent', borderRadius: '50%', display: 'inline-block', animation: 'spin 1s linear infinite' }} />}
          {scanning ? `SCANNING ${scanProgress.done}/${scanProgress.total}` : 'SCAN PHOTOS'}
        </button>
      </div>

      {/* Filter bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 20 }}>
        
        {/* Left Actions: Hamburger + Chips */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, overflow: 'hidden' }}>
          {/* Hamburger menu */}
          <div ref={menuRef} style={{ position: 'relative', flexShrink: 0 }}>
            <button
              onClick={() => setMenuOpen(o => !o)}
              style={{
                width: 32, height: 32, borderRadius: 20,
                background: menuOpen ? 'var(--gold-dim)' : 'var(--bg2)',
                border: `1px solid ${menuOpen ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                cursor: 'pointer', display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center', gap: 3,
                transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                transform: menuOpen ? 'rotate(90deg)' : 'rotate(0deg)',
              }}
            >
              {[0, 1, 2].map(i => (
                <div key={i} style={{
                  width: 12, height: 1.5, borderRadius: 1,
                  background: menuOpen ? 'var(--gold)' : 'var(--text3)',
                  transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                }} />
              ))}
            </button>

            <div
              style={{
                position: 'absolute', top: 38, left: 0, zIndex: 100,
                background: 'var(--menu-bg)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
                border: '1px solid var(--border2)',
                borderRadius: 12, padding: '8px',
                boxShadow: menuOpen ? '0 8px 32px rgba(0,0,0,0.25)' : 'none',
                opacity: menuOpen ? 1 : 0,
                transform: menuOpen ? 'translateY(0) scale(1)' : 'translateY(-8px) scale(0.96)',
                transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                pointerEvents: menuOpen ? 'auto' : 'none',
                display: 'flex', flexDirection: 'column', gap: 4,
                minWidth: 140
              }}
            >
              {FILTER_OPTIONS.map(({ key, label }) => (
                <button
                  key={key}
                  onClick={() => { toggleActiveFilter(key); setMenuOpen(false); }}
                  style={{
                    padding: '8px 12px', borderRadius: 8,
                    fontSize: 12, fontWeight: 600, textAlign: 'left',
                    background: activeFilters.includes(key) ? 'var(--gold-dim)' : 'transparent',
                    border: 'none',
                    color: activeFilters.includes(key) ? 'var(--gold)' : 'var(--text)',
                    cursor: 'pointer', transition: 'all 0.15s',
                  }}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>

          {/* Active filter chips (scrollable) */}
          <div style={{ display: 'flex', gap: 6, overflowX: 'auto', paddingRight: 10, scrollbarWidth: 'none' }} className="no-scrollbar">
            <FilterChip label="All" active={activeFilters.length === 0} onClick={() => { setFilter('all'); useStore.setState({ activeFilters: [] }); }} />
            {activeFilters.map(f => (
              <FilterChip
                key={f}
                label={FILTER_OPTIONS.find(o => o.key === f)?.label ?? f}
                active={true}
                onClick={() => toggleActiveFilter(f)}
              />
            ))}
          </div>
        </div>

        {/* Right Actions: Search + Size */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
          {/* Search button */}
          <div style={{ position: 'relative' }}>
            <button
              onClick={() => { setSearchOpen(o => !o); if (searchOpen) setPoolSearch(''); }}
              style={{
                width: 32, height: 32, borderRadius: 20,
                background: searchOpen ? 'var(--gold-dim)' : 'var(--bg2)',
                border: `1px solid ${searchOpen ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
                cursor: 'pointer', fontSize: 14,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: searchOpen ? 'var(--gold)' : 'var(--text3)',
                transition: 'all 0.15s',
              }}
            ><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="22" y2="22"/></svg></button>
            {searchOpen && (
              <input
                autoFocus
                value={poolSearchQuery}
                onChange={e => setPoolSearch(e.target.value)}
                placeholder="Search..."
                className="menu-dropdown"
                style={{
                  position: 'absolute', top: 38, right: 0, zIndex: 101,
                  background: 'var(--menu-bg)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
                  border: '1px solid var(--border2)',
                  borderRadius: 12, padding: '8px 12px', color: 'var(--text)',
                  fontSize: 12, width: 180, fontFamily: 'var(--font)',
                  outline: 'none', boxShadow: '0 8px 32px rgba(0,0,0,0.25)'
                }}
              />
            )}
          </div>

          {/* Size toggle */}
          <div style={{ display: 'flex', gap: 4, background: 'var(--bg2)', padding: 3, borderRadius: 20, border: '1px solid var(--border2)' }}>
            {(['small', 'medium', 'large'] as const).map(s => (
              <button
                key={s}
                onClick={() => setPoolSize(s)}
                style={{
                  width: 26, height: 26, borderRadius: 20, fontSize: 10, fontWeight: 700,
                  background: poolSize === s ? 'var(--gold)' : 'transparent',
                  border: 'none',
                  color: poolSize === s ? '#000' : 'var(--text3)', cursor: 'pointer',
                  transition: 'all 0.15s'
                }}
              >{sizeLabels[s]}</button>
            ))}
          </div>
        </div>
      </div>

      {/* Adding-to-dump banner */}
      {addingToDumpId && (
        <div className="menu-dropdown" style={{
          background: 'rgba(76,175,80,0.1)', border: '1px solid rgba(76,175,80,0.3)',
          borderRadius: 12, padding: '12px 16px', marginBottom: 16,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <p style={{ fontSize: 13, color: '#4CAF50', fontWeight: 600 }}>
            {selectedIds.size} selected
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={confirmAddToDump}
              disabled={selectedIds.size === 0}
              style={{
                padding: '7px 16px', borderRadius: 20, fontSize: 11, fontWeight: 700,
                background: selectedIds.size > 0 ? '#4CAF50' : 'transparent',
                color: selectedIds.size > 0 ? '#fff' : '#4CAF50',
                border: '1px solid #4CAF50', cursor: selectedIds.size > 0 ? 'pointer' : 'default',
              }}
            >Add Photos</button>
            <button
              onClick={() => setAddingToDump(null)}
              style={{
                padding: '7px 12px', borderRadius: 20, fontSize: 11,
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
              padding: '60px 24px', textAlign: 'center', cursor: 'pointer',
              marginBottom: 16, transition: 'all 0.2s',
              background: 'var(--bg1)'
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--gold)';
              (e.currentTarget as HTMLDivElement).style.background = 'var(--gold-dim2)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border3)';
              (e.currentTarget as HTMLDivElement).style.background = 'var(--bg1)';
            }}
          >
            <div style={{ fontSize: 32, marginBottom: 16 }}>📸</div>
            <p style={{ fontSize: 15, color: 'var(--text)', fontWeight: 600, marginBottom: 4 }}>
              Your pool is empty
            </p>
            <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 20 }}>
              Drop photos here or <span style={{ color: 'var(--gold)' }}>click to upload</span>
            </p>
            <input
              type="file"
              ref={fileRef}
              multiple
              accept="image/*,video/*"
              onChange={handleFileChange}
              style={{ display: 'none' }}
            />
          </div>
        )}

        {/* Photo grid */}
        {(activeFilters.includes('used') ? usedPhotos : poolPhotos).length > 0 && (
          <div style={{
            display: 'grid',
            gridTemplateColumns: `repeat(${colCount}, 1fr)`,
            gap: 8, marginBottom: 16,
          }}>
            {(activeFilters.includes('used') ? usedPhotos : poolPhotos).map((photo, idx) => (
              <PhotoCard
                key={photo.id}
                photo={photo}
                index={idx}
                selected={selectedIds.has(photo.id)}
                onClick={() => handlePhotoClick(photo.id)}
                onToggleHuji={() => toggleHuji(photo.id)}
                onToggleStar={() => toggleStar(photo.id)}
                onRemove={() => removePhoto(photo.id)}
                poolSize={poolSize}
              />
            ))}
          </div>
        )}
      </div>

      <style>{`
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
        .no-scrollbar::-webkit-scrollbar {
          display: none;
        }
        .no-scrollbar {
          -ms-overflow-style: none;
          scrollbar-width: none;
        }
      `}</style>
    </section>
  );
}

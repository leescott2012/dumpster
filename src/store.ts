import { create } from 'zustand';
import type { Photo, Dump, Filter, Caption, ColorMode, PoolSize } from './types';
import { checkColorTemp, arrangePhotos, generateDumpTitle } from './formula';

// ─── helpers ────────────────────────────────────────────────────────────────

function guessCategory(filename: string): string {
  const f = filename.toLowerCase();
  if (f.includes('portrait') || f.includes('selfie') || f.includes('face')) return 'PORTRAIT';
  if (f.includes('car') || f.includes('auto') || f.includes('bmw') || f.includes('porsch') || f.includes('lambo') || f.includes('gwagon')) return 'AUTOMOTIVE';
  if (f.includes('studio') || f.includes('ssl') || f.includes('mix')) return 'STUDIO';
  if (f.includes('night') || f.includes('club') || f.includes('bar')) return 'NIGHTLIFE';
  if (f.includes('gym') || f.includes('fit')) return 'FITNESS';
  if (f.includes('art') || f.includes('museum') || f.includes('gallery')) return 'ART';
  if (f.includes('arch') || f.includes('hotel') || f.includes('build')) return 'ARCHITECTURE';
  if (f.includes('travel') || f.includes('beach') || f.includes('miami')) return 'TRAVEL';
  if (f.includes('fashion') || f.includes('gucci') || f.includes('balenc') || f.includes('outfit')) return 'FASHION';
  if (f.includes('watch') || f.includes('rm') || f.includes('patek') || f.includes('rolex')) return 'WATCH';
  return 'LIFESTYLE';
}

function detectHuji(filename: string): boolean {
  const f = filename.toLowerCase();
  return f.includes('huji') || f.includes('dexp') || f.includes('film') || f.includes('grain');
}

// ─── localStorage persistence ───────────────────────────────────────────────

const STORAGE_KEY = 'dumpster_state_v4';

// Clear old storage keys so Safari reloads fresh cloud photos
['dumpster_state_v3', 'dumpster_state_v2', 'dumpster_state_v1'].forEach(k => {
  try { localStorage.removeItem(k); } catch {}
});

function loadPersistedState(): Partial<PersistedState> | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch { return null; }
}

function saveState(state: PersistedState) {
  try {
    // Only persist server photos (blob: URLs are session-only)
    const photos = state.photos.filter(p => !p.url.startsWith('blob:'));
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...state, photos }));
  } catch { /* quota exceeded */ }
}

const DEFAULT_RULES = [
  'Peak dump: 10–12 slides',
  'Never same category back-to-back',
  'Hook shot opens, anchor shot closes',
  'Balance light & dark tones',
  'Max 2 portraits in a row',
];

interface PersistedState {
  photos: Photo[];
  dumps: Dump[];
  activeDumpId: string | null;
  captions: Caption[];
  colorMode: ColorMode;
  poolSize: PoolSize;
  filter: Filter;
  activeFilters: Filter[];
  customRules: string[];
}

// ─── undo/redo ───────────────────────────────────────────────────────────────

interface Snapshot { photos: Photo[]; dumps: Dump[] }
const undoStack: Snapshot[] = [];
const redoStack: Snapshot[] = [];
function pushUndo(photos: Photo[], dumps: Dump[]) {
  undoStack.push({ photos: [...photos], dumps: [...dumps] });
  redoStack.length = 0;
  while (undoStack.length > 200) undoStack.shift();
}

// ─── presets ─────────────────────────────────────────────────────────────────

let dumpCounter = 1;

const PRESET_DUMPS: Array<{ title: string; photoFilenames: string[]; categories: string[] }> = [
  {
    title: 'Luxury Flex: Cars & Vibes',
    photoFilenames: ['IMG_0077.jpeg', 'IMG_0068.jpeg', 'IMG_0075.jpeg', 'IMG_9263.jpeg'],
    categories: ['ARCHITECTURE', 'AUTOMOTIVE', 'AUTOMOTIVE', 'AUTOMOTIVE'],
  },
  {
    title: 'Casino Night: High Stakes',
    photoFilenames: ['IMG_9954.jpeg', 'IMG_9955.jpeg'],
    categories: ['NIGHTLIFE', 'NIGHTLIFE'],
  },
  {
    title: 'Studio Session: Creative Space',
    photoFilenames: ['000596820011.jpg', '000596820017.jpeg', '194DA2FC-256C-4A7D-B667-B10671837E80.JPG', '74D86430-959F-4378-BF0C-0D0818DEC946.jpg'],
    categories: ['STUDIO', 'STUDIO', 'STUDIO', 'STUDIO'],
  },
  {
    title: 'Wine Tasting: Epicurean Night',
    photoFilenames: ['IMG_0307.jpeg', 'IMG_0309.jpeg', 'IMG_0316.jpeg'],
    categories: ['DINING', 'DINING', 'DINING'],
  },
  {
    title: 'LED Mystery: Moody Nightlife',
    photoFilenames: ['IMG_9301.jpeg', 'IMG_9541.jpeg', 'IMG_9324.jpeg'],
    categories: ['NIGHTLIFE', 'NIGHTLIFE', 'NIGHTLIFE'],
  },
];

// ─── store interface ─────────────────────────────────────────────────────────

interface Store {
  photos: Photo[];
  dumps: Dump[];
  activeDumpId: string | null;
  filter: Filter;
  activeFilters: Filter[];
  captions: Caption[];
  colorMode: ColorMode;
  poolSize: PoolSize;
  poolSearchQuery: string;
  lightboxPhotoId: string | null;
  addingToDumpId: string | null; // pool selection mode
  customRules: string[];

  // photos
  addPhotos: (files: File[]) => void;
  removePhoto: (photoId: string) => void;
  toggleStar: (photoId: string) => void;
  toggleHuji: (photoId: string) => void;
  setCategory: (photoId: string, category: string) => void;
  addLabel: (photoId: string, label: string) => void;
  removeLabel: (photoId: string, label: string) => void;
  cropPhoto: (photoId: string, croppedBlob: Blob) => void;
  rescanPhoto: (photoId: string) => Promise<void>;

  // dumps
  addPhotoToDump: (photoId: string, dumpId: string) => void;
  addPhotosToDump: (photoIds: string[], dumpId: string) => void;
  removePhotoFromDump: (photoId: string, dumpId: string) => void;
  reorderDumpPhotos: (dumpId: string, activeId: string, overId: string) => void;
  setActiveDump: (id: string | null) => void;
  newDump: () => void;
  autoGenerateDump: (count: number) => void;
  deleteDump: (id: string) => void;
  updateDumpTitle: (dumpId: string, title: string) => void;
  checkDumpVibe: (dumpId: string) => void;
  toggleDumpLike: (dumpId: string) => void;
  approveDumpTitle: (dumpId: string) => void;
  rejectDumpTitle: (dumpId: string) => void;
  resetAll: () => void;

  // captions
  addCaption: (caption: Omit<Caption, 'id' | 'createdAt'>) => void;
  rateCaption: (captionId: string, rating: number) => void;
  favoriteCaption: (captionId: string) => void;
  removeCaption: (captionId: string) => void;
  banCaption: (captionId: string) => void;

  // rules
  addRule: (rule: string) => void;
  removeRule: (index: number) => void;
  updateRule: (index: number, rule: string) => void;

  // ui
  setFilter: (f: Filter) => void;
  toggleActiveFilter: (f: Filter) => void;
  setColorMode: (m: ColorMode) => void;
  setPoolSize: (s: PoolSize) => void;
  setPoolSearch: (q: string) => void;
  setLightbox: (photoId: string | null) => void;
  setAddingToDump: (dumpId: string | null) => void;

  // undo/redo
  undo: () => void;
  redo: () => void;
  canUndo: () => boolean;
  canRedo: () => boolean;
}

// ─── AI photo scan ───────────────────────────────────────────────────────────

async function fetchAiLabels(url: string): Promise<{ category: string; labels: string[] } | null> {
  try {
    const res = await fetch(url);
    const blob = await res.blob();
    const bmp = await createImageBitmap(blob, { resizeWidth: 512, resizeQuality: 'medium' });
    const canvas = document.createElement('canvas');
    canvas.width = bmp.width;
    canvas.height = bmp.height;
    canvas.getContext('2d')!.drawImage(bmp, 0, 0);
    const base64 = canvas.toDataURL('image/jpeg', 0.7).split(',')[1];
    const apiRes = await fetch('/api/analyze-photo', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ imageBase64: base64, mimeType: 'image/jpeg' }),
    });
    if (!apiRes.ok) return null;
    return await apiRes.json() as { category: string; labels: string[] };
  } catch { return null; }
}

// ─── store ───────────────────────────────────────────────────────────────────

const persisted = loadPersistedState();

export const useStore = create<Store>((set, get) => {
  const persist = () => {
    const s = get();
    saveState({
      photos: s.photos,
      dumps: s.dumps,
      activeDumpId: s.activeDumpId,
      captions: s.captions,
      colorMode: s.colorMode,
      poolSize: s.poolSize,
      filter: s.filter,
      activeFilters: s.activeFilters,
      customRules: s.customRules,
    });
  };

  const snap = () => {
    const s = get();
    pushUndo(s.photos, s.dumps);
  };

  return {
    photos: persisted?.photos ?? [],
    dumps: persisted?.dumps ?? [{ id: 'd1', num: 1, title: 'Untitled Dump', photos: [], vibeBadge: null }],
    activeDumpId: persisted?.activeDumpId ?? 'd1',
    filter: persisted?.filter ?? 'all',
    activeFilters: persisted?.activeFilters ?? [],
    captions: persisted?.captions ?? [],
    colorMode: persisted?.colorMode ?? 'dark',
    poolSize: persisted?.poolSize ?? 'large',
    customRules: persisted?.customRules ?? DEFAULT_RULES,
    poolSearchQuery: '',
    lightboxPhotoId: null,
    addingToDumpId: null,

    // ── photos ──────────────────────────────────────────────────────────────

    addPhotos: (files) => {
      snap();
      const newPhotos: Photo[] = files.map((file) => ({
        id: `p-${Date.now()}-${Math.random().toString(36).slice(2)}`,
        url: URL.createObjectURL(file),
        filename: file.name,
        category: guessCategory(file.name),
        labels: [],
        starred: false,
        isHuji: detectHuji(file.name),
      }));
      set((s) => ({ photos: [...s.photos, ...newPhotos] }));
      persist();

      // AI label: fire-and-forget for each image (skip videos)
      newPhotos.forEach(async (photo) => {
        if (/\.(mp4|mov|webm)$/i.test(photo.filename)) return;
        const result = await fetchAiLabels(photo.url);
        if (!result) return;
        set((s) => ({ photos: s.photos.map((p) => p.id === photo.id ? { ...p, ...result } : p) }));
        persist();
      });
    },

    rescanPhoto: async (photoId) => {
      const photo = get().photos.find(p => p.id === photoId);
      if (!photo || /\.(mp4|mov|webm)$/i.test(photo.filename)) return;
      const result = await fetchAiLabels(photo.url);
      if (!result) return;
      set((s) => ({ photos: s.photos.map((p) => p.id === photoId ? { ...p, ...result } : p) }));
      persist();
    },

    removePhoto: (photoId) => {
      snap();
      const photo = get().photos.find((p) => p.id === photoId);
      if (photo?.url.startsWith('blob:')) URL.revokeObjectURL(photo.url);
      set((s) => ({
        photos: s.photos.filter((p) => p.id !== photoId),
        dumps: s.dumps.map((d) => ({ ...d, photos: d.photos.filter((id) => id !== photoId) })),
      }));
      persist();
    },

    toggleStar: (photoId) => {
      set((s) => ({ photos: s.photos.map((p) => p.id === photoId ? { ...p, starred: !p.starred } : p) }));
      persist();
    },

    toggleHuji: (photoId) => {
      set((s) => ({ photos: s.photos.map((p) => p.id === photoId ? { ...p, isHuji: !p.isHuji } : p) }));
      persist();
    },

    setCategory: (photoId, category) => {
      snap();
      set((s) => ({ photos: s.photos.map((p) => p.id === photoId ? { ...p, category } : p) }));
      persist();
    },

    addLabel: (photoId, label) => {
      set((s) => ({
        photos: s.photos.map((p) =>
          p.id === photoId && !p.labels.includes(label)
            ? { ...p, labels: [...p.labels, label] } : p
        ),
      }));
      persist();
    },

    removeLabel: (photoId, label) => {
      set((s) => ({
        photos: s.photos.map((p) =>
          p.id === photoId ? { ...p, labels: p.labels.filter((l) => l !== label) } : p
        ),
      }));
      persist();
    },

    cropPhoto: (photoId, croppedBlob) => {
      snap();
      const blobUrl = URL.createObjectURL(croppedBlob);
      set((s) => ({
        photos: s.photos.map((p) =>
          p.id === photoId ? { ...p, url: blobUrl } : p
        ),
      }));
      persist();
    },

    // ── dumps ────────────────────────────────────────────────────────────────

    addPhotoToDump: (photoId, dumpId) => {
      snap();
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId && d.photos.length < 20 && !d.photos.includes(photoId)
            ? { ...d, photos: [...d.photos, photoId] } : d
        ),
      }));
      persist();
    },

    addPhotosToDump: (photoIds, dumpId) => {
      snap();
      set((s) => ({
        dumps: s.dumps.map((d) => {
          if (d.id !== dumpId) return d;
          const toAdd = photoIds.filter(id => !d.photos.includes(id));
          const available = 20 - d.photos.length;
          return { ...d, photos: [...d.photos, ...toAdd.slice(0, available)] };
        }),
        addingToDumpId: null,
      }));
      persist();
    },

    removePhotoFromDump: (photoId, dumpId) => {
      snap();
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId ? { ...d, photos: d.photos.filter((id) => id !== photoId) } : d
        ),
      }));
      persist();
    },

    reorderDumpPhotos: (dumpId, activeId, overId) => {
      snap();
      set((s) => ({
        dumps: s.dumps.map((d) => {
          if (d.id !== dumpId) return d;
          const photos = [...d.photos];
          const from = photos.indexOf(activeId);
          const to = photos.indexOf(overId);
          if (from === -1 || to === -1) return d;
          photos.splice(from, 1);
          photos.splice(to, 0, activeId);
          return { ...d, photos };
        }),
      }));
      persist();
    },

    setActiveDump: (id) => set({ activeDumpId: id }),

    newDump: () => {
      snap();
      const num = ++dumpCounter;
      const id = `d-${Date.now()}`;
      set((s) => ({
        dumps: [...s.dumps, { id, num, title: `Dump ${String(num).padStart(2, '0')}`, photos: [], vibeBadge: null }],
        activeDumpId: id,
      }));
      persist();
    },

    autoGenerateDump: (count) => {
      snap();
      const state = useStore.getState();
      const usedIds = new Set(state.dumps.flatMap((d) => d.photos));
      const pool = state.photos.filter((p) => !usedIds.has(p.id));
      if (pool.length === 0) return;
      const clamped = Math.min(count, pool.length, 20);
      const arranged = arrangePhotos(pool).slice(0, clamped);
      const title = generateDumpTitle(arranged);
      const num = ++dumpCounter;
      const id = `d-${Date.now()}`;
      set((s) => ({
        dumps: [...s.dumps, {
          id, num,
          title,
          photos: arranged.map((p) => p.id),
          vibeBadge: null,
        }],
        activeDumpId: id,
      }));
      persist();
    },

    deleteDump: (id) => {
      snap();
      set((s) => {
        const dumps = s.dumps.filter((d) => d.id !== id);
        return {
          dumps,
          activeDumpId: s.activeDumpId === id ? (dumps[0]?.id ?? null) : s.activeDumpId,
        };
      });
      persist();
    },

    updateDumpTitle: (dumpId, title) => {
      set((s) => ({ dumps: s.dumps.map((d) => d.id === dumpId ? { ...d, title } : d) }));
      persist();
    },

    checkDumpVibe: (dumpId) => {
      const { photos, dumps } = get();
      const dump = dumps.find(d => d.id === dumpId);
      if (!dump) return;
      const dumpPhotos = dump.photos.map(id => photos.find(p => p.id === id)).filter(Boolean) as Photo[];
      const consistent = checkColorTemp(dumpPhotos);
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId ? { ...d, vibeBadge: consistent ? null : 'mismatch' } : d
        ),
      }));
    },

    toggleDumpLike: (dumpId) => {
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId ? { ...d, liked: !d.liked } : d
        ),
      }));
      persist();
    },

    approveDumpTitle: (dumpId) => {
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId ? { ...d, titleApproved: true } : d
        ),
      }));
      persist();
    },

    rejectDumpTitle: (dumpId) => {
      // Regenerate title using AI, then mark as not approved
      const { dumps, photos } = get();
      const dump = dumps.find(d => d.id === dumpId);
      if (!dump) return;
      set((s) => ({
        dumps: s.dumps.map((d) =>
          d.id === dumpId ? { ...d, titleApproved: false } : d
        ),
      }));
      // Fire AI title regeneration
      const dumpPhotos = dump.photos.map(id => photos.find(p => p.id === id)).filter(Boolean) as Photo[];
      const existingTitles = dumps.map(d => d.title);
      fetch('/api/generate-dump-title', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          photos: dumpPhotos.map(p => ({ category: p.category, labels: p.labels })),
          existingTitles,
        }),
      }).then(r => r.json()).then(({ title: newTitle }) => {
        if (newTitle) {
          set((s) => ({
            dumps: s.dumps.map((d) =>
              d.id === dumpId ? { ...d, title: newTitle, titleApproved: undefined } : d
            ),
          }));
          persist();
        }
      }).catch(() => {});
    },

    addRule: (rule) => {
      set((s) => ({ customRules: [...s.customRules, rule] }));
      persist();
    },

    removeRule: (index) => {
      set((s) => ({ customRules: s.customRules.filter((_, i) => i !== index) }));
      persist();
    },

    updateRule: (index, rule) => {
      set((s) => ({
        customRules: s.customRules.map((r, i) => i === index ? rule : r),
      }));
      persist();
    },

    resetAll: () => {
      snap();
      get().photos.forEach((p) => { if (p.url.startsWith('blob:')) URL.revokeObjectURL(p.url); });
      dumpCounter = 1;
      const initial = {
        photos: [] as Photo[],
        dumps: [{ id: 'd1', num: 1, title: 'Untitled Dump', photos: [], vibeBadge: null as null }],
        activeDumpId: 'd1',
        filter: 'all' as Filter,
        activeFilters: [] as Filter[],
        captions: [] as Caption[],
      };
      set(initial);
      localStorage.removeItem(STORAGE_KEY);
      loadPhotosFromServer();
    },

    // ── captions ─────────────────────────────────────────────────────────────

    addCaption: (caption) => {
      const c: Caption = {
        ...caption,
        id: `cap-${Date.now()}-${Math.random().toString(36).slice(2)}`,
        createdAt: Date.now(),
      };
      set((s) => ({ captions: [...s.captions, c] }));
      persist();
    },

    rateCaption: (captionId, rating) => {
      set((s) => ({
        captions: s.captions.map((c) => c.id === captionId ? { ...c, rating } : c),
      }));
      persist();
    },

    favoriteCaption: (captionId) => {
      set((s) => ({
        captions: s.captions.map((c) => c.id === captionId ? { ...c, favorited: !c.favorited } : c),
      }));
      persist();
    },

    removeCaption: (captionId) => {
      set((s) => ({ captions: s.captions.filter((c) => c.id !== captionId) }));
      persist();
    },

    banCaption: (captionId) => {
      set((s) => ({
        captions: s.captions.map((c) => c.id === captionId ? { ...c, banned: true, favorited: false } : c),
      }));
      persist();
    },

    // ── ui ───────────────────────────────────────────────────────────────────

    setFilter: (filter) => { set({ filter }); persist(); },

    toggleActiveFilter: (f) => {
      set((s) => {
        const has = s.activeFilters.includes(f);
        return { activeFilters: has ? s.activeFilters.filter(x => x !== f) : [...s.activeFilters, f] };
      });
    },

    setColorMode: (colorMode) => { set({ colorMode }); persist(); applyColorMode(colorMode); },
    setPoolSize: (poolSize) => { set({ poolSize }); persist(); },
    setPoolSearch: (poolSearchQuery) => set({ poolSearchQuery }),
    setLightbox: (lightboxPhotoId) => set({ lightboxPhotoId }),
    setAddingToDump: (addingToDumpId) => set({ addingToDumpId }),

    // ── undo/redo ─────────────────────────────────────────────────────────────

    undo: () => {
      if (undoStack.length === 0) return;
      const current = get();
      redoStack.push({ photos: current.photos, dumps: current.dumps });
      const prev = undoStack.pop()!;
      set({ photos: prev.photos, dumps: prev.dumps });
      persist();
    },

    redo: () => {
      if (redoStack.length === 0) return;
      const current = get();
      undoStack.push({ photos: current.photos, dumps: current.dumps });
      const next = redoStack.pop()!;
      set({ photos: next.photos, dumps: next.dumps });
      persist();
    },

    canUndo: () => undoStack.length > 0,
    canRedo: () => redoStack.length > 0,
  };
});

// ─── color mode ──────────────────────────────────────────────────────────────

export function applyColorMode(mode: ColorMode) {
  const root = document.documentElement;
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const isDark = mode === 'dark' || (mode === 'system' && prefersDark);

  if (isDark) {
    root.style.setProperty('--bg', '#0a0a0a');
    root.style.setProperty('--bg1', '#111');
    root.style.setProperty('--bg2', '#181818');
    root.style.setProperty('--bg3', '#222');
    root.style.setProperty('--border', '#1e1e1e');
    root.style.setProperty('--border2', '#2a2a2a');
    root.style.setProperty('--border3', '#333');
    root.style.setProperty('--text', '#e8e8e8');
    root.style.setProperty('--text2', '#999');
    root.style.setProperty('--text3', '#555');
    root.style.setProperty('--menu-bg', 'rgba(20, 20, 20, 0.75)');
  } else {
    // Day mode — warm tan
    root.style.setProperty('--bg', '#f0ebe0');
    root.style.setProperty('--bg1', '#e8e2d5');
    root.style.setProperty('--bg2', '#dfd8c8');
    root.style.setProperty('--bg3', '#d4ccba');
    root.style.setProperty('--border', '#c8bfa8');
    root.style.setProperty('--border2', '#b8ae98');
    root.style.setProperty('--border3', '#a89e88');
    root.style.setProperty('--text', '#1a1610');
    root.style.setProperty('--text2', '#5a5040');
    root.style.setProperty('--text3', '#8a7a60');
    root.style.setProperty('--menu-bg', 'rgba(230, 224, 210, 0.75)');
  }
}

// ─── server photo loading ─────────────────────────────────────────────────────

export async function loadPhotosFromServer() {
  try {
    // Skip if we already have persisted server photos (local or cloud)
    const existing = useStore.getState().photos;
    if (existing.some(p =>
      p.url.startsWith('/photos/') ||
      p.url.startsWith('/sample-photos/') ||
      p.url.includes('blob.vercel-storage.com')
    )) return;

    // Try loading sample photos first (preloaded examples)
    try {
      const sampleRes = await fetch('/sample-photos.json');
      if (sampleRes.ok) {
        const samplePhotos: Array<{ id: string; filename: string; url: string; category: string; labels: string[]; colorTemp?: number }> = await sampleRes.json();
        const photos: Photo[] = samplePhotos.map((p) => ({
          id: p.id,
          url: p.url,
          filename: p.filename,
          category: p.category,
          labels: p.labels || [],
          starred: false,
          isHuji: false,
        }));

        useStore.setState({ photos });
        const s = useStore.getState();
        saveState({
          photos: s.photos, dumps: s.dumps, activeDumpId: s.activeDumpId,
          captions: s.captions, colorMode: s.colorMode, poolSize: s.poolSize,
          filter: s.filter, activeFilters: s.activeFilters, customRules: s.customRules,
        });
        return;
      }
    } catch { /* continue to server photos */ }

    // Fallback to server photos endpoint
    const res = await fetch('/photos/');
    if (!res.ok) return;
    const filenames: string[] = await res.json();

    const presetFilenames = new Set(PRESET_DUMPS.flatMap((d) => d.photoFilenames));
    const presetFiles = filenames.filter((f) => presetFilenames.has(f));
    const otherFiles = filenames.filter((f) => !presetFilenames.has(f));
    const selectedFilenames = [...presetFiles, ...otherFiles].slice(0, 100);

    const photos: Photo[] = selectedFilenames.map((filename, i) => {
      let category = guessCategory(filename);
      for (const dump of PRESET_DUMPS) {
        const idx = dump.photoFilenames.indexOf(filename);
        if (idx !== -1) { category = dump.categories[idx]; break; }
      }
      return {
        id: `server-${i}-${filename}`,
        url: `/photos/${encodeURIComponent(filename)}`,
        filename,
        category,
        labels: [],
        starred: false,
        isHuji: detectHuji(filename),
      };
    });

    const photoByFilename = new Map(photos.map((p) => [p.filename, p]));
    const dumps: Dump[] = PRESET_DUMPS.map((preset, i) => ({
      id: `preset-${i + 1}`,
      num: i + 1,
      title: preset.title,
      photos: preset.photoFilenames.map((fn) => photoByFilename.get(fn)?.id).filter((id): id is string => !!id),
      vibeBadge: null,
    }));

    dumpCounter = dumps.length;
    useStore.setState({ photos, dumps, activeDumpId: dumps[0]?.id ?? null });
    const s = useStore.getState();
    saveState({
      photos: s.photos, dumps: s.dumps, activeDumpId: s.activeDumpId,
      captions: s.captions, colorMode: s.colorMode, poolSize: s.poolSize,
      filter: s.filter, activeFilters: s.activeFilters, customRules: s.customRules,
    });
  } catch { /* silently fail */ }
}

// ─── native AI bridge ─────────────────────────────────────────────────────────

if (typeof window !== 'undefined') {
  (window as any).__dumpsterAI = {
    createDumps: (jsonStr: string) => {
      try {
        const groups: Array<{ title: string; photos: Array<{ url: string; category: string }> }> = JSON.parse(jsonStr);
        groups.forEach((group) => {
          const newPhotos = group.photos.map((p, i) => ({
            id: `ai-${Date.now()}-${i}-${Math.random().toString(36).slice(2)}`,
            url: p.url,
            filename: p.url.split('/').pop() ?? 'photo.jpg',
            category: p.category,
            labels: [],
            starred: false,
            isHuji: false,
          }));
          useStore.setState((s) => ({ photos: [...s.photos, ...newPhotos] }));
          const dumpId = `ai-dump-${Date.now()}`;
          const num = useStore.getState().dumps.length + 1;
          useStore.setState((s) => ({
            dumps: [...s.dumps, { id: dumpId, num, title: group.title, photos: newPhotos.map((p) => p.id), vibeBadge: null }],
            activeDumpId: dumpId,
          }));
        });
      } catch (e) { console.error('__dumpsterAI error', e); }
    },
  };
}

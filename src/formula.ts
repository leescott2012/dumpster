// @catchcanary carousel formula scoring engine
import type { Photo } from './types';

// Human-readable label for each photo category (used in dump description + titles)
export const CATEGORY_DISPLAY: Record<string, string> = {
  PORTRAIT: 'Face',
  AUTOMOTIVE: 'Car',
  NIGHTLIFE: 'Night',
  ART: 'Museum',
  FITNESS: 'Gym',
  ABSTRACT: 'Abstract',
  FASHION: 'Style',
  ARCHITECTURE: 'Space',
  TRAVEL: 'Travel',
  DINING: 'Eats',
  WATCH: 'Watch',
  LIFESTYLE: 'Life',
  SCENE: 'Scene',
  STUDIO: 'Studio',
};

// Generate a creative dump title based on the photos' categories
export function generateDumpTitle(photos: Photo[]): string {
  if (photos.length === 0) return 'New Dump';

  const counts: Record<string, number> = {};
  photos.forEach((p) => {
    const cat = p.category.toUpperCase();
    counts[cat] = (counts[cat] || 0) + 1;
  });

  const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]);
  const primary = sorted[0]?.[0] ?? 'LIFESTYLE';
  const secondary = sorted[1]?.[0] ?? null;
  const secLabel = secondary ? (CATEGORY_DISPLAY[secondary] ?? secondary) : null;

  const pick = (arr: string[]) => arr[Math.floor(Math.random() * arr.length)];

  switch (primary) {
    case 'NIGHTLIFE':
      return secLabel
        ? `The ${secLabel} Night`
        : pick(['After Hours', 'The Night Edit', 'Nightfall', 'Dark Hours']);
    case 'AUTOMOTIVE':
      return secLabel
        ? `The ${secLabel} Drive`
        : pick(['The Drive', 'On The Road', 'The Car Edit']);
    case 'FASHION':
      return pick(['The Style Edit', 'The Fashion Diary', 'Dressed Up', 'The Look', 'The Fit']);
    case 'ART':
      return pick(['The Museum Run', 'Gallery Night', 'Culture Drop', 'The Art Edit']);
    case 'PORTRAIT':
      return secLabel
        ? `The ${secLabel} Portrait`
        : pick(['The Face Edit', 'Faces', 'Portrait Study']);
    case 'TRAVEL':
      return secLabel
        ? `${secLabel} Trip`
        : pick(['The Trip', 'On Location', 'Away Edit']);
    case 'FITNESS':
      return pick(['Gains Season', 'The Gym Diary', 'Work Mode', 'Session']);
    case 'ARCHITECTURE':
      return secLabel
        ? `The ${secLabel} Space`
        : pick(['The Space Edit', 'The Build', 'Interiors']);
    case 'DINING':
      return pick(['The Table', 'Good Eats', 'The Dinner Edit', 'Last Night']);
    case 'WATCH':
      return pick(['On The Wrist', 'The Watch Edit', 'Time Piece']);
    default:
      return secLabel
        ? `The ${CATEGORY_DISPLAY[primary] ?? primary} ${secLabel}`
        : `The ${CATEGORY_DISPLAY[primary] ?? primary} Edit`;
  }
}

export type SlotRole =
  | 'hook' | 'contrast' | 'detail' | 'fashion'
  | 'culture' | 'watch' | 'second-car' | 'insider'
  | 'atmosphere' | 'second-fashion' | 'wildcard' | 'closer';

export const SLOT_LABELS: Record<SlotRole, string> = {
  'hook': 'THE HOOK',
  'contrast': 'THE CONTRAST',
  'detail': 'THE DETAIL',
  'fashion': 'THE FASHION BEAT',
  'culture': 'THE CULTURAL MOMENT',
  'watch': 'THE WATCH',
  'second-car': 'THE SECOND CAR',
  'insider': 'THE INSIDER',
  'atmosphere': 'THE ATMOSPHERE',
  'second-fashion': 'SECOND FASHION BEAT',
  'wildcard': 'THE WILDCARD',
  'closer': 'THE CLOSER',
};

// 12-position template
export const TEMPLATE_12: SlotRole[] = [
  'hook', 'contrast', 'detail', 'fashion', 'culture', 'watch',
  'second-car', 'insider', 'atmosphere', 'second-fashion', 'wildcard', 'closer',
];

// 7-position tight edit
export const TEMPLATE_7: SlotRole[] = [
  'hook', 'contrast', 'detail', 'fashion', 'culture', 'second-car', 'closer',
];

// Score each category for each slot role (0–10)
const SLOT_SCORES: Record<SlotRole, Record<string, number>> = {
  hook:           { PORTRAIT: 10, AUTOMOTIVE: 10, ART: 7, FASHION: 5, NIGHTLIFE: 5 },
  contrast:       { AUTOMOTIVE: 10, PORTRAIT: 8, ARCHITECTURE: 6 },
  detail:         { WATCH: 10, FASHION: 8, AUTOMOTIVE: 6, PORTRAIT: 5 },
  fashion:        { FASHION: 10, PORTRAIT: 6, LIFESTYLE: 4 },
  culture:        { ART: 10, PORTRAIT: 7, LIFESTYLE: 5 },
  watch:          { WATCH: 10, FASHION: 5 },
  'second-car':   { AUTOMOTIVE: 10, ARCHITECTURE: 5 },
  insider:        { PORTRAIT: 10, NIGHTLIFE: 7, LIFESTYLE: 5 },
  atmosphere:     { ARCHITECTURE: 10, TRAVEL: 10, NIGHTLIFE: 8, SCENE: 10 },
  'second-fashion': { FASHION: 10, PORTRAIT: 6 },
  wildcard:       { DINING: 10, ART: 8, ARCHITECTURE: 7, TRAVEL: 7, LIFESTYLE: 6 },
  closer:         { ARCHITECTURE: 10, TRAVEL: 10, NIGHTLIFE: 8, ART: 8, PORTRAIT: 7 },
};

// Hook score — internal only, used to pick slide 1
export function hookScore(photo: Photo): number {
  const cat = photo.category.toUpperCase();
  if (cat === 'PORTRAIT') return 10;
  if (cat === 'AUTOMOTIVE') return 10;
  if (cat === 'ART') return 7;
  if (cat === 'NIGHTLIFE') return 6;
  if (cat === 'FASHION') return 5;
  return 3;
}

// Score a photo for a given slot
export function scoreForSlot(photo: Photo, slot: SlotRole): number {
  const cat = photo.category.toUpperCase();
  return SLOT_SCORES[slot]?.[cat] ?? 2;
}

// Auto-arrange photos into the best template order
export function arrangePhotos(photos: Photo[]): Photo[] {
  if (photos.length === 0) return [];
  const template = photos.length >= 10 ? TEMPLATE_12 : TEMPLATE_7;
  const slots = template.slice(0, photos.length);
  const remaining = [...photos];
  const result: Photo[] = new Array(slots.length).fill(null);

  slots.forEach((slot, slotIdx) => {
    if (remaining.length === 0) return;
    let best = -1;
    let bestScore = -1;
    remaining.forEach((photo, i) => {
      const s = scoreForSlot(photo, slot);
      if (s > bestScore) { bestScore = s; best = i; }
    });
    result[slotIdx] = remaining[best];
    remaining.splice(best, 1);
  });

  return result.filter(Boolean);
}

// Get the template slot for a given index
export function getSlotRole(index: number, total: number): SlotRole | null {
  const template = total >= 10 ? TEMPLATE_12 : TEMPLATE_7;
  return template[index] ?? null;
}

// Check color temperature consistency
export function checkColorTemp(photos: Photo[]): boolean {
  // Simplified: flag if mix of warm (travel/dining) and cool (nightlife/architecture)
  const warm = photos.filter(p => ['TRAVEL', 'DINING', 'FITNESS'].includes(p.category.toUpperCase())).length;
  const cool = photos.filter(p => ['NIGHTLIFE', 'ARCHITECTURE', 'STUDIO'].includes(p.category.toUpperCase())).length;
  if (photos.length < 3) return true;
  const warmRatio = warm / photos.length;
  const coolRatio = cool / photos.length;
  return !(warmRatio > 0.25 && coolRatio > 0.25);
}

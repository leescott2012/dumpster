export interface Photo {
  id: string;
  url: string;
  filename: string;
  category: string;
  labels: string[];
  starred: boolean;
  isHuji: boolean;
}

export interface Caption {
  id: string;
  text: string;
  style: 'storytelling' | 'emoji' | 'clean' | 'numbered';
  rating: number; // 0–5
  dumpId?: string;
  createdAt: number;
  favorited: boolean;
  banned?: boolean; // thumbs-down = never use again
}

export interface Dump {
  id: string;
  num: number;
  title: string;
  photos: string[]; // ordered photo IDs, max 20
  vibeBadge?: 'mismatch' | null;
  liked?: boolean;
  titleApproved?: boolean; // true = user kept it, false = user rejected it
}

export type Filter = 'all' | 'starred' | 'huji' | 'used' | 'videos';
export type ColorMode = 'dark' | 'day' | 'system';
export type PoolSize = 'small' | 'medium' | 'large';

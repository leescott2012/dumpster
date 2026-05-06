import { useState } from 'react';
import { useStore } from '../store';
import type { Caption } from '../types';

// ─── Caption generation (local formula) ──────────────────────────────────────

type CaptionStyle = Caption['style'];

const STYLE_OPTIONS: { key: CaptionStyle; label: string; desc: string }[] = [
  { key: 'punchy',       label: 'Punchy',       desc: 'Short & bold' },
  { key: 'storytelling', label: 'Story',         desc: 'Narrative arc' },
  { key: 'emoji',        label: 'Emoji',         desc: 'Vibes + icons' },
  { key: 'clean',        label: 'Clean',         desc: 'Minimal, elegant' },
  { key: 'numbered',     label: 'Numbered',      desc: 'Scene list' },
];

const CATEGORY_EMOJI: Record<string, string> = {
  PORTRAIT: '🪞', AUTOMOTIVE: '🚗', STUDIO: '🎵', NIGHTLIFE: '🌃',
  FITNESS: '💪', ART: '🎨', ARCHITECTURE: '🏛️', TRAVEL: '✈️',
  FASHION: '👔', WATCH: '⌚', LIFESTYLE: '✨', DINING: '🍷',
};

function generateCaption(
  style: CaptionStyle,
  dumpTitle: string,
  categories: string[],
  index: number
): string {
  const uniq = [...new Set(categories)].slice(0, 3);
  const cat1 = uniq[0] ?? 'LIFESTYLE';
  const cat2 = uniq[1] ?? cat1;
  const emojis = uniq.map(c => CATEGORY_EMOJI[c] ?? '✨').join(' ');
  const n = (index % 4) + 1; // variation seed 1–4

  const punchy = [
    `${dumpTitle.toUpperCase()}. No context needed.`,
    `Not showing off. Just sharing.`,
    `Different chapters, same energy.`,
    `This is the dump. You get it.`,
  ];

  const story = [
    `Some nights write themselves — ${dumpTitle.toLowerCase()} was one of them. Started with ${cat1.toLowerCase()}, ended somewhere completely different. Every slide is a scene I didn't plan.`,
    `${dumpTitle} wasn't supposed to be a series. But then the moments kept coming, and suddenly you have a dump. ${cat1} into ${cat2}. That's the formula.`,
    `The phone was out more than usual. The ${cat1.toLowerCase()} lighting was right. The energy in the room was right. ${dumpTitle} basically made itself.`,
    `No itinerary, no agenda — just a string of moments that somehow fit together. ${cat1} to ${cat2}, one frame at a time. Dropping ${dumpTitle}.`,
  ];

  const emojiStyle = [
    `${emojis}\n\n${dumpTitle} dump is live. Swipe through.`,
    `${dumpTitle} ↓\n\n${emojis} same vibe, different angles`,
    `${categories.slice(0, 4).map(c => CATEGORY_EMOJI[c] ?? '✨').join('')}\n\n${dumpTitle.toLowerCase()}.`,
    `${emojis} this one's for the archives`,
  ];

  const clean = [
    dumpTitle,
    `${dumpTitle.split(':')[0].trim()}.`,
    `${cat1.charAt(0) + cat1.slice(1).toLowerCase()} — ${dumpTitle.toLowerCase()}`,
    `Moments. ${dumpTitle}.`,
  ];

  const numbered = (() => {
    const cats = categories.slice(0, Math.min(categories.length, 5));
    return cats.map((c, i) => `${i + 1}. ${c.charAt(0) + c.slice(1).toLowerCase()}`).join('\n')
      + `\n\n${dumpTitle}.`;
  })();

  const pick = (arr: string[]) => arr[(n - 1) % arr.length];

  switch (style) {
    case 'punchy':       return pick(punchy);
    case 'storytelling': return pick(story);
    case 'emoji':        return pick(emojiStyle);
    case 'clean':        return pick(clean);
    case 'numbered':     return numbered;
  }
}

// ─── CaptionsView ─────────────────────────────────────────────────────────────

export default function CaptionsView() {
  const { dumps, photos, captions, addCaption, favoriteCaption, removeCaption } = useStore();
  const [activeDumpFilter, setActiveDumpFilter] = useState<string>('all');
  const [activeStyle, setActiveStyle] = useState<CaptionStyle>('punchy');
  const [generating, setGenerating] = useState<string | null>(null); // dumpId
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const visibleDumps = activeDumpFilter === 'all'
    ? dumps
    : dumps.filter(d => d.id === activeDumpFilter);

  const handleGenerate = async (dumpId: string) => {
    const dump = dumps.find(d => d.id === dumpId);
    if (!dump) return;
    setGenerating(dumpId);
    const dumpPhotos = dump.photos.map(id => photos.find(p => p.id === id)).filter(Boolean);
    const cats = dumpPhotos.map(p => p!.category);
    // Slight delay for feel
    await new Promise(r => setTimeout(r, 420));
    const existingCount = captions.filter(c => c.dumpId === dumpId && c.style === activeStyle).length;
    const text = generateCaption(activeStyle, dump.title, cats, existingCount);
    addCaption({ text, style: activeStyle, rating: 0, dumpId, favorited: false });
    setGenerating(null);
  };

  const handleCopy = (id: string, text: string) => {
    navigator.clipboard.writeText(text).then(() => {
      setCopiedId(id);
      setTimeout(() => setCopiedId(null), 1800);
    });
  };

  const dumpCaptions = (dumpId: string) =>
    [...captions.filter(c => c.dumpId === dumpId)].sort((a, b) => b.createdAt - a.createdAt);

  const totalCaptions = captions.length;

  return (
    <section style={{ paddingBottom: 80 }}>
      {/* Header */}
      <p style={{
        fontSize: 10, fontWeight: 800, letterSpacing: '0.22em',
        color: 'var(--accent)', textTransform: 'uppercase', marginBottom: 6,
      }}>CAPTIONS</p>
      <h2 style={{ fontSize: 34, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', marginBottom: 4 }}>
        Your Captions
      </h2>
      <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 28 }}>
        {totalCaptions} caption{totalCaptions !== 1 ? 's' : ''} saved · generate per dump below
      </p>

      {/* Style selector pill row */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 28, flexWrap: 'wrap' }}>
        {STYLE_OPTIONS.map(({ key, label, desc }) => (
          <button
            key={key}
            onClick={() => setActiveStyle(key)}
            title={desc}
            style={{
              padding: '7px 16px', borderRadius: 999, fontSize: 12, fontWeight: 600,
              border: activeStyle === key ? '1px solid var(--accent)' : '1px solid var(--border2)',
              background: activeStyle === key ? 'var(--accent)' : 'var(--bg2)',
              color: activeStyle === key ? '#000' : 'var(--text)',
              cursor: 'pointer', transition: 'all 0.15s', whiteSpace: 'nowrap',
            }}
          >{label}</button>
        ))}
      </div>

      {/* Dump filter */}
      {dumps.length > 1 && (
        <div style={{ display: 'flex', gap: 6, marginBottom: 24, overflowX: 'auto' }} className="dump-photos-row">
          <DumpChip label="All Dumps" active={activeDumpFilter === 'all'} onClick={() => setActiveDumpFilter('all')} />
          {dumps.map(d => (
            <DumpChip
              key={d.id}
              label={d.title.split(':')[0].trim()}
              active={activeDumpFilter === d.id}
              onClick={() => setActiveDumpFilter(d.id)}
            />
          ))}
        </div>
      )}

      {/* Empty state */}
      {dumps.length === 0 && (
        <EmptyState message="Create a dump first, then generate captions for it here." />
      )}

      {/* Per-dump caption cards */}
      {visibleDumps.map(dump => {
        const dc = dumpCaptions(dump.id);
        const isGen = generating === dump.id;
        const thumbPhotos = dump.photos.slice(0, 3).map(id => photos.find(p => p.id === id)).filter(Boolean);

        return (
          <div key={dump.id} style={{
            marginBottom: 40,
            background: 'var(--bg2)', border: '1px solid var(--border2)',
            borderRadius: 16, overflow: 'hidden',
          }}>
            {/* Dump header */}
            <div style={{
              padding: '16px 20px', display: 'flex', alignItems: 'center',
              justifyContent: 'space-between', gap: 12,
              borderBottom: '1px solid var(--border2)',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
                {/* Mini photo strip */}
                {thumbPhotos.length > 0 && (
                  <div style={{ display: 'flex', gap: 3, flexShrink: 0 }}>
                    {thumbPhotos.map((p) => p && (
                      <img
                        key={p.id}
                        src={p.url}
                        alt=""
                        style={{ width: 32, height: 42, objectFit: 'cover', borderRadius: 5, border: '1px solid var(--border)' }}
                      />
                    ))}
                  </div>
                )}
                <div style={{ minWidth: 0 }}>
                  <p style={{
                    fontSize: 9, color: 'var(--accent)', fontWeight: 800,
                    letterSpacing: '0.14em', textTransform: 'uppercase', marginBottom: 2,
                  }}>
                    DUMP {String(dump.num).padStart(2, '0')}
                  </p>
                  <p style={{
                    fontSize: 15, fontWeight: 700, color: 'var(--text)',
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                  }}>{dump.title}</p>
                  <p style={{ fontSize: 11, color: 'var(--text3)', marginTop: 1 }}>
                    {dump.photos.length} photos · {dc.length} caption{dc.length !== 1 ? 's' : ''}
                  </p>
                </div>
              </div>

              {/* Generate button */}
              <button
                onClick={() => handleGenerate(dump.id)}
                disabled={isGen || dump.photos.length === 0}
                style={{
                  flexShrink: 0, padding: '9px 18px', borderRadius: 999,
                  fontSize: 11, fontWeight: 800, letterSpacing: '0.1em', textTransform: 'uppercase',
                  background: isGen ? 'var(--accent-dim)' : 'var(--accent)',
                  border: 'none', color: '#000',
                  cursor: isGen || dump.photos.length === 0 ? 'default' : 'pointer',
                  opacity: dump.photos.length === 0 ? 0.4 : 1,
                  transition: 'all 0.15s', fontFamily: 'var(--font)',
                  display: 'flex', alignItems: 'center', gap: 6,
                }}
              >
                {isGen ? (
                  <>
                    <Spinner /> Generating…
                  </>
                ) : (
                  <>
                    <span style={{ fontSize: 14 }}>✦</span>
                    Generate
                  </>
                )}
              </button>
            </div>

            {/* Captions list */}
            {dc.length === 0 ? (
              <div style={{ padding: '24px 20px', textAlign: 'center' }}>
                <p style={{ fontSize: 13, color: 'var(--text3)' }}>
                  {dump.photos.length === 0
                    ? 'Add photos to this dump first'
                    : `Hit Generate to create a ${activeStyle} caption`}
                </p>
              </div>
            ) : (
              <div>
                {dc.map((cap, idx) => (
                  <CaptionCard
                    key={cap.id}
                    caption={cap}
                    copied={copiedId === cap.id}
                    showDivider={idx < dc.length - 1}
                    onCopy={() => handleCopy(cap.id, cap.text)}
                    onFavorite={() => favoriteCaption(cap.id)}
                    onRemove={() => removeCaption(cap.id)}
                  />
                ))}
              </div>
            )}
          </div>
        );
      })}
    </section>
  );
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function CaptionCard({
  caption, copied, showDivider, onCopy, onFavorite, onRemove,
}: {
  caption: Caption;
  copied: boolean;
  showDivider: boolean;
  onCopy: () => void;
  onFavorite: () => void;
  onRemove: () => void;
}) {
  const styleLabel = STYLE_OPTIONS.find(s => s.key === caption.style)?.label ?? caption.style;

  return (
    <div style={{ borderBottom: showDivider ? '1px solid var(--border)' : 'none' }}>
      <div style={{ padding: '16px 20px' }}>
        {/* Style badge */}
        <span style={{
          fontSize: 9, fontWeight: 700, letterSpacing: '0.12em', textTransform: 'uppercase',
          color: 'var(--accent)', background: 'var(--accent-dim)',
          padding: '2px 8px', borderRadius: 4, display: 'inline-block', marginBottom: 10,
        }}>{styleLabel}</span>

        {/* Caption text */}
        <p style={{
          fontSize: 14, lineHeight: 1.7, color: 'var(--text)',
          whiteSpace: 'pre-line', marginBottom: 14,
          fontStyle: caption.style === 'clean' ? 'italic' : 'normal',
        }}>{caption.text}</p>

        {/* Action row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {/* Copy */}
          <button
            onClick={onCopy}
            style={{
              padding: '6px 14px', borderRadius: 999, fontSize: 11, fontWeight: 700,
              background: copied ? 'var(--accent)' : 'var(--bg3)',
              border: copied ? 'none' : '1px solid var(--border2)',
              color: copied ? '#000' : 'var(--text2)',
              cursor: 'pointer', transition: 'all 0.15s', fontFamily: 'var(--font)',
              display: 'flex', alignItems: 'center', gap: 5,
            }}
          >
            {copied ? '✓ Copied' : '⌘ Copy'}
          </button>

          {/* Favorite */}
          <button
            onClick={onFavorite}
            style={{
              width: 32, height: 32, borderRadius: '50%', border: 'none',
              background: caption.favorited ? 'var(--accent-dim)' : 'var(--bg3)',
              color: caption.favorited ? 'var(--accent)' : 'var(--text3)',
              cursor: 'pointer', fontSize: 14, transition: 'all 0.15s',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
            title={caption.favorited ? 'Unfavorite' : 'Favorite'}
          >★</button>

          <div style={{ flex: 1 }} />

          {/* Delete */}
          <button
            onClick={onRemove}
            style={{
              width: 32, height: 32, borderRadius: '50%', border: 'none',
              background: 'transparent', color: 'var(--text3)',
              cursor: 'pointer', fontSize: 13, transition: 'all 0.15s',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
            title="Delete caption"
            onMouseEnter={(e) => (e.currentTarget.style.color = 'var(--red)')}
            onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--text3)')}
          >✕</button>
        </div>
      </div>
    </div>
  );
}

function DumpChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        flexShrink: 0, padding: '6px 14px', borderRadius: 999, fontSize: 11, fontWeight: 600,
        border: active ? '1px solid var(--accent)' : '1px solid var(--border2)',
        background: active ? 'var(--accent)' : 'var(--bg2)',
        color: active ? '#000' : 'var(--text)', cursor: 'pointer', transition: 'all 0.15s',
        whiteSpace: 'nowrap',
      }}
    >{label}</button>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div style={{ textAlign: 'center', padding: '56px 28px' }}>
      <div style={{
        width: 72, height: 72, borderRadius: '50%', background: 'var(--accent-dim)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        margin: '0 auto 16px',
      }}>
        <span style={{ fontSize: 28, color: 'var(--accent)' }}>✦</span>
      </div>
      <p style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)', marginBottom: 8 }}>No captions yet</p>
      <p style={{ fontSize: 13, color: 'var(--text3)', maxWidth: 280, margin: '0 auto' }}>{message}</p>
    </div>
  );
}

function Spinner() {
  return (
    <span style={{
      width: 11, height: 11, borderRadius: '50%',
      border: '2px solid rgba(0,0,0,0.25)', borderTopColor: '#000',
      display: 'inline-block', animation: 'spin 0.6s linear infinite',
    }} />
  );
}

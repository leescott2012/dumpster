import { useState } from 'react';
import { useStore } from '../store';
import type { Caption } from '../types';

const STYLES: Caption['style'][] = ['storytelling', 'emoji', 'clean', 'numbered'];

const STYLE_LABELS: Record<Caption['style'], string> = {
  storytelling: 'Story',
  emoji: 'Emoji',
  clean: 'Clean',
  numbered: 'List',
};

const STORYTELLING_TEMPLATES = [
  "Nobody told me the city would feel like this at 2am. Glad I showed up anyway.",
  "The drive was part of it.",
  "Some nights you're just there for the energy.",
  "Didn't plan this one. Best ones never are.",
  "Not everything needs context. This one does.",
  "You had to be there. Glad I was.",
  "The quiet before everything got loud.",
  "This is what I meant when I said I was busy.",
  "Some rooms you walk into and already know.",
  "Shot this on a Tuesday. Tuesday felt like this.",
  "I keep coming back to this one.",
  "The in-between is underrated.",
  "Paid attention. Got rewarded.",
  "Nothing was planned. Everything was intentional.",
  "There's a version of this night I'll never fully explain.",
];

const EMOJI_TEMPLATES = [
  ".",
  "..",
  "...",
  "....",
  "…",
];

const CLEAN_TEMPLATES = [
  "No context.",
  "24hrs.",
  "The usual.",
  "Read the room.",
  "Still here.",
  "Running it back.",
  "Don't overthink it.",
  "Part of the process.",
  "Filed under necessary.",
  "Nothing changes if nothing changes.",
  "Present.",
  "Worth it.",
  "That's it.",
  "Locked in.",
  "As expected.",
];

const NUMBERED_TEMPLATES = [
  "01. The look\n02. The vibe\n03. The exit",
  "01. Showed up\n02. Locked in\n03. Said nothing",
  "01. The setup\n02. The moment\n03. The after",
  "01. Early\n02. On time\n03. Never late",
  "01. The city\n02. The car\n03. The night",
  "01. Mood\n02. Movement\n03. Memory",
  "01. Vision\n02. Execute\n03. Move on",
  "01. Started\n02. Stayed\n03. Left different",
];

function generateCaption(style: Caption['style'], used: Set<string> = new Set()): string {
  const templates = {
    storytelling: STORYTELLING_TEMPLATES,
    emoji: EMOJI_TEMPLATES,
    clean: CLEAN_TEMPLATES,
    numbered: NUMBERED_TEMPLATES,
  }[style];
  const available = templates.filter(t => !used.has(t));
  const pool = available.length > 0 ? available : templates; // fallback to all if exhausted
  return pool[Math.floor(Math.random() * pool.length)];
}

type FilterTab = 'all' | 'favorites' | 'banned';

export default function CaptionPool() {
  const { captions, dumps, activeDumpId, addCaption, banCaption, favoriteCaption, removeCaption } = useStore();
  const [selectedStyle, setSelectedStyle] = useState<Caption['style']>('storytelling');
  const [customText, setCustomText] = useState('');
  const [filterTab, setFilterTab] = useState<FilterTab>('all');

  const activeDump = dumps.find(d => d.id === activeDumpId);

  const filteredCaptions = captions
    .filter(c => {
      if (filterTab === 'favorites') return c.favorited && !c.banned;
      if (filterTab === 'banned') return c.banned;
      return !c.banned;
    })
    .sort((a, b) => b.createdAt - a.createdAt);

  const bannedCount = captions.filter(c => c.banned).length;

  const handleAutoGenerate = () => {
    const usedTexts = new Set(captions.map(c => c.text));
    const text = generateCaption(selectedStyle, usedTexts);
    if (!text) return; // all templates exhausted
    addCaption({
      text,
      style: selectedStyle,
      rating: 0,
      dumpId: activeDumpId ?? undefined,
      favorited: false,
    });
  };

  const handleAddCustom = () => {
    if (!customText.trim()) return;
    addCaption({
      text: customText.trim(),
      style: selectedStyle,
      rating: 0,
      dumpId: activeDumpId ?? undefined,
      favorited: false,
    });
    setCustomText('');
  };

  return (
    <section>
      {/* Header */}
      <p style={{
        fontSize: 10, fontWeight: 700, letterSpacing: '0.18em',
        color: 'var(--gold)', textTransform: 'uppercase', marginBottom: 10,
      }}>CAPTION POOL</p>

      <h2 style={{ fontSize: 36, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', marginBottom: 6 }}>
        Captions
      </h2>
      <p style={{ fontSize: 13, color: 'var(--text3)', marginBottom: 20 }}>
        {captions.filter(c => !c.banned).length} captions{activeDump ? ` · Active: ${activeDump.title}` : ''}
      </p>

      {/* Style selector */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 16, flexWrap: 'wrap' }}>
        {STYLES.map(s => (
          <button
            key={s}
            onClick={() => setSelectedStyle(s)}
            style={{
              padding: '6px 14px', borderRadius: 20,
              fontSize: 11, fontWeight: 600, letterSpacing: '0.04em',
              background: selectedStyle === s ? 'var(--gold-dim)' : 'transparent',
              border: `1px solid ${selectedStyle === s ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
              color: selectedStyle === s ? 'var(--gold)' : 'var(--text3)',
              cursor: 'pointer', transition: 'all 0.15s',
            }}
          >
            {STYLE_LABELS[s]}
          </button>
        ))}
      </div>

      {/* Auto-generate button */}
      <button
        onClick={handleAutoGenerate}
        style={{
          width: '100%', padding: '12px 16px', borderRadius: 10,
          background: 'var(--gold-dim)', border: '1px solid rgba(200,169,110,0.3)',
          color: 'var(--gold)', fontSize: 13, fontWeight: 700,
          letterSpacing: '0.06em', cursor: 'pointer',
          transition: 'all 0.15s', marginBottom: 12,
        }}
        onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'rgba(200,169,110,0.25)'; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = 'var(--gold-dim)'; }}
      >
        Auto-Generate {STYLE_LABELS[selectedStyle]} Caption
      </button>

      {/* Custom caption input */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 24 }}>
        <input
          value={customText}
          onChange={e => setCustomText(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') handleAddCustom(); }}
          placeholder="Write your own caption..."
          style={{
            flex: 1, padding: '10px 14px', borderRadius: 8,
            background: 'var(--bg2)', border: '1px solid var(--border2)',
            color: 'var(--text)', fontSize: 12, fontFamily: 'var(--font)',
            outline: 'none',
          }}
        />
        <button
          onClick={handleAddCustom}
          style={{
            padding: '10px 16px', borderRadius: 8,
            background: 'var(--bg2)', border: '1px solid var(--border2)',
            color: 'var(--text3)', fontSize: 11, fontWeight: 600,
            cursor: 'pointer', transition: 'all 0.15s', whiteSpace: 'nowrap',
          }}
          onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--gold)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--gold)'; }}
          onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--text3)'; (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--border2)'; }}
        >
          + Add
        </button>
      </div>

      {/* Filter bar */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        {([
          { key: 'all' as const, label: 'All' },
          { key: 'favorites' as const, label: 'Favorites' },
          { key: 'banned' as const, label: `Never Use${bannedCount > 0 ? ` (${bannedCount})` : ''}` },
        ]).map(tab => (
          <button
            key={tab.key}
            onClick={() => setFilterTab(tab.key)}
            style={{
              padding: '5px 12px', borderRadius: 20, fontSize: 11, fontWeight: 600,
              background: filterTab === tab.key ? (tab.key === 'banned' ? 'rgba(224,92,92,0.12)' : 'var(--gold-dim)') : 'transparent',
              border: `1px solid ${filterTab === tab.key ? (tab.key === 'banned' ? 'rgba(224,92,92,0.4)' : 'rgba(200,169,110,0.4)') : 'var(--border2)'}`,
              color: filterTab === tab.key ? (tab.key === 'banned' ? 'var(--red)' : 'var(--gold)') : 'var(--text3)',
              cursor: 'pointer',
            }}
          >{tab.label}</button>
        ))}
      </div>

      {/* Caption list */}
      {filteredCaptions.length === 0 ? (
        <div style={{
          padding: '40px 20px', textAlign: 'center',
          border: '1.5px dashed var(--border3)', borderRadius: 12,
          color: 'var(--text3)', fontSize: 13,
        }}>
          {filterTab === 'banned'
            ? <p>No banned captions</p>
            : filterTab === 'favorites'
            ? <p>No favorites yet</p>
            : (
              <>
                <p style={{ marginBottom: 8 }}>No captions yet</p>
                <p style={{ fontSize: 11 }}>Generate or write a caption above</p>
              </>
            )
          }
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filteredCaptions.map((caption) => (
            <CaptionCard
              key={caption.id}
              caption={caption}
              onBan={() => banCaption(caption.id)}
              onFavorite={() => favoriteCaption(caption.id)}
              onRemove={() => removeCaption(caption.id)}
            />
          ))}
        </div>
      )}
    </section>
  );
}

// ─── Caption Card ─────────────────────────────────────────────────────────────

function CaptionCard({ caption, onBan, onFavorite, onRemove }: {
  caption: Caption;
  onBan: () => void;
  onFavorite: () => void;
  onRemove: () => void;
}) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(caption.text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div style={{
      padding: '14px 16px', borderRadius: 10,
      background: caption.banned ? 'rgba(224,92,92,0.05)' : 'var(--bg2)',
      border: `1px solid ${caption.banned ? 'rgba(224,92,92,0.25)' : 'var(--border2)'}`,
      transition: 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
      opacity: caption.banned ? 0.65 : 1,
    }}>
      {/* Caption text + thumbs row */}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 10 }}>
        <p style={{
          flex: 1,
          fontSize: 14, color: caption.banned ? 'var(--text3)' : 'var(--text)', lineHeight: 1.5,
          whiteSpace: 'pre-wrap',
          textDecoration: caption.banned ? 'line-through' : 'none',
        }}>
          {caption.text}
        </p>
        {/* Thumbs — only show on non-banned captions */}
        {!caption.banned && (
          <div style={{ display: 'flex', gap: 6, flexShrink: 0, marginTop: 2 }}>
            <button
              onClick={onFavorite}
              title="Good caption"
              style={{
                background: caption.favorited ? 'rgba(80,180,80,0.12)' : 'transparent',
                border: `1px solid ${caption.favorited ? 'rgba(80,180,80,0.4)' : 'var(--border2)'}`,
                borderRadius: 6, width: 30, height: 30, cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                transition: 'all 0.15s',
              }}
            >
              <ThumbSvg up filled={caption.favorited} color={caption.favorited ? '#50b450' : 'var(--text3)'} />
            </button>
            <button
              onClick={onBan}
              title="Never use"
              style={{
                background: 'transparent',
                border: '1px solid var(--border2)',
                borderRadius: 6, width: 30, height: 30, cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                transition: 'all 0.15s',
              }}
              onMouseEnter={e => { (e.currentTarget as HTMLButtonElement).style.borderColor = 'rgba(224,92,92,0.5)'; }}
              onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--border2)'; }}
            >
              <ThumbSvg up={false} filled={false} color="var(--text3)" />
            </button>
          </div>
        )}
        {/* Banned label */}
        {caption.banned && (
          <span style={{
            fontSize: 8, fontWeight: 700, letterSpacing: '0.1em',
            color: 'var(--red)', background: 'rgba(224,92,92,0.12)',
            padding: '2px 6px', borderRadius: 4, flexShrink: 0, marginTop: 4,
            textTransform: 'uppercase',
          }}>Never Use</span>
        )}
      </div>

      {/* Meta row */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
        <span style={{
          fontSize: 9, fontWeight: 700, letterSpacing: '0.1em',
          padding: '2px 8px', borderRadius: 4,
          background: 'var(--gold-dim)', color: 'var(--gold)',
          textTransform: 'uppercase',
        }}>
          {STYLE_LABELS[caption.style]}
        </span>

        {/* Action buttons */}
        <div style={{ display: 'flex', gap: 6 }}>
          {!caption.banned && (
            <button
              onClick={handleCopy}
              style={{
                fontSize: 9, fontWeight: 600, padding: '3px 8px', borderRadius: 4,
                background: 'transparent', border: '1px solid var(--border2)',
                color: copied ? 'var(--gold)' : 'var(--text3)', cursor: 'pointer',
              }}
            >{copied ? 'Copied!' : 'Copy'}</button>
          )}
          <button
            onClick={onRemove}
            style={{
              fontSize: 9, fontWeight: 600, padding: '3px 8px', borderRadius: 4,
              background: 'transparent', border: '1px solid rgba(224,92,92,0.3)',
              color: 'var(--red)', cursor: 'pointer',
            }}
          >Delete</button>
        </div>
      </div>
    </div>
  );
}

// ─── Thumb SVG ────────────────────────────────────────────────────────────────

function ThumbSvg({ up, filled, color }: { up: boolean; filled: boolean; color: string }) {
  return (
    <svg
      width="14" height="14"
      viewBox="0 0 24 24"
      fill={filled ? color : 'none'}
      stroke={color}
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ transform: up ? 'none' : 'scaleY(-1)', transition: 'fill 0.15s, stroke 0.15s' }}
    >
      <path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3H14z" />
      <path d="M7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3" />
    </svg>
  );
}

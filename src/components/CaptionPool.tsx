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
  'There\'s a story behind every photo, but this one speaks for itself.',
  'Some moments deserve to live forever.',
  'Caught between the city lights and the night sky.',
  'The journey is the destination.',
  'Every detail tells a story.',
];

const EMOJI_TEMPLATES = [
  '....',
  '.....',
  '......',
  '.....',
  '......',
];

const CLEAN_TEMPLATES = [
  'Details.',
  'Perspective.',
  'Moments.',
  'Curated.',
  'Timeless.',
];

const NUMBERED_TEMPLATES = [
  '1. Show up\n2. Stand out\n3. Repeat',
  '1. Vision\n2. Execution\n3. Results',
  '1. Dream it\n2. Build it\n3. Live it',
  '1. Create\n2. Elevate\n3. Dominate',
];

function generateCaption(style: Caption['style']): string {
  const templates = {
    storytelling: STORYTELLING_TEMPLATES,
    emoji: EMOJI_TEMPLATES,
    clean: CLEAN_TEMPLATES,
    numbered: NUMBERED_TEMPLATES,
  }[style];
  return templates[Math.floor(Math.random() * templates.length)];
}

export default function CaptionPool() {
  const { captions, dumps, activeDumpId, addCaption, rateCaption, favoriteCaption, removeCaption } = useStore();
  const [selectedStyle, setSelectedStyle] = useState<Caption['style']>('storytelling');
  const [customText, setCustomText] = useState('');
  const [filterFavorites, setFilterFavorites] = useState(false);

  const activeDump = dumps.find(d => d.id === activeDumpId);

  const filteredCaptions = captions
    .filter(c => filterFavorites ? c.favorited : true)
    .sort((a, b) => b.createdAt - a.createdAt);

  const handleAutoGenerate = () => {
    const text = generateCaption(selectedStyle);
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
        {captions.length} captions{activeDump ? ` · Active: ${activeDump.title}` : ''}
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
        <button
          onClick={() => setFilterFavorites(false)}
          style={{
            padding: '5px 12px', borderRadius: 20, fontSize: 11, fontWeight: 600,
            background: !filterFavorites ? 'var(--gold-dim)' : 'transparent',
            border: `1px solid ${!filterFavorites ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
            color: !filterFavorites ? 'var(--gold)' : 'var(--text3)',
            cursor: 'pointer',
          }}
        >All</button>
        <button
          onClick={() => setFilterFavorites(true)}
          style={{
            padding: '5px 12px', borderRadius: 20, fontSize: 11, fontWeight: 600,
            background: filterFavorites ? 'var(--gold-dim)' : 'transparent',
            border: `1px solid ${filterFavorites ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
            color: filterFavorites ? 'var(--gold)' : 'var(--text3)',
            cursor: 'pointer',
          }}
        >Favorites</button>
      </div>

      {/* Caption list */}
      {filteredCaptions.length === 0 ? (
        <div style={{
          padding: '40px 20px', textAlign: 'center',
          border: '1.5px dashed var(--border3)', borderRadius: 12,
          color: 'var(--text3)', fontSize: 13,
        }}>
          <p style={{ marginBottom: 8 }}>No captions yet</p>
          <p style={{ fontSize: 11 }}>Generate or write a caption above</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filteredCaptions.map((caption, idx) => (
            <CaptionCard
              key={caption.id}
              caption={caption}
              onRate={(rating) => rateCaption(caption.id, rating)}
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

function CaptionCard({ caption, onRate, onFavorite, onRemove }: {
  caption: Caption;
  onRate: (rating: number) => void;
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
    <div className="menu-dropdown" style={{
      padding: '14px 16px', borderRadius: 10,
      background: 'var(--bg2)', border: '1px solid var(--border2)',
      transition: 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)',
    }}>
      {/* Caption text */}
      <p style={{
        fontSize: 14, color: 'var(--text)', lineHeight: 1.5,
        marginBottom: 10, whiteSpace: 'pre-wrap',
      }}>
        {caption.text}
      </p>

      {/* Meta row */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {/* Style badge */}
          <span style={{
            fontSize: 9, fontWeight: 700, letterSpacing: '0.1em',
            padding: '2px 8px', borderRadius: 4,
            background: 'var(--gold-dim)', color: 'var(--gold)',
            textTransform: 'uppercase',
          }}>
            {STYLE_LABELS[caption.style]}
          </span>

          {/* Rating stars */}
          <div style={{ display: 'flex', gap: 2 }}>
            {[1, 2, 3, 4, 5].map(star => (
              <button
                key={star}
                onClick={() => onRate(caption.rating === star ? 0 : star)}
                style={{
                  background: 'none', border: 'none', cursor: 'pointer',
                  fontSize: 12, color: star <= caption.rating ? 'var(--gold)' : 'var(--text3)',
                  padding: '0 1px', lineHeight: 1,
                }}
              >
                {star <= caption.rating ? '★' : '☆'}
              </button>
            ))}
          </div>
        </div>

        {/* Action buttons */}
        <div style={{ display: 'flex', gap: 6 }}>
          <button
            onClick={handleCopy}
            style={{
              fontSize: 9, fontWeight: 600, padding: '3px 8px', borderRadius: 4,
              background: 'transparent', border: '1px solid var(--border2)',
              color: copied ? 'var(--gold)' : 'var(--text3)', cursor: 'pointer',
            }}
          >{copied ? 'Copied!' : 'Copy'}</button>
          <button
            onClick={onFavorite}
            style={{
              fontSize: 12, padding: '2px 6px', borderRadius: 4,
              background: caption.favorited ? 'var(--gold-dim)' : 'transparent',
              border: `1px solid ${caption.favorited ? 'rgba(200,169,110,0.4)' : 'var(--border2)'}`,
              color: caption.favorited ? 'var(--gold)' : 'var(--text3)', cursor: 'pointer',
            }}
          >{caption.favorited ? '★' : '☆'}</button>
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

import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { style, photos, usedCaptions, styleProfile } = req.body as {
    style: string;
    photos: Array<{ category: string; labels: string[] }>;
    usedCaptions: string[];
    styleProfile?: string;
  };

  const photoContext = photos && photos.length > 0
    ? photos.map((p) => `${p.category}: ${(p.labels || []).join(', ')}`).join(' | ')
    : 'luxury lifestyle photo dump';

  const styleGuides: Record<string, string> = {
    storytelling: 'Write 1-3 sentences. Cinematic, evocative, narrative-driven. Like a movie caption, not an Instagram cliché.',
    emoji: 'Write ONLY 4-8 emojis that capture the mood. Zero text, just emojis.',
    clean: 'Write ONE word or a ultra-short phrase (1-5 words max). Minimal. Powerful. Poetic.',
    numbered: 'Write exactly 3 short numbered items: "1. ... 2. ... 3. ..." Each item is 2-5 words.',
  };

  const avoidNote = usedCaptions && usedCaptions.length > 0
    ? `\n\nNEVER repeat or paraphrase any of these already-used captions:\n${usedCaptions.slice(-30).map((c) => `- "${c}"`).join('\n')}\n\nBe genuinely different and original.`
    : '';

  const guide = styleGuides[style] ?? styleGuides.clean;

  const creatorStyle = styleProfile?.trim()
    ? `\n\nCreator's personal style: ${styleProfile.trim()}`
    : '';

  try {
    const message = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 150,
      messages: [{
        role: 'user',
        content: `You are a High-End Magazine Editor and Instagram Creative Director. Your standard: every caption must feel like it belongs in a luxury fashion or culture magazine — W, i-D, System, Hypebeast at its most refined. Cool, confident, cinematic. Never generic. Never influencer-coded.${creatorStyle}

Photo context: ${photoContext}

Style instruction: ${guide}${avoidNote}

Output ONLY the caption itself. No quotes. No explanation. Just the caption text.`,
      }],
    });

    const caption = message.content[0]?.type === 'text' ? message.content[0].text.trim() : '';
    res.status(200).json({ caption });
  } catch (err) {
    console.error('generate-caption error:', err);
    res.status(500).json({ error: 'Generation failed', caption: '' });
  }
}

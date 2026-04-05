import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { photos, existingTitles, styleProfile } = req.body as {
    photos: Array<{ category: string; labels: string[] }>;
    existingTitles: string[];
    styleProfile?: string;
  };

  const photoContext = photos && photos.length > 0
    ? photos.map((p) => `${p.category}: ${(p.labels || []).join(', ')}`).join(' | ')
    : 'lifestyle photos';

  const avoidNote = existingTitles && existingTitles.length > 0
    ? `\n\nDo NOT use any of these existing titles or anything similar:\n${existingTitles.map((t) => `- "${t}"`).join('\n')}`
    : '';

  const creatorStyle = styleProfile?.trim()
    ? `\n\nCreator's personal style: ${styleProfile.trim()}`
    : '';

  try {
    const message = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 60,
      messages: [{
        role: 'user',
        content: `You are a High-End Magazine Editor naming a photo editorial. Think W Magazine, Dazed, System, AnOther — short, evocative, intentional titles that feel curated not casual.${creatorStyle}

Photos in this dump: ${photoContext}

Rules:
- 2-6 words max
- Stylish, confident, slightly editorial — like a magazine feature title
- Format: "Category: Vibe" or "Adjective Noun" or just a mood phrase
- Never generic (no "My Photos", "Weekend Vibes", "Good Times")
- Capitalize each word${avoidNote}

Output ONLY the title. Nothing else.`,
      }],
    });

    const title = message.content[0]?.type === 'text' ? message.content[0].text.trim() : 'New Dump';
    res.status(200).json({ title });
  } catch (err) {
    console.error('generate-dump-title error:', err);
    res.status(500).json({ error: 'Generation failed', title: '' });
  }
}

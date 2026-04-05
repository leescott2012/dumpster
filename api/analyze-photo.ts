import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const VALID_CATEGORIES = [
  'PORTRAIT', 'AUTOMOTIVE', 'NIGHTLIFE', 'ART', 'FITNESS',
  'FASHION', 'ARCHITECTURE', 'TRAVEL', 'DINING', 'WATCH',
  'LIFESTYLE', 'SCENE', 'STUDIO',
];

const CATEGORY_GUIDE = `
PORTRAIT — face, person, people as the main subject
AUTOMOTIVE — cars, motorcycles, vehicles, driving
NIGHTLIFE — clubs, bars, parties, late-night scenes, bottle service
ART — museums, galleries, sculptures, paintings, installations
FITNESS — gyms, workouts, sports, athletic activity
FASHION — clothing, outfits, shoes, accessories worn by person; style is the point
ARCHITECTURE — buildings, interiors, corridors, structures, spaces (no people needed)
TRAVEL — outdoor scenery, destinations, beaches, cities from tourist perspective
DINING — food, restaurants, tables, drinks as the subject
WATCH — timepieces, wristwatches as the main focus
STUDIO — recording studios, creative workspaces, professional production spaces
SCENE — crowd scenes, events, concerts, atmosphere shots with many people
LIFESTYLE — everything else; everyday moments, vibes, mixed content
`.trim();

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { imageBase64, mimeType } = req.body as { imageBase64: string; mimeType: string };
  if (!imageBase64 || !mimeType) {
    res.status(400).json({ error: 'Missing imageBase64 or mimeType' });
    return;
  }

  try {
    const message = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 256,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: mimeType as 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp',
              data: imageBase64,
            },
          },
          {
            type: 'text',
            text: `You are categorizing photos for an Instagram content app. Look at this photo carefully.

CATEGORY GUIDE:
${CATEGORY_GUIDE}

Rules:
- Pick the SINGLE most accurate category based on what the photo is ACTUALLY about
- If there's a person wearing fashion items but the scene is a bar/club, it's NIGHTLIFE
- If there's a car AND a person, pick AUTOMOTIVE if the car is the hero, PORTRAIT if the face is
- If it's an indoor architectural space (hotel lobby, corridor, staircase), it's ARCHITECTURE
- Labels should describe what's literally in the photo — specific, visual, concrete words

Return ONLY valid JSON, no explanation:
{"category": "CATEGORY", "labels": ["label1", "label2", "label3"]}`,
          },
        ],
      }],
    });

    const raw = message.content[0]?.type === 'text' ? message.content[0].text.trim() : '';

    // Extract JSON even if model wraps it in markdown
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};

    const category = VALID_CATEGORIES.includes(parsed.category) ? parsed.category : 'LIFESTYLE';
    const labels = Array.isArray(parsed.labels)
      ? parsed.labels.slice(0, 5).map((l: unknown) => String(l).toLowerCase().trim()).filter(Boolean)
      : [];

    res.status(200).json({ category, labels });
  } catch (err) {
    console.error('analyze-photo error:', err);
    res.status(500).json({ error: 'Analysis failed', category: 'LIFESTYLE', labels: [] });
  }
}

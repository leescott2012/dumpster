import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { anchors, candidates, styleProfile } = req.body as {
    anchors: Array<{ category: string; labels: string[] }>;
    candidates: Array<{ id: string; category: string; labels: string[] }>;
    styleProfile?: string;
  };

  if (!anchors?.length || !candidates?.length) {
    res.status(400).json({ error: 'Missing anchors or candidates' });
    return;
  }

  const anchorDesc = anchors.map((a) => `${a.category}: ${a.labels.join(', ')}`).join(' | ');
  const candidateList = candidates.map((c, i) =>
    `${i + 1}. [${c.id}] ${c.category}: ${c.labels.join(', ')}`
  ).join('\n');

  const styleContext = styleProfile?.trim()
    ? `\nCreator's aesthetic: ${styleProfile.trim()}`
    : '';

  try {
    const message = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 200,
      messages: [{
        role: 'user',
        content: `You are a High-End Magazine Editor curating a photo dump. The opener and closer are set. Rank the middle photos by how well they flow between the anchors — best contextual match first.${styleContext}

Anchor shots (opener + closer): ${anchorDesc}

Middle candidates to rank:
${candidateList}

Return ONLY a JSON array of IDs in ranked order (best fit first):
["id1", "id2", "id3"]

No explanation. Just the JSON array.`,
      }],
    });

    const text = message.content[0]?.type === 'text' ? message.content[0].text.trim() : '[]';
    const cleaned = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
    const rankedIds: string[] = JSON.parse(cleaned);

    res.status(200).json({ rankedIds });
  } catch (err) {
    console.error('rank-fillers error:', err);
    // Fallback: return original order
    res.status(200).json({ rankedIds: candidates.map((c) => c.id) });
  }
}

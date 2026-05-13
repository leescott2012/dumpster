// Pro-gated Instagram aesthetic scrubber.
//
// Flow:
//   1. iOS posts { profileURL, resultsLimit } to this endpoint.
//   2. We hit Apify's `apify/instagram-scraper` Actor with that URL (public posts only).
//   3. The captions + hashtags get distilled by Claude into a 2-3 sentence
//      "AI Style Profile" description, which the app stores in
//      @AppStorage("ai_style_profile") and injects into every caption prompt.
//
// Costs: ~$0.05 (Apify) + ~$0.002 (Claude) per scrub.
// Rate-limited per device on the iOS side (10 scrubs / 30 days for Pro users).

import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const APIFY_TOKEN = process.env.APIFY_TOKEN;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  if (!APIFY_TOKEN) {
    res.status(500).json({ error: 'APIFY_TOKEN not configured on server' });
    return;
  }
  if (!process.env.ANTHROPIC_API_KEY) {
    res.status(500).json({ error: 'ANTHROPIC_API_KEY not configured on server' });
    return;
  }

  const { profileURL, resultsLimit = 12 } = (req.body ?? {}) as {
    profileURL?: string;
    resultsLimit?: number;
  };

  // Light validation — only accept instagram.com URLs.
  if (!profileURL || typeof profileURL !== 'string' || !/instagram\.com\//i.test(profileURL)) {
    res.status(400).json({ error: 'Provide a valid Instagram profile URL.' });
    return;
  }

  try {
    // 1. Apify run (sync) — returns dataset items directly.
    const apifyUrl = `https://api.apify.com/v2/acts/apify~instagram-scraper/run-sync-get-dataset-items?token=${APIFY_TOKEN}`;
    const apifyRes = await fetch(apifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        directUrls: [profileURL],
        resultsType: 'posts',
        resultsLimit: Math.min(Math.max(resultsLimit, 4), 25),
        searchType: 'user',
        addParentData: false,
      }),
    });

    if (!apifyRes.ok) {
      const detail = await apifyRes.text();
      res.status(502).json({ error: 'Apify scrub failed', detail: detail.slice(0, 500) });
      return;
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const posts: any[] = await apifyRes.json();

    if (!Array.isArray(posts) || posts.length === 0) {
      res.status(404).json({ error: 'No public posts found on this profile.' });
      return;
    }

    // 2. Pull out the signal — captions, hashtags, basic engagement.
    const captions = posts
      .map((p) => (typeof p?.caption === 'string' ? p.caption : ''))
      .filter((c) => c.length > 0);

    const hashtags = Array.from(
      new Set(posts.flatMap((p) => (Array.isArray(p?.hashtags) ? p.hashtags : []))),
    ).slice(0, 20);

    const postBlock = posts
      .slice(0, resultsLimit)
      .map((p, i) => {
        const cap = (p?.caption ?? '[no caption]').toString().slice(0, 250);
        const likes = p?.likesCount ?? '?';
        return `Post ${i + 1} (${likes} likes): ${cap}`;
      })
      .join('\n');

    // 3. Distill via Claude.
    const distill = await anthropic.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 400,
      messages: [
        {
          role: 'user',
          content: `You are an Instagram aesthetic analyst. Read these posts from a creator's public Instagram and distill their visual+verbal style into a 2-3 sentence description that another AI can use to write captions and curate photo dumps in the same voice.

Focus on:
- Visual mood (moody / sun-drenched / neon / minimalist / cinematic / etc.)
- Subject matter (cars / portraits / nightlife / travel / fashion / etc.)
- Caption voice (sparse / poetic / hype-heavy / ironic / lowercase / etc.)
- Recurring motifs or vocabulary

Output ONLY the description prose — no preamble, no headers, no bullet lists, no quotes around it. Plain sentences. Under 600 characters.

Posts:
${postBlock}

Top hashtags: ${hashtags.slice(0, 12).join(', ')}`,
        },
      ],
    });

    const block = distill.content[0];
    const text = block && 'text' in block ? block.text.trim() : '';

    if (!text) {
      res.status(500).json({ error: 'AI returned an empty description.' });
      return;
    }

    res.status(200).json({
      description: text,
      postsAnalyzed: captions.length,
      hashtags: hashtags.slice(0, 10),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[scrub-instagram]', msg);
    res.status(500).json({ error: 'Scrub failed', detail: msg.slice(0, 500) });
  }
}

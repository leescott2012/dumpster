// Pro-gated Instagram aesthetic + engagement scrubber.
//
// Flow:
//   1. iOS posts { profileURL, resultsLimit } to this endpoint.
//   2. Apify's `apify/instagram-scraper` Actor returns public posts.
//   3. We capture caption/hashtags/likes/comments/views/post-type/timestamp/
//      mentions/location and RANK by engagement score.
//   4. Claude receives the full set + an explicit flag for the top-3
//      "winners" so the distill weights what actually performs.
//   5. Claude returns TWO outputs:
//      - styleDescription  → voice + visual mood (used for caption tone)
//      - engagementPlaybook → what wins for this creator (used for what
//        type of post, when, with what hook structure)
//   Both get injected into LLMService.userContextBlock() on the iOS side
//   so every AI generation respects the playbook too.
//
// Costs: ~$0.05-0.10 (Apify, depends on resultsLimit) + ~$0.003 (Claude).
// Rate-limited per device on the iOS side (10 scrubs / 30 days for Pro).

import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const APIFY_TOKEN = process.env.APIFY_TOKEN;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type RawPost = any;

interface RankedPost {
  caption: string;
  firstLine: string;
  hashtags: string[];
  mentions: string[];
  likes: number;
  comments: number;
  views: number;
  productType: string;
  carouselLength: number;
  location: string;
  postedAt: string;
  engagementScore: number;
}

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

  if (!profileURL || typeof profileURL !== 'string' || !/instagram\.com\//i.test(profileURL)) {
    res.status(400).json({ error: 'Provide a valid Instagram profile URL.' });
    return;
  }

  const limit = Math.min(Math.max(resultsLimit, 4), 25);

  try {
    // 1. Apify scrape
    const apifyUrl = `https://api.apify.com/v2/acts/apify~instagram-scraper/run-sync-get-dataset-items?token=${APIFY_TOKEN}`;
    const apifyRes = await fetch(apifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        directUrls: [profileURL],
        resultsType: 'posts',
        resultsLimit: limit,
        searchType: 'user',
        addParentData: false,
      }),
    });

    if (!apifyRes.ok) {
      const detail = await apifyRes.text();
      res.status(502).json({ error: 'Apify scrub failed', detail: detail.slice(0, 500) });
      return;
    }

    const posts: RawPost[] = await apifyRes.json();

    if (!Array.isArray(posts) || posts.length === 0) {
      res.status(404).json({ error: 'No public posts found on this profile.' });
      return;
    }

    // 2. Normalize + rank by engagement
    const ranked: RankedPost[] = posts.map((p) => {
      const caption = (p?.caption ?? '').toString();
      const firstLine = caption.split(/\r?\n/)[0]?.trim().slice(0, 200) ?? '';
      const likes = Number(p?.likesCount ?? 0);
      const comments = Number(p?.commentsCount ?? 0);
      const views = Number(p?.videoViewCount ?? p?.videoPlayCount ?? 0);
      return {
        caption,
        firstLine,
        hashtags: Array.isArray(p?.hashtags) ? p.hashtags.slice(0, 15) : [],
        mentions: Array.isArray(p?.mentions) ? p.mentions.slice(0, 8) : [],
        likes,
        comments,
        views,
        productType: (p?.productType ?? p?.type ?? 'Feed').toString(),
        carouselLength: Array.isArray(p?.images) ? p.images.length : (Array.isArray(p?.childPosts) ? p.childPosts.length : 1),
        location: (p?.locationName ?? '').toString(),
        postedAt: (p?.timestamp ?? p?.takenAt ?? '').toString(),
        // Score formula: comments weighted 3x (engagement quality),
        // views weighted 0.05x (reels reach), likes baseline.
        engagementScore: likes + comments * 3 + views * 0.05,
      };
    });

    ranked.sort((a, b) => b.engagementScore - a.engagementScore);
    const winners = ranked.slice(0, 3);
    const allUnique = Array.from(new Set(ranked.flatMap((r) => r.hashtags))).slice(0, 20);

    // 3. Build Claude prompt — explicit winner weighting
    const winnerBlock = winners
      .map((p, i) => {
        return `WINNER #${i + 1} (${fmtEng(p)})
Type: ${p.productType}${p.carouselLength > 1 ? ` (${p.carouselLength}-slide carousel)` : ''}
Hook: ${p.firstLine || '[no caption]'}
Full caption: ${p.caption.slice(0, 400) || '[no caption]'}
Hashtags: ${p.hashtags.slice(0, 8).join(', ') || 'none'}
${p.location ? `Location: ${p.location}\n` : ''}${p.mentions.length ? `Mentions: ${p.mentions.join(', ')}\n` : ''}`;
      })
      .join('\n\n');

    const restBlock = ranked
      .slice(3, limit)
      .map((p, i) => `Post ${i + 4} (${fmtEng(p)}, ${p.productType}): ${p.firstLine || '[no caption]'}`)
      .join('\n');

    const distill = await anthropic.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 700,
      messages: [
        {
          role: 'user',
          content: `You are an Instagram strategist. Analyze this creator's public posts and produce TWO outputs as valid JSON:

{
  "styleDescription": "2-3 sentence description of the creator's aesthetic + verbal voice (visual mood, subject matter, caption tone, recurring motifs). 400-600 chars.",
  "engagementPlaybook": "2-3 sentence playbook of WHAT WORKS for this creator (best-performing post types, hook formulas, hashtag combos, content patterns that drove the top engagement). 400-600 chars. Be specific and actionable — another AI will use this to write content that performs."
}

Weight the TOP-3 WINNERS heavily — those reflect what the audience rewards. The lower-engagement posts are context only.

TOP-3 WINNERS (highest engagement, weight these most):
${winnerBlock}

REST OF FEED (context only):
${restBlock || '[none]'}

Top hashtags overall: ${allUnique.slice(0, 12).join(', ') || 'none'}

Respond with ONLY the JSON object. No preamble, no markdown fences, no commentary.`,
        },
      ],
    });

    const block = distill.content[0];
    const raw = block && 'text' in block ? block.text.trim() : '';

    // 4. Parse Claude's JSON
    let parsed: { styleDescription?: string; engagementPlaybook?: string } = {};
    try {
      // Strip markdown fences if Claude adds them despite instructions
      const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/```$/g, '').trim();
      parsed = JSON.parse(cleaned);
    } catch (e) {
      console.error('[scrub-instagram] JSON parse failed, raw was:', raw.slice(0, 300));
      // Graceful fallback: dump everything into styleDescription
      parsed = { styleDescription: raw.slice(0, 750), engagementPlaybook: '' };
    }

    res.status(200).json({
      description: parsed.styleDescription ?? '',
      engagementPlaybook: parsed.engagementPlaybook ?? '',
      postsAnalyzed: ranked.length,
      hashtags: allUnique.slice(0, 10),
      topPosts: winners.map((w) => ({
        firstLine: w.firstLine.slice(0, 120),
        likes: w.likes,
        comments: w.comments,
        views: w.views,
        productType: w.productType,
      })),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[scrub-instagram]', msg);
    res.status(500).json({ error: 'Scrub failed', detail: msg.slice(0, 500) });
  }
}

function fmtEng(p: RankedPost): string {
  const parts: string[] = [];
  if (p.likes) parts.push(`${formatNum(p.likes)} likes`);
  if (p.comments) parts.push(`${formatNum(p.comments)} comments`);
  if (p.views) parts.push(`${formatNum(p.views)} views`);
  return parts.length ? parts.join(' / ') : 'no engagement data';
}

function formatNum(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toString();
}

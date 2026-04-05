import { put } from '@vercel/blob';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const rawFilename = req.headers['x-filename'] as string;
  if (!rawFilename) {
    res.status(400).json({ error: 'Missing x-filename header' });
    return;
  }

  const filename = decodeURIComponent(rawFilename);
  const contentType = (req.headers['content-type'] as string) || 'image/jpeg';

  try {
    const chunks: Buffer[] = [];
    await new Promise<void>((resolve, reject) => {
      req.on('data', (chunk: Buffer) => chunks.push(chunk));
      req.on('end', resolve);
      req.on('error', reject);
    });
    const buffer = Buffer.concat(chunks);

    const blob = await put(`photos/${Date.now()}-${filename}`, buffer, {
      access: 'public',
      contentType,
    });

    res.status(200).json({ url: blob.url });
  } catch (err) {
    console.error('upload-photo error:', err);
    res.status(500).json({ error: String(err) });
  }
}

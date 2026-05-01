import { Router, type IRouter } from "express";
import { logger } from "../lib/logger";

// ---------------------------------------------------------------------------
// Tiny in-memory TTL cache
// ---------------------------------------------------------------------------

interface CacheEntry<T> {
  data: T;
  expiresAt: number;
}

function createCache<T>(ttlMs: number) {
  const store = new Map<string, CacheEntry<T>>();
  return {
    get(key: string): T | undefined {
      const entry = store.get(key);
      if (!entry) return undefined;
      if (Date.now() > entry.expiresAt) {
        store.delete(key);
        return undefined;
      }
      return entry.data;
    },
    set(key: string, data: T): void {
      store.set(key, { data, expiresAt: Date.now() + ttlMs });
    },
  };
}

// ---------------------------------------------------------------------------
// Cache instances
// ---------------------------------------------------------------------------

// Book-list queries (search/topic/sort): 5-minute TTL so popular shelves
// are served from memory on repeated Home Screen visits within the same
// session, while still picking up new Gutendex data reasonably quickly.
const bookListCache = createCache<unknown>(5 * 60 * 1000);

// Individual book metadata barely changes: 1-hour TTL.
const bookCache = createCache<unknown>(60 * 60 * 1000);

// Book text can be hundreds of KB; cache aggressively since a Gutenberg
// text is effectively immutable.
const textCache = createCache<string>(24 * 60 * 60 * 1000);

// ---------------------------------------------------------------------------
// Upstream endpoints
// ---------------------------------------------------------------------------

const GUTENDEX_API = "https://gutendex.com/books";
const GUTENBERG_BASE = "https://www.gutenberg.org";

// ---------------------------------------------------------------------------
// Helpers (mirrors the logic in the mobile gutendex.ts lib)
// ---------------------------------------------------------------------------

function htmlToPlainText(html: string): string {
  return html
    .replace(/<head[\s\S]*?<\/head>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<\/(p|div|h[1-6]|li|tr|br|hr)>/gi, "\n\n")
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    .replace(/&hellip;/g, "…")
    .replace(/&rsquo;/g, "\u2019")
    .replace(/&lsquo;/g, "\u2018")
    .replace(/&rdquo;/g, "\u201d")
    .replace(/&ldquo;/g, "\u201c")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n");
}

function cleanGutenbergText(text: string): string {
  const startIdx = text.search(/\*\*\* START OF (THE|THIS) PROJECT GUTENBERG/i);
  if (startIdx !== -1) {
    const endOfLine = text.indexOf("\n", startIdx);
    if (endOfLine !== -1) {
      text = text.substring(endOfLine + 1);
    }
  }

  const endIdx = text.search(/\*\*\* END OF (THE|THIS) PROJECT GUTENBERG/i);
  if (endIdx !== -1) {
    text = text.substring(0, endIdx);
  }

  text = text.replace(/\n{4,}/g, "\n\n\n");
  return text.trim();
}

type TextSource = { url: string; isHtml: boolean };

function getBookTextSources(
  bookId: number,
  formats: Record<string, string>,
): TextSource[] {
  const sources: TextSource[] = [];
  const seen = new Set<string>();

  const push = (url: string | undefined, isHtml: boolean) => {
    if (!url) return;
    const u = url.replace(/^http:\/\//i, "https://");
    if (seen.has(u)) return;
    seen.add(u);
    sources.push({ url: u, isHtml });
  };

  // Plain text from Gutendex metadata
  push(formats["text/plain; charset=utf-8"], false);
  push(formats["text/plain; charset=us-ascii"], false);
  push(formats["text/plain"], false);
  push(formats["text/plain; charset=iso-8859-1"], false);

  // Deterministic Gutenberg cache URLs
  push(`${GUTENBERG_BASE}/cache/epub/${bookId}/pg${bookId}.txt`, false);
  push(`${GUTENBERG_BASE}/files/${bookId}/${bookId}-0.txt`, false);
  push(`${GUTENBERG_BASE}/files/${bookId}/${bookId}.txt`, false);

  // HTML fallbacks
  push(formats["text/html; charset=utf-8"], true);
  push(formats["text/html"], true);
  push(`${GUTENBERG_BASE}/cache/epub/${bookId}/pg${bookId}-images.html`, true);
  push(`${GUTENBERG_BASE}/cache/epub/${bookId}/pg${bookId}.html`, true);

  return sources;
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

const router: IRouter = Router();

// Proxy: GET /books  (book list / search / topic shelves)
router.get("/books", async (req, res) => {
  try {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(req.query)) {
      if (typeof value === "string") params.append(key, value);
    }
    const qs = params.toString();
    const cacheKey = qs;
    const cached = bookListCache.get(cacheKey);
    if (cached) {
      res.json(cached);
      return;
    }

    const url = qs ? `${GUTENDEX_API}?${qs}` : GUTENDEX_API;
    const upstream = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15000),
    });

    if (!upstream.ok) {
      res
        .status(upstream.status)
        .json({ error: `Upstream HTTP ${upstream.status}` });
      return;
    }

    const data: unknown = await upstream.json();
    bookListCache.set(cacheKey, data);
    res.json(data);
  } catch (err) {
    logger.error({ err }, "books proxy: failed to fetch book list");
    res.status(502).json({ error: "Failed to reach Gutendex" });
  }
});

// Proxy: GET /books/:id  (single book metadata)
router.get("/books/:id", async (req, res) => {
  const { id } = req.params;
  try {
    const cached = bookCache.get(id);
    if (cached) {
      res.json(cached);
      return;
    }

    const upstream = await fetch(`${GUTENDEX_API}/${id}`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15000),
    });

    if (!upstream.ok) {
      res
        .status(upstream.status)
        .json({ error: `Upstream HTTP ${upstream.status}` });
      return;
    }

    const data: unknown = await upstream.json();
    bookCache.set(id, data);
    res.json(data);
  } catch (err) {
    logger.error({ err }, "books proxy: failed to fetch book");
    res.status(502).json({ error: "Failed to reach Gutendex" });
  }
});

// Server-side text fetch: GET /books/:id/text
// Fetches the full book text from Project Gutenberg on behalf of the client.
// This bypasses the CORS restrictions that block direct browser requests to
// gutenberg.org, and the result is cached so repeat reads are near-instant.
router.get("/books/:id/text", async (req, res) => {
  const { id } = req.params;
  const bookId = Number(id);

  if (!Number.isFinite(bookId) || bookId <= 0) {
    res.status(400).json({ error: "Invalid book ID" });
    return;
  }

  try {
    const cached = textCache.get(id);
    if (cached) {
      res.set("Content-Type", "text/plain; charset=utf-8");
      res.send(cached);
      return;
    }

    // Resolve book metadata to get format URLs
    const bookUpstream = await fetch(`${GUTENDEX_API}/${bookId}`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15000),
    });

    if (!bookUpstream.ok) {
      res.status(bookUpstream.status).json({ error: "Book not found" });
      return;
    }

    const book = (await bookUpstream.json()) as {
      formats?: Record<string, string>;
    };
    const formats = book.formats ?? {};
    const sources = getBookTextSources(bookId, formats);

    if (sources.length === 0) {
      res
        .status(422)
        .json({ error: "No readable text format available for this book" });
      return;
    }

    const errors: string[] = [];
    for (const src of sources) {
      try {
        const textRes = await fetch(src.url, {
          signal: AbortSignal.timeout(30000),
        });
        if (!textRes.ok) {
          errors.push(`HTTP ${textRes.status} from ${src.url}`);
          continue;
        }
        const raw = await textRes.text();
        if (!raw || raw.length < 200) {
          errors.push(`empty/too-short body from ${src.url}`);
          continue;
        }
        const decoded = src.isHtml ? htmlToPlainText(raw) : raw;
        const cleaned = cleanGutenbergText(decoded);
        if (cleaned.length < 200) {
          errors.push(`empty after cleanup from ${src.url}`);
          continue;
        }

        textCache.set(id, cleaned);
        res.set("Content-Type", "text/plain; charset=utf-8");
        res.send(cleaned);
        return;
      } catch (srcErr) {
        const msg = srcErr instanceof Error ? srcErr.message : String(srcErr);
        errors.push(`${msg} (${src.url})`);
      }
    }

    logger.error({ bookId, errors }, "books proxy: all text sources failed");
    res.status(422).json({
      error: `Couldn't reach Project Gutenberg for book ${bookId}. Please check your connection and try again.`,
    });
  } catch (err) {
    logger.error({ err }, "books proxy: unexpected error fetching book text");
    res.status(502).json({ error: "Failed to fetch book text" });
  }
});

export default router;

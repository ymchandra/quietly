import { Platform } from "react-native";

export interface Person {
  name: string;
  birth_year?: number;
  death_year?: number;
}

export interface Book {
  id: number;
  title: string;
  authors: Person[];
  translators: Person[];
  subjects: string[];
  bookshelves: string[];
  languages: string[];
  copyright: boolean;
  media_type: string;
  formats: Record<string, string>;
  download_count: number;
}

export interface GutendexResponse {
  count: number;
  next: string | null;
  previous: string | null;
  results: Book[];
}

// On web (Expo Web / browser) all requests are routed through the API server
// proxy so that same-origin fetch calls are used.  This avoids CORS blocks on
// both the Gutendex API and on Project Gutenberg text files.
// On native (iOS / Android) there are no CORS restrictions, so we call the
// upstream services directly.
const IS_WEB = Platform.OS === "web";
const API_BASE = IS_WEB ? "/api/books" : "https://gutendex.com/books";

const REQUEST_HEADERS: Record<string, string> = {
  Accept: "*/*",
  "User-Agent": "Quietly/1.0 (Expo; Reader)",
};

// Fetch with a hard timeout — Project Gutenberg mirrors can hang.
async function fetchWithTimeout(
  url: string,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      headers: REQUEST_HEADERS,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

export async function fetchBooks(params?: {
  search?: string;
  page?: number;
  topic?: string;
  languages?: string;
  sort?: "popular" | "ascending" | "descending";
}): Promise<GutendexResponse> {
  const url = new URL(API_BASE, IS_WEB ? globalThis.location?.href : undefined);

  if (params?.search) url.searchParams.append("search", params.search);
  if (params?.page) url.searchParams.append("page", params.page.toString());
  if (params?.topic) url.searchParams.append("topic", params.topic);
  if (params?.languages) url.searchParams.append("languages", params.languages);
  if (params?.sort) url.searchParams.append("sort", params.sort);

  const res = await fetchWithTimeout(url.toString(), 15000);
  if (!res.ok) throw new Error(`Failed to fetch books (HTTP ${res.status})`);
  return res.json();
}

export async function fetchBook(id: number): Promise<Book> {
  const res = await fetchWithTimeout(`${API_BASE}/${id}`, 15000);
  if (!res.ok) throw new Error(`Failed to fetch book (HTTP ${res.status})`);
  return res.json();
}

export function getBookCoverUrl(book: Book): string | null {
  return book.formats["image/jpeg"] || null;
}

interface TextSource {
  url: string;
  // Whether the body is HTML and needs tag stripping.
  isHtml: boolean;
}

// Returns an ordered list of candidate text sources to try.
// We always include Gutenberg's deterministic cache URLs as a final
// fallback because Gutendex sometimes lists outdated mirror URLs.
export function getBookTextSources(book: Book): TextSource[] {
  const plain: string[] = [
    book.formats["text/plain; charset=utf-8"],
    book.formats["text/plain; charset=us-ascii"],
    book.formats["text/plain"],
    book.formats["text/plain; charset=iso-8859-1"],
  ].filter((u): u is string => typeof u === "string" && u.length > 0);

  const html: string[] = [
    book.formats["text/html; charset=utf-8"],
    book.formats["text/html"],
  ].filter((u): u is string => typeof u === "string" && u.length > 0);

  // Deterministic Gutenberg cache URLs (reliable when other mirrors fail).
  const cachePlain = [
    `https://www.gutenberg.org/cache/epub/${book.id}/pg${book.id}.txt`,
    `https://www.gutenberg.org/files/${book.id}/${book.id}-0.txt`,
    `https://www.gutenberg.org/files/${book.id}/${book.id}.txt`,
  ];
  const cacheHtml = [
    `https://www.gutenberg.org/cache/epub/${book.id}/pg${book.id}-images.html`,
    `https://www.gutenberg.org/cache/epub/${book.id}/pg${book.id}.html`,
  ];

  // Prefer https everywhere.
  const upgrade = (u: string) => u.replace(/^http:\/\//i, "https://");

  const sources: TextSource[] = [];
  const seen = new Set<string>();
  const push = (url: string, isHtml: boolean) => {
    const u = upgrade(url);
    if (seen.has(u)) return;
    seen.add(u);
    sources.push({ url: u, isHtml });
  };

  plain.forEach((u) => push(u, false));
  cachePlain.forEach((u) => push(u, false));
  html.forEach((u) => push(u, true));
  cacheHtml.forEach((u) => push(u, true));

  return sources;
}

// Backward-compat alias.
export function getBookTextUrl(book: Book): string | null {
  const sources = getBookTextSources(book);
  return sources[0]?.url ?? null;
}

// Strip HTML tags and decode common entities so the body can be
// rendered as plain text. This is intentionally minimal — full HTML
// rendering would defeat the point of a calm plain-text reader.
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
    .replace(/&mdash;/g, "\u2014")
    .replace(/&ndash;/g, "\u2013")
    .replace(/&hellip;/g, "\u2026")
    .replace(/&rsquo;/g, "\u2019")
    .replace(/&lsquo;/g, "\u2018")
    .replace(/&rdquo;/g, "\u201d")
    .replace(/&ldquo;/g, "\u201c")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n");
}

export function cleanGutenbergText(text: string): string {
  // Strip license headers/footers
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

  // Collapse runs of 4+ blank lines into 3
  text = text.replace(/\n{4,}/g, "\n\n\n");

  return text.trim();
}

export async function fetchBookText(book: Book): Promise<string> {
  // On web, delegate to the API server which fetches and cleans the text
  // server-side — bypassing the CORS restrictions that block direct browser
  // requests to gutenberg.org.
  if (IS_WEB) {
    const res = await fetchWithTimeout(`${API_BASE}/${book.id}/text`, 60000);
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      const message = (() => {
        try {
          return (JSON.parse(body) as { error?: string }).error ?? body;
        } catch {
          return body;
        }
      })();
      throw new Error(
        message ||
          `Couldn't reach Project Gutenberg for "${book.title}". Please check your connection and try again.`,
      );
    }
    return res.text();
  }

  // Native: try each source in sequence (no CORS restrictions).
  const sources = getBookTextSources(book);
  if (sources.length === 0) {
    throw new Error("No readable text format is available for this book.");
  }

  const errors: string[] = [];
  for (const src of sources) {
    try {
      const res = await fetchWithTimeout(src.url, 30000);
      if (!res.ok) {
        errors.push(`HTTP ${res.status} from ${src.url}`);
        continue;
      }
      const raw = await res.text();
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
      return cleaned;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${message} (${src.url})`);
    }
  }

  // Keep the surfaced error compact — the dev console has the full list.
  console.error("[gutendex] all text sources failed:", errors);
  throw new Error(
    `Couldn't reach Project Gutenberg for "${book.title}". Please check your connection and try again.`,
  );
}

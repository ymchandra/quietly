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

const API_BASE = "https://gutendex.com/books";

const REQUEST_HEADERS: Record<string, string> = {
  "Accept": "*/*",
  "User-Agent": "Quietread/1.0 (Expo; Reader)",
};

export async function fetchBooks(params?: {
  search?: string;
  page?: number;
  topic?: string;
  languages?: string;
  sort?: "popular" | "ascending" | "descending";
}): Promise<GutendexResponse> {
  const url = new URL(API_BASE);

  if (params?.search) url.searchParams.append("search", params.search);
  if (params?.page) url.searchParams.append("page", params.page.toString());
  if (params?.topic) url.searchParams.append("topic", params.topic);
  if (params?.languages) url.searchParams.append("languages", params.languages);
  if (params?.sort) url.searchParams.append("sort", params.sort);

  const res = await fetch(url.toString(), { headers: REQUEST_HEADERS });
  if (!res.ok) throw new Error(`Failed to fetch books (HTTP ${res.status})`);
  return res.json();
}

export async function fetchBook(id: number): Promise<Book> {
  const res = await fetch(`${API_BASE}/${id}`, { headers: REQUEST_HEADERS });
  if (!res.ok) throw new Error(`Failed to fetch book (HTTP ${res.status})`);
  return res.json();
}

export function getBookCoverUrl(book: Book): string | null {
  return book.formats["image/jpeg"] || null;
}

// Returns an ordered list of candidate plain-text URLs to try.
// Project Gutenberg exposes multiple URLs per book; the first
// available is not always reachable (mirror outages, redirect loops),
// so we keep a fallback list and try them in order.
export function getBookTextUrls(book: Book): string[] {
  const candidates = [
    book.formats["text/plain; charset=utf-8"],
    book.formats["text/plain; charset=us-ascii"],
    book.formats["text/plain"],
    book.formats["text/plain; charset=iso-8859-1"],
  ].filter((u): u is string => typeof u === "string" && u.length > 0);

  // Prefer https over http when both are present.
  const upgraded = candidates.map((u) => u.replace(/^http:\/\//i, "https://"));
  return Array.from(new Set(upgraded));
}

// Kept for backward compat with any other callers.
export function getBookTextUrl(book: Book): string | null {
  const urls = getBookTextUrls(book);
  return urls[0] ?? null;
}

export function cleanGutenbergText(text: string): string {
  // Strip license headers/footers
  const startIdx = text.search(/\*\*\* START OF/i);
  if (startIdx !== -1) {
    const endOfLine = text.indexOf("\n", startIdx);
    if (endOfLine !== -1) {
      text = text.substring(endOfLine + 1);
    }
  }

  const endIdx = text.search(/\*\*\* END OF/i);
  if (endIdx !== -1) {
    text = text.substring(0, endIdx);
  }

  // Collapse runs of 4+ blank lines into 3
  text = text.replace(/\n{4,}/g, "\n\n\n");

  return text.trim();
}

export async function fetchBookText(book: Book): Promise<string> {
  const urls = getBookTextUrls(book);
  if (urls.length === 0) {
    throw new Error("No readable plain-text format is available for this book.");
  }

  const errors: string[] = [];
  for (const url of urls) {
    try {
      const res = await fetch(url, { headers: REQUEST_HEADERS });
      if (!res.ok) {
        errors.push(`${url} -> HTTP ${res.status}`);
        continue;
      }
      const rawText = await res.text();
      if (!rawText || rawText.length < 100) {
        errors.push(`${url} -> empty body`);
        continue;
      }
      return cleanGutenbergText(rawText);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${url} -> ${message}`);
    }
  }

  throw new Error(
    `Failed to load any text source for "${book.title}". Tried: ${errors.join("; ")}`,
  );
}

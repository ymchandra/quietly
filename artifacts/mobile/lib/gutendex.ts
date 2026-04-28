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

  const res = await fetch(url.toString());
  if (!res.ok) throw new Error("Failed to fetch books");
  return res.json();
}

export async function fetchBook(id: number): Promise<Book> {
  const res = await fetch(`${API_BASE}/${id}`);
  if (!res.ok) throw new Error("Failed to fetch book");
  return res.json();
}

export function getBookCoverUrl(book: Book): string | null {
  return book.formats["image/jpeg"] || null;
}

export function getBookTextUrl(book: Book): string | null {
  // Prefer utf-8 plain text, then plain text, then html
  return (
    book.formats["text/plain; charset=utf-8"] ||
    book.formats["text/plain; charset=us-ascii"] ||
    book.formats["text/plain"] ||
    book.formats["text/html; charset=utf-8"] ||
    null
  );
}

export function cleanGutenbergText(text: string): string {
  // Strip license headers/footers
  let startIdx = text.search(/\*\*\* START OF/i);
  if (startIdx !== -1) {
    const endOfLine = text.indexOf('\n', startIdx);
    if (endOfLine !== -1) {
      text = text.substring(endOfLine + 1);
    }
  }

  let endIdx = text.search(/\*\*\* END OF/i);
  if (endIdx !== -1) {
    text = text.substring(0, endIdx);
  }

  // Collapse runs of 3+ blank lines into 2
  text = text.replace(/\n{4,}/g, '\n\n\n');

  return text.trim();
}

export async function fetchBookText(book: Book): Promise<string> {
  const url = getBookTextUrl(book);
  if (!url) throw new Error("No readable text format found for this book");
  
  // Follow redirects as gutendex urls often redirect to gutenberg.org
  const res = await fetch(url);
  if (!res.ok) throw new Error("Failed to fetch book text");
  
  const rawText = await res.text();
  return cleanGutenbergText(rawText);
}

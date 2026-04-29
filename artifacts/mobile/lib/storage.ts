import AsyncStorage from "@react-native-async-storage/async-storage";
import * as FileSystem from "expo-file-system";

const STORAGE_PREFIX = "@quietread:";

// --- AsyncStorage Helpers ---

export async function getItem<T>(key: string): Promise<T | null> {
  try {
    const value = await AsyncStorage.getItem(`${STORAGE_PREFIX}${key}`);
    return value ? JSON.parse(value) : null;
  } catch (error) {
    console.error(`[storage] Error getting item ${key}:`, error);
    return null;
  }
}

export async function setItem<T>(key: string, value: T): Promise<void> {
  try {
    await AsyncStorage.setItem(`${STORAGE_PREFIX}${key}`, JSON.stringify(value));
  } catch (error) {
    console.error(`[storage] Error setting item ${key}:`, error);
  }
}

export async function removeItem(key: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(`${STORAGE_PREFIX}${key}`);
  } catch (error) {
    console.error(`[storage] Error removing item ${key}:`, error);
  }
}

// --- FileSystem Helpers (Offline Reading) ---
//
// expo-file-system on web has no document directory. We treat that
// (and any other unexpected FS error) as "no offline copy available"
// so the reader falls through to the network instead of crashing.

const documentDirectory = FileSystem.documentDirectory ?? null;
const BOOKS_DIR = documentDirectory ? `${documentDirectory}books/` : null;

function bookFileUri(bookId: number): string | null {
  return BOOKS_DIR ? `${BOOKS_DIR}${bookId}.txt` : null;
}

export async function ensureBooksDirExists(): Promise<boolean> {
  if (!BOOKS_DIR) return false;
  try {
    const dirInfo = await FileSystem.getInfoAsync(BOOKS_DIR);
    if (!dirInfo.exists) {
      await FileSystem.makeDirectoryAsync(BOOKS_DIR, { intermediates: true });
    }
    return true;
  } catch (error) {
    console.warn("[storage] ensureBooksDirExists failed:", error);
    return false;
  }
}

export async function saveBookTextOffline(
  bookId: number,
  text: string,
): Promise<string | null> {
  const fileUri = bookFileUri(bookId);
  if (!fileUri) return null;
  try {
    const ready = await ensureBooksDirExists();
    if (!ready) return null;
    await FileSystem.writeAsStringAsync(fileUri, text, {
      encoding: FileSystem.EncodingType.UTF8,
    });
    return fileUri;
  } catch (error) {
    console.warn(`[storage] saveBookTextOffline(${bookId}) failed:`, error);
    return null;
  }
}

export async function getBookTextOffline(
  bookId: number,
): Promise<string | null> {
  const fileUri = bookFileUri(bookId);
  if (!fileUri) return null;
  try {
    const fileInfo = await FileSystem.getInfoAsync(fileUri);
    if (!fileInfo.exists) return null;
    return await FileSystem.readAsStringAsync(fileUri, {
      encoding: FileSystem.EncodingType.UTF8,
    });
  } catch (error) {
    console.warn(`[storage] getBookTextOffline(${bookId}) failed:`, error);
    return null;
  }
}

export async function removeBookTextOffline(bookId: number): Promise<void> {
  const fileUri = bookFileUri(bookId);
  if (!fileUri) return;
  try {
    const fileInfo = await FileSystem.getInfoAsync(fileUri);
    if (fileInfo.exists) {
      await FileSystem.deleteAsync(fileUri, { idempotent: true });
    }
  } catch (error) {
    console.warn(`[storage] removeBookTextOffline(${bookId}) failed:`, error);
  }
}

export async function checkOfflineBookExists(bookId: number): Promise<boolean> {
  const fileUri = bookFileUri(bookId);
  if (!fileUri) return false;
  try {
    const fileInfo = await FileSystem.getInfoAsync(fileUri);
    return fileInfo.exists;
  } catch {
    return false;
  }
}

import AsyncStorage from "@react-native-async-storage/async-storage";
import * as FileSystem from "expo-file-system";
import { Book } from "./gutendex";

const STORAGE_PREFIX = "@quietread:";

// --- AsyncStorage Helpers ---

export async function getItem<T>(key: string): Promise<T | null> {
  try {
    const value = await AsyncStorage.getItem(`${STORAGE_PREFIX}${key}`);
    return value ? JSON.parse(value) : null;
  } catch (error) {
    console.error(`Error getting item ${key}:`, error);
    return null;
  }
}

export async function setItem<T>(key: string, value: T): Promise<void> {
  try {
    await AsyncStorage.setItem(`${STORAGE_PREFIX}${key}`, JSON.stringify(value));
  } catch (error) {
    console.error(`Error setting item ${key}:`, error);
  }
}

export async function removeItem(key: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(`${STORAGE_PREFIX}${key}`);
  } catch (error) {
    console.error(`Error removing item ${key}:`, error);
  }
}

// --- FileSystem Helpers (Offline Reading) ---

const BOOKS_DIR = `${FileSystem.documentDirectory}books/`;

export async function ensureBooksDirExists() {
  const dirInfo = await FileSystem.getInfoAsync(BOOKS_DIR);
  if (!dirInfo.exists) {
    await FileSystem.makeDirectoryAsync(BOOKS_DIR, { intermediates: true });
  }
}

export async function saveBookTextOffline(bookId: number, text: string): Promise<string> {
  await ensureBooksDirExists();
  const fileUri = `${BOOKS_DIR}${bookId}.txt`;
  await FileSystem.writeAsStringAsync(fileUri, text, { encoding: FileSystem.EncodingType.UTF8 });
  return fileUri;
}

export async function getBookTextOffline(bookId: number): Promise<string | null> {
  const fileUri = `${BOOKS_DIR}${bookId}.txt`;
  const fileInfo = await FileSystem.getInfoAsync(fileUri);
  if (fileInfo.exists) {
    return await FileSystem.readAsStringAsync(fileUri, { encoding: FileSystem.EncodingType.UTF8 });
  }
  return null;
}

export async function removeBookTextOffline(bookId: number): Promise<void> {
  const fileUri = `${BOOKS_DIR}${bookId}.txt`;
  const fileInfo = await FileSystem.getInfoAsync(fileUri);
  if (fileInfo.exists) {
    await FileSystem.deleteAsync(fileUri, { idempotent: true });
  }
}

export async function checkOfflineBookExists(bookId: number): Promise<boolean> {
  const fileUri = `${BOOKS_DIR}${bookId}.txt`;
  const fileInfo = await FileSystem.getInfoAsync(fileUri);
  return fileInfo.exists;
}

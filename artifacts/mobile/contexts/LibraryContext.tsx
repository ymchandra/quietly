import React, { createContext, useContext, useEffect, useState, ReactNode, useMemo, useCallback } from 'react';
import { Book } from '../lib/gutendex';
import { getItem, setItem, saveBookTextOffline, removeBookTextOffline, checkOfflineBookExists } from '../lib/storage';
import * as Haptics from 'expo-haptics';

export interface Progress {
  percent: number;
  updatedAt: number;
}

interface LibraryContextValue {
  wishlist: Book[];
  readLater: Book[];
  downloaded: Book[];
  progress: Record<number, Progress>;
  addToWishlist: (book: Book) => void;
  removeFromWishlist: (id: number) => void;
  addToReadLater: (book: Book) => void;
  removeFromReadLater: (id: number) => void;
  saveOffline: (book: Book, textPromise: Promise<string>) => Promise<void>;
  removeOffline: (id: number) => Promise<void>;
  setProgress: (id: number, percent: number) => void;
  isReady: boolean;
}

const LibraryContext = createContext<LibraryContextValue | null>(null);

export function LibraryProvider({ children }: { children: ReactNode }) {
  const [wishlist, setWishlist] = useState<Book[]>([]);
  const [readLater, setReadLater] = useState<Book[]>([]);
  const [downloaded, setDownloaded] = useState<Book[]>([]);
  const [progress, setProgressState] = useState<Record<number, Progress>>({});
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    async function loadData() {
      const [w, r, d, p] = await Promise.all([
        getItem<Book[]>('wishlist'),
        getItem<Book[]>('readLater'),
        getItem<Book[]>('downloaded'),
        getItem<Record<number, Progress>>('progress'),
      ]);
      if (w) setWishlist(w);
      if (r) setReadLater(r);
      if (d) setDownloaded(d);
      if (p) setProgressState(p);
      setIsReady(true);
    }
    loadData();
  }, []);

  const saveState = useCallback(async () => {
    if (!isReady) return;
    await Promise.all([
      setItem('wishlist', wishlist),
      setItem('readLater', readLater),
      setItem('downloaded', downloaded),
      setItem('progress', progress),
    ]);
  }, [wishlist, readLater, downloaded, progress, isReady]);

  useEffect(() => {
    saveState();
  }, [saveState]);

  const addToWishlist = useCallback((book: Book) => {
    setWishlist(prev => {
      if (prev.some(b => b.id === book.id)) return prev;
      return [book, ...prev];
    });
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const removeFromWishlist = useCallback((id: number) => {
    setWishlist(prev => prev.filter(b => b.id !== id));
  }, []);

  const addToReadLater = useCallback((book: Book) => {
    setReadLater(prev => {
      if (prev.some(b => b.id === book.id)) return prev;
      return [book, ...prev];
    });
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const removeFromReadLater = useCallback((id: number) => {
    setReadLater(prev => prev.filter(b => b.id !== id));
  }, []);

  const saveOffline = useCallback(async (book: Book, textPromise: Promise<string>) => {
    try {
      const text = await textPromise;
      await saveBookTextOffline(book.id, text);
      setDownloaded(prev => {
        if (prev.some(b => b.id === book.id)) return prev;
        return [book, ...prev];
      });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch (e) {
      console.error('Failed to save offline:', e);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      throw e;
    }
  }, []);

  const removeOffline = useCallback(async (id: number) => {
    await removeBookTextOffline(id);
    setDownloaded(prev => prev.filter(b => b.id !== id));
  }, []);

  const setProgress = useCallback((id: number, percent: number) => {
    setProgressState(prev => ({
      ...prev,
      [id]: { percent, updatedAt: Date.now() }
    }));
  }, []);

  const value = useMemo(() => ({
    wishlist,
    readLater,
    downloaded,
    progress,
    addToWishlist,
    removeFromWishlist,
    addToReadLater,
    removeFromReadLater,
    saveOffline,
    removeOffline,
    setProgress,
    isReady
  }), [wishlist, readLater, downloaded, progress, addToWishlist, removeFromWishlist, addToReadLater, removeFromReadLater, saveOffline, removeOffline, setProgress, isReady]);

  return (
    <LibraryContext.Provider value={value}>
      {children}
    </LibraryContext.Provider>
  );
}

export function useLibrary() {
  const context = useContext(LibraryContext);
  if (!context) throw new Error('useLibrary must be used within LibraryProvider');
  return context;
}

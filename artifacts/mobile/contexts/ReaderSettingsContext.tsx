import React, { createContext, useContext, useEffect, useState, ReactNode, useMemo, useCallback } from 'react';
import { getItem, setItem } from '../lib/storage';
import * as Haptics from 'expo-haptics';

export type ThemeName = 'Cream' | 'Paper' | 'Sepia' | 'Slate' | 'Midnight';
export type FontFamily = 'Lora' | 'Inter';
export type LineHeight = 'Compact' | 'Comfortable' | 'Airy';

export interface ReaderSettings {
  theme: ThemeName;
  fontFamily: FontFamily;
  fontSize: number;
  lineHeight: LineHeight;
}

export interface ReaderSettingsState {
  global: ReaderSettings;
  perBook: Record<number, Partial<ReaderSettings>>;
}

const DEFAULT_SETTINGS: ReaderSettings = {
  theme: 'Cream',
  fontFamily: 'Lora',
  fontSize: 18,
  lineHeight: 'Comfortable',
};

interface ReaderSettingsContextValue {
  settings: ReaderSettingsState;
  updateGlobalSettings: (newSettings: Partial<ReaderSettings>) => void;
  updateBookSettings: (bookId: number, newSettings: Partial<ReaderSettings>) => void;
  getEffectiveSettings: (bookId?: number) => ReaderSettings;
  isReady: boolean;
}

const ReaderSettingsContext = createContext<ReaderSettingsContextValue | null>(null);

export function ReaderSettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<ReaderSettingsState>({ global: DEFAULT_SETTINGS, perBook: {} });
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    async function loadSettings() {
      const stored = await getItem<ReaderSettingsState>('readerSettings');
      if (stored) {
        setSettings({
          global: { ...DEFAULT_SETTINGS, ...stored.global },
          perBook: stored.perBook || {},
        });
      }
      setIsReady(true);
    }
    loadSettings();
  }, []);

  useEffect(() => {
    if (isReady) {
      setItem('readerSettings', settings);
    }
  }, [settings, isReady]);

  const updateGlobalSettings = useCallback((newSettings: Partial<ReaderSettings>) => {
    setSettings(prev => ({
      ...prev,
      global: { ...prev.global, ...newSettings }
    }));
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const updateBookSettings = useCallback((bookId: number, newSettings: Partial<ReaderSettings>) => {
    setSettings(prev => ({
      ...prev,
      perBook: {
        ...prev.perBook,
        [bookId]: { ...(prev.perBook[bookId] || {}), ...newSettings }
      }
    }));
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const getEffectiveSettings = useCallback((bookId?: number) => {
    if (!bookId) return settings.global;
    return { ...settings.global, ...(settings.perBook[bookId] || {}) };
  }, [settings]);

  const value = useMemo(() => ({
    settings,
    updateGlobalSettings,
    updateBookSettings,
    getEffectiveSettings,
    isReady
  }), [settings, updateGlobalSettings, updateBookSettings, getEffectiveSettings, isReady]);

  return (
    <ReaderSettingsContext.Provider value={value}>
      {children}
    </ReaderSettingsContext.Provider>
  );
}

export function useReaderSettings() {
  const context = useContext(ReaderSettingsContext);
  if (!context) throw new Error('useReaderSettings must be used within ReaderSettingsProvider');
  return context;
}

export const THEMES: Record<ThemeName, { bg: string; text: string; accent: string }> = {
  Cream: { bg: '#F7F1E3', text: '#2A2622', accent: '#B8865A' },
  Paper: { bg: '#F4EFE6', text: '#1F1B17', accent: '#A67C52' },
  Sepia: { bg: '#E8D9B8', text: '#3B2E1F', accent: '#8F6636' },
  Slate: { bg: '#2B2D31', text: '#DCD3C2', accent: '#8F9CA6' },
  Midnight: { bg: '#0F1419', text: '#B8B0A4', accent: '#6B7280' },
};

export const LINE_HEIGHTS: Record<LineHeight, number> = {
  Compact: 1.4,
  Comfortable: 1.65,
  Airy: 1.9,
};

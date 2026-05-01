import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import {
  View,
  StyleSheet,
  FlatList,
  Text,
  ActivityIndicator,
  Pressable,
  NativeSyntheticEvent,
  NativeScrollEvent,
  ListRenderItemInfo,
} from 'react-native';
import { useLocalSearchParams, Stack, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { fetchBook, fetchBookText } from '@/lib/gutendex';
import { getBookTextOffline } from '@/lib/storage';
import { useLibrary } from '@/contexts/LibraryContext';
import { useReaderSettings, THEMES, LINE_HEIGHTS } from '@/contexts/ReaderSettingsContext';
import { ReaderControls } from '@/components/ReaderControls';
import { EmptyState } from '@/components/EmptyState';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// Split full text into chunks that are safe to render as individual <Text>
// elements. React Native on Android has a hard ~64 KB limit per <Text>
// element and silently renders blank past that. Splitting on blank lines
// keeps paragraph boundaries intact.
// IMPORTANT: must be declared before any conditional returns (Rules of Hooks).
function splitTextIntoChunks(text: string | undefined): string[] {
  if (!text) return [];
  const MAX_CHUNK = 8000;
  const paragraphs = text.split(/\n{2,}/);
  const chunks: string[] = [];
  let buf = '';
  for (const p of paragraphs) {
    const piece = p.trim();
    if (!piece) continue;
    if (buf.length + piece.length + 2 > MAX_CHUNK && buf.length > 0) {
      chunks.push(buf);
      buf = '';
    }
    if (piece.length > MAX_CHUNK) {
      if (buf) { chunks.push(buf); buf = ''; }
      for (let i = 0; i < piece.length; i += MAX_CHUNK) {
        chunks.push(piece.slice(i, i + MAX_CHUNK));
      }
      continue;
    }
    buf = buf ? `${buf}\n\n${piece}` : piece;
  }
  if (buf) chunks.push(buf);
  return chunks;
}

export default function ReaderScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const bookId = Number(id);

  const router = useRouter();
  const { progress, setProgress } = useLibrary();
  const { getEffectiveSettings } = useReaderSettings();
  const settings = getEffectiveSettings(bookId);
  const themeColors = THEMES[settings.theme];
  const insets = useSafeAreaInsets();

  // ── All hooks must appear before any conditional return ──────────────────

  const [controlsVisible, setControlsVisible] = useState(false);
  const controlsTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const flatListRef = useRef<FlatList>(null);
  const touchStartY = useRef(0);
  const savedPercent = progress[bookId]?.percent || 0;

  // 1. Fetch text (offline first, then network).
  const { data: text, isLoading, error } = useQuery({
    queryKey: ['bookText', bookId],
    queryFn: async () => {
      let offlineText: string | null = null;
      try {
        offlineText = await getBookTextOffline(bookId);
      } catch (offlineErr) {
        console.warn('[reader] offline read failed, falling back to network:', offlineErr);
      }
      if (offlineText) return offlineText;

      try {
        const book = await fetchBook(bookId);
        return await fetchBookText(book);
      } catch (networkErr) {
        console.error('[reader] failed to load book text:', networkErr);
        throw networkErr;
      }
    },
    retry: 1,
    staleTime: Infinity,
  });

  // 2. Split text into renderable chunks (must be before early returns).
  const textChunks = useMemo(() => splitTextIntoChunks(text), [text]);

  // 3. Controls auto-hide.
  const toggleControls = useCallback(() => {
    setControlsVisible(prev => {
      const next = !prev;
      if (next) {
        if (controlsTimeoutRef.current) clearTimeout(controlsTimeoutRef.current);
        controlsTimeoutRef.current = setTimeout(() => setControlsVisible(false), 3000);
      }
      return next;
    });
  }, []);

  useEffect(() => {
    if (controlsVisible) {
      if (controlsTimeoutRef.current) clearTimeout(controlsTimeoutRef.current);
      controlsTimeoutRef.current = setTimeout(() => setControlsVisible(false), 3000);
    }
    return () => {
      if (controlsTimeoutRef.current) clearTimeout(controlsTimeoutRef.current);
    };
  }, [controlsVisible]);

  // 4. Scroll tracking — saved every 100 ms to avoid flooding state.
  const handleScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const { contentOffset, contentSize, layoutMeasurement } = event.nativeEvent;
      if (controlsVisible) setControlsVisible(false);
      const maxOffset = contentSize.height - layoutMeasurement.height;
      if (maxOffset <= 0) return;
      const pct = Math.max(0, Math.min(100, (contentOffset.y / maxOffset) * 100));
      setProgress(bookId, pct);
    },
    [bookId, setProgress, controlsVisible],
  );

  // 5. Restore saved position once the content is tall enough to scroll.
  const hasRestoredScroll = useRef(false);
  const handleContentSizeChange = useCallback(
    (w: number, h: number) => {
      if (!hasRestoredScroll.current && h > 0 && flatListRef.current && savedPercent > 0) {
        const layoutHeight = insets.top + insets.bottom + 800;
        const maxOffset = h - layoutHeight;
        if (maxOffset > 0) {
          flatListRef.current.scrollToOffset({
            offset: (savedPercent / 100) * maxOffset,
            animated: false,
          });
        }
        hasRestoredScroll.current = true;
      }
    },
    [savedPercent, insets],
  );

  // 6. Render a single text chunk.  Defined here (not inline) so the function
  //    reference is stable across re-renders and FlatList doesn't re-render
  //    every visible item when unrelated state changes.
  const fontFamily = settings.fontFamily === 'Lora' ? 'Lora_400Regular' : 'Inter_400Regular';
  const lineHeight = Math.round(settings.fontSize * LINE_HEIGHTS[settings.lineHeight]);

  const renderChunk = useCallback(
    ({ item }: ListRenderItemInfo<string>) => (
      <Text
        style={[
          styles.text,
          styles.paragraph,
          {
            color: themeColors.text,
            fontFamily,
            fontSize: settings.fontSize,
            lineHeight,
          },
        ]}
        selectable
      >
        {item}
      </Text>
    ),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [themeColors.text, fontFamily, settings.fontSize, lineHeight],
  );

  // ── Conditional returns (after all hooks) ────────────────────────────────

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: themeColors.bg }]}>
        <Stack.Screen options={{ headerShown: false }} />
        <View style={styles.center}>
          <ActivityIndicator size="large" color={themeColors.text} />
        </View>
      </View>
    );
  }

  if (error || !text) {
    return (
      <View style={[styles.container, { backgroundColor: themeColors.bg }]}>
        <Stack.Screen options={{ headerShown: false }} />
        <ReaderControls
          visible={true}
          theme={settings.theme}
          percent={0}
          onSettingsPress={() => router.push(`/reader/settings/${bookId}`)}
        />
        <EmptyState
          icon="alert-circle"
          title="Couldn't load text"
          subtitle={
            error instanceof Error
              ? error.message
              : 'There was an error loading the book content. Please try again.'
          }
        />
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: themeColors.bg }]}>
      <Stack.Screen options={{ headerShown: false }} />

      {/*
        FlatList virtualises the text chunks so only what is currently
        visible (plus a small buffer) is mounted. A plain ScrollView +
        map renders every chunk immediately, which on a full-length book
        (200–500 chunks) causes a significant initial-render stall and
        wastes memory. Using FlatList reduces first-paint time and keeps
        scrolling smooth throughout the book.

        Tap detection: we track touchStart/touchEnd Y-delta ourselves
        because FlatList intercepts press events. If the finger moves
        less than 8 px it is treated as a tap → toggle controls.
      */}
      <FlatList
        ref={flatListRef}
        data={textChunks}
        keyExtractor={(_, i) => i.toString()}
        renderItem={renderChunk}
        contentContainerStyle={[
          styles.scrollContent,
          {
            paddingTop: Math.max(insets.top, 40),
            paddingBottom: Math.max(insets.bottom, 60),
          },
        ]}
        onScroll={handleScroll}
        scrollEventThrottle={100}
        onContentSizeChange={handleContentSizeChange}
        initialNumToRender={12}
        maxToRenderPerBatch={8}
        windowSize={5}
        removeClippedSubviews
        // Tap detection without blocking scroll
        onTouchStart={(e) => { touchStartY.current = e.nativeEvent.pageY; }}
        onTouchEnd={(e) => {
          if (Math.abs(e.nativeEvent.pageY - touchStartY.current) < 8) {
            toggleControls();
          }
        }}
      />

      <ReaderControls
        visible={controlsVisible}
        theme={settings.theme}
        percent={savedPercent}
        onSettingsPress={() => {
          setControlsVisible(false);
          router.push(`/reader/settings/${bookId}`);
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  scrollContent: {
    paddingHorizontal: 24,
  },
  text: {
    textAlign: 'left',
  },
  paragraph: {
    marginBottom: 12,
  },
});

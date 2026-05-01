import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import {
  View,
  StyleSheet,
  FlatList,
  Text,
  ActivityIndicator,
  NativeSyntheticEvent,
  NativeScrollEvent,
  ListRenderItemInfo,
  useWindowDimensions,
  Pressable,
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

// Average character width as a fraction of font size.
// Derived empirically for both Lora and Inter at typical reading sizes;
// Inter is slightly narrower but the difference is within the 0.85 safety
// factor applied later, so a single value works for both.
const CHAR_WIDTH_RATIO = 0.52;

// Safety factor applied to the theoretical chars-per-page estimate to
// give breathing room for paragraph breaks and variable-width characters.
const PAGE_FILL_FACTOR = 0.85;

// Minimum characters per page regardless of screen/font settings, so very
// small screens or very large font sizes always show a usable amount of text.
const MIN_CHARS_PER_PAGE = 300;

// Split full text into pages sized to fill one screen at the current
// typography settings. charsPerPage is pre-calculated by the caller based
// on screen dimensions and font size/line-height so each page looks like a
// real book page.
// IMPORTANT: must be declared before any conditional returns (Rules of Hooks).
function splitTextIntoPages(text: string | undefined, charsPerPage: number): string[] {
  if (!text) return [];
  const paragraphs = text.split(/\n{2,}/);
  const pages: string[] = [];
  let current = '';
  for (const p of paragraphs) {
    const piece = p.trim();
    if (!piece) continue;

    // Paragraph fits alongside current accumulator → keep appending.
    if (current.length + piece.length + 2 <= charsPerPage) {
      current = current ? `${current}\n\n${piece}` : piece;
      continue;
    }

    // Flush the current page before handling this paragraph.
    if (current.length > 0) {
      pages.push(current);
      current = '';
    }

    // Paragraph is smaller than a full page → start a fresh page with it.
    if (piece.length <= charsPerPage) {
      current = piece;
      continue;
    }

    // Paragraph exceeds a full page → split it into page-sized slices.
    // We split on word boundaries where possible to avoid mid-word breaks.
    let remaining = piece;
    while (remaining.length > charsPerPage) {
      let splitAt = charsPerPage;
      // Walk back to the nearest space so we don't break a word.
      while (splitAt > 0 && remaining[splitAt] !== ' ') splitAt--;
      if (splitAt === 0) splitAt = charsPerPage; // no space found – hard split
      pages.push(remaining.slice(0, splitAt).trim());
      remaining = remaining.slice(splitAt).trim();
    }
    if (remaining.length > 0) current = remaining;
  }
  if (current) pages.push(current);
  return pages;
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
  const { width, height } = useWindowDimensions();

  // ── All hooks must appear before any conditional return ──────────────────

  const [controlsVisible, setControlsVisible] = useState(false);
  const [currentPage, setCurrentPage] = useState(0);
  const controlsTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const flatListRef = useRef<FlatList>(null);
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

  // 2. Typography helpers (needed for page-size calculation below).
  const fontFamily = settings.fontFamily === 'Lora' ? 'Lora_400Regular' : 'Inter_400Regular';
  const lineHeight = Math.round(settings.fontSize * LINE_HEIGHTS[settings.lineHeight]);

  // 3. Estimate how many characters fit on a single screen page.
  //    The formula approximates: chars-per-line × lines-per-page.
  //    A 0.85 factor gives breathing room for paragraph gaps and
  //    variable character widths.
  const charsPerPage = useMemo(() => {
    const paddingTop = Math.max(insets.top, 40);
    const paddingBottom = Math.max(insets.bottom, 60);
    const textHeight = height - paddingTop - paddingBottom;
    const textWidth = width - 48; // 24 px horizontal padding each side
    const charsPerLine = Math.floor(textWidth / (settings.fontSize * CHAR_WIDTH_RATIO));
    const linesPerPage = Math.floor(textHeight / lineHeight);
    return Math.max(MIN_CHARS_PER_PAGE, Math.floor(charsPerLine * linesPerPage * PAGE_FILL_FACTOR));
  }, [height, width, settings.fontSize, lineHeight, insets.top, insets.bottom]);

  // 4. Split text into screen-sized pages (must be before early returns).
  const pages = useMemo(() => splitTextIntoPages(text, charsPerPage), [text, charsPerPage]);

  // 5. Derive the initial page from the saved reading position.
  const initialPage = useMemo(() => {
    if (savedPercent <= 0 || pages.length <= 1) return 0;
    return Math.min(pages.length - 1, Math.round((savedPercent / 100) * (pages.length - 1)));
  }, [savedPercent, pages.length]);

  // 6. Once pages are available, jump to the saved page and sync state.
  const hasRestoredPage = useRef(false);
  useEffect(() => {
    if (!hasRestoredPage.current && pages.length > 0) {
      hasRestoredPage.current = true;
      setCurrentPage(initialPage);
    }
  }, [pages.length, initialPage]);

  // 7. Controls auto-hide.
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

  // 8. Page-change tracking — fires after each swipe animation completes.
  const handleMomentumScrollEnd = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const pageIndex = Math.round(event.nativeEvent.contentOffset.x / width);
      const clampedPage = Math.max(0, Math.min(pages.length - 1, pageIndex));
      setCurrentPage(clampedPage);
      if (controlsVisible) setControlsVisible(false);
      const pct = pages.length > 1 ? (clampedPage / (pages.length - 1)) * 100 : 100;
      setProgress(bookId, pct);
    },
    [bookId, setProgress, pages.length, width, controlsVisible],
  );

  // 9. getItemLayout lets FlatList know each page is exactly `width` wide so
  //    initialScrollIndex works without a layout pass.
  const getItemLayout = useCallback(
    (_: unknown, index: number) => ({ length: width, offset: width * index, index }),
    [width],
  );

  // 10. Render a single page.  Stable reference so FlatList doesn't re-render
  //     every visible item on unrelated state changes.
  //     Each page is given an explicit width AND height so that in a horizontal
  //     FlatList the cross-axis dimension fills the screen — relying on flex:1
  //     alone is not reliable for items in a horizontal scroll view.
  const renderPage = useCallback(
    ({ item }: ListRenderItemInfo<string>) => (
      <Pressable
        style={[
          styles.page,
          {
            width,
            height,
            paddingTop: Math.max(insets.top, 40),
            paddingBottom: Math.max(insets.bottom, 60),
          },
        ]}
        onPress={toggleControls}
      >
        <Text
          style={[
            styles.text,
            {
              color: themeColors.text,
              fontFamily,
              fontSize: settings.fontSize,
              lineHeight,
            },
          ]}
          selectable={false}
        >
          {item}
        </Text>
      </Pressable>
    ),
    [width, height, insets.top, insets.bottom, themeColors.text, fontFamily, settings.fontSize, lineHeight, toggleControls],
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

  const percent = pages.length > 1 ? (currentPage / (pages.length - 1)) * 100 : 100;

  return (
    <View style={[styles.container, { backgroundColor: themeColors.bg }]}>
      <Stack.Screen options={{ headerShown: false }} />

      {/*
        Horizontal FlatList with pagingEnabled turns the reader into a
        book-like page-swiping experience. Each item is exactly `width`
        wide and `height` tall so the list snaps to a full page on every
        swipe.

        getItemLayout is required for initialScrollIndex to work without
        a layout pass (restores saved reading position instantly).

        Tap to toggle controls is handled by the Pressable wrapper inside
        each page item, which avoids conflicts with the horizontal swipe
        gesture on the new React Native architecture.

        removeClippedSubviews is intentionally omitted — it can cause
        blank pages when combined with pagingEnabled.
      */}
      <FlatList
        ref={flatListRef}
        data={pages}
        keyExtractor={(_, i) => i.toString()}
        renderItem={renderPage}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        bounces={false}
        decelerationRate="fast"
        getItemLayout={getItemLayout}
        initialScrollIndex={initialPage}
        onMomentumScrollEnd={handleMomentumScrollEnd}
        initialNumToRender={3}
        maxToRenderPerBatch={3}
        windowSize={5}
        style={styles.flatList}
      />

      <ReaderControls
        visible={controlsVisible}
        theme={settings.theme}
        percent={percent}
        currentPage={currentPage + 1}
        totalPages={pages.length}
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
  flatList: {
    flex: 1,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  page: {
    paddingHorizontal: 24,
    overflow: 'hidden',
  },
  text: {
    textAlign: 'left',
  },
});

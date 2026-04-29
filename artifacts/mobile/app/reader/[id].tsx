import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { View, StyleSheet, ScrollView, Text, ActivityIndicator, Pressable, NativeSyntheticEvent, NativeScrollEvent } from 'react-native';
import { useLocalSearchParams, Stack, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { fetchBook, fetchBookText } from '@/lib/gutendex';
import { getBookTextOffline } from '@/lib/storage';
import { useLibrary } from '@/contexts/LibraryContext';
import { useReaderSettings, THEMES, LINE_HEIGHTS } from '@/contexts/ReaderSettingsContext';
import { ReaderControls } from '@/components/ReaderControls';
import { EmptyState } from '@/components/EmptyState';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

export default function ReaderScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const bookId = Number(id);
  
  const router = useRouter();
  const { progress, setProgress } = useLibrary();
  const { getEffectiveSettings } = useReaderSettings();
  const settings = getEffectiveSettings(bookId);
  const themeColors = THEMES[settings.theme];
  const insets = useSafeAreaInsets();

  const [controlsVisible, setControlsVisible] = useState(false);
  const controlsTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const scrollViewRef = useRef<ScrollView>(null);
  
  const savedPercent = progress[bookId]?.percent || 0;

  // 1. Fetch text (offline first, then network).
  // The offline check is wrapped so a FileSystem error can never block the
  // network fallback — the reader should always try the network if there is
  // no usable offline copy.
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
        // Surface the real cause in the dev console so this is debuggable.
        console.error('[reader] failed to load book text:', networkErr);
        throw networkErr;
      }
    },
    retry: 1,
    staleTime: Infinity,
  });

  // Controls auto-hide
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

  // Scroll tracking
  const handleScroll = useCallback((event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const { contentOffset, contentSize, layoutMeasurement } = event.nativeEvent;
    
    // Hide controls on scroll
    if (controlsVisible) setControlsVisible(false);

    // Calculate percent
    const currentOffset = contentOffset.y;
    const maxOffset = contentSize.height - layoutMeasurement.height;
    
    if (maxOffset <= 0) return; // Cannot scroll
    
    let currentPercent = (currentOffset / maxOffset) * 100;
    currentPercent = Math.max(0, Math.min(100, currentPercent));
    
    // Debounce save
    setProgress(bookId, currentPercent);
  }, [bookId, setProgress, controlsVisible]);

  // Initial scroll restore
  const hasRestoredScroll = useRef(false);
  const handleContentSizeChange = useCallback((w: number, h: number) => {
    if (!hasRestoredScroll.current && h > 0 && scrollViewRef.current && savedPercent > 0) {
      const layoutHeight = insets.top + insets.bottom + 800; // rough est
      const maxOffset = h - layoutHeight;
      if (maxOffset > 0) {
        scrollViewRef.current.scrollTo({
          y: (savedPercent / 100) * maxOffset,
          animated: false,
        });
      }
      hasRestoredScroll.current = true;
    }
  }, [savedPercent, insets]);

  // React Native's <Text> on Android has a hard limit of ~64KB per
  // element (it silently renders blank past that). Most Gutenberg
  // books are well over that, so we split the body into chunks and
  // render each as its own <Text>. Splitting on blank lines keeps
  // paragraph boundaries intact.
  //
  // IMPORTANT: this hook MUST be declared before any early returns to
  // satisfy the Rules of Hooks (the previous render path included
  // it conditionally, which crashed React with a hooks-mismatch).
  const textChunks = useMemo(() => {
    if (!text) return [] as string[];
    const MAX_CHUNK = 8000; // chars; keeps each <Text> well under any limit
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
      // A single paragraph longer than MAX_CHUNK still needs splitting.
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
  }, [text]);

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

  const fontFamily = settings.fontFamily === 'Lora' ? 'Lora_400Regular' : 'Inter_400Regular';
  const lineHeight = Math.round(settings.fontSize * LINE_HEIGHTS[settings.lineHeight]);

  return (
    <View style={[styles.container, { backgroundColor: themeColors.bg }]}>
      <Stack.Screen options={{ headerShown: false }} />
      
      <ScrollView
        ref={scrollViewRef}
        contentContainerStyle={[
          styles.scrollContent,
          { paddingTop: Math.max(insets.top, 40), paddingBottom: Math.max(insets.bottom, 60) }
        ]}
        onScroll={handleScroll}
        scrollEventThrottle={100}
        onContentSizeChange={handleContentSizeChange}
      >
        <Pressable onPress={toggleControls} style={styles.textContainer}>
          {textChunks.map((chunk, i) => (
            <Text
              key={i}
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
              selectable={true}
            >
              {chunk}
            </Text>
          ))}
        </Pressable>
      </ScrollView>

      <ReaderControls 
        visible={controlsVisible} 
        theme={settings.theme} 
        percent={savedPercent} 
        onSettingsPress={() => {
          setControlsVisible(false);
          // Navigate to a transparent modal or just toggle a local state for the sheet
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
  textContainer: {
    flex: 1,
  },
  text: {
    textAlign: 'left',
  },
  paragraph: {
    marginBottom: 12,
  },
});

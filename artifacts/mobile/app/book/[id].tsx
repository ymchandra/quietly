import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, Pressable, Alert } from 'react-native';
import { useLocalSearchParams, router, Stack } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { Image } from 'expo-image';
import { Feather } from '@expo/vector-icons';
import { useColors } from '@/hooks/useColors';
import { useLibrary } from '@/contexts/LibraryContext';
import { fetchBook, getBookCoverUrl, fetchBookText } from '@/lib/gutendex';
import { Chip } from '@/components/Chip';
import { Skeleton } from '@/components/Skeleton';
import { EmptyState } from '@/components/EmptyState';
import * as Haptics from 'expo-haptics';

export default function BookDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const bookId = Number(id);
  const colors = useColors();
  
  const { 
    wishlist, readLater, downloaded, 
    addToWishlist, removeFromWishlist, 
    addToReadLater, removeFromReadLater,
    saveOffline, removeOffline
  } = useLibrary();

  const isWishlisted = wishlist.some(b => b.id === bookId);
  const isReadLater = readLater.some(b => b.id === bookId);
  const isDownloaded = downloaded.some(b => b.id === bookId);

  const [isDownloading, setIsDownloading] = useState(false);

  const { data: book, isLoading, error } = useQuery({
    queryKey: ['book', bookId],
    queryFn: () => fetchBook(bookId),
  });

  const handleRead = () => {
    router.push(`/reader/${bookId}`);
  };

  const handleDownloadToggle = async () => {
    if (!book) return;
    
    if (isDownloaded) {
      Alert.alert(
        "Remove Download",
        `Remove "${book.title}" from offline storage?`,
        [
          { text: "Cancel", style: "cancel" },
          { 
            text: "Remove", 
            style: "destructive", 
            onPress: () => removeOffline(bookId) 
          }
        ]
      );
    } else {
      try {
        setIsDownloading(true);
        const textPromise = fetchBookText(book);
        await saveOffline(book, textPromise);
      } catch (e) {
        Alert.alert("Download Failed", "Could not download the book text.");
      } finally {
        setIsDownloading(false);
      }
    }
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <Stack.Screen options={{ title: '', headerShadowVisible: false, headerStyle: { backgroundColor: colors.background } }} />
        <View style={styles.content}>
          <View style={styles.header}>
            <Skeleton width={140} height={210} borderRadius={8} />
            <View style={styles.headerInfo}>
              <Skeleton width="100%" height={24} />
              <Skeleton width="80%" height={24} />
              <Skeleton width="60%" height={16} style={{ marginTop: 8 }} />
            </View>
          </View>
        </View>
      </View>
    );
  }

  if (error || !book) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <Stack.Screen options={{ title: 'Error' }} />
        <EmptyState 
          icon="alert-circle" 
          title="Couldn't load book" 
          subtitle="There was an error loading the book details. Please try again."
        />
      </View>
    );
  }

  const coverUrl = getBookCoverUrl(book);
  const authorName = book.authors?.[0]?.name?.split(',').reverse().join(' ').trim() || 'Unknown Author';

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Stack.Screen 
        options={{ 
          title: '', 
          headerShadowVisible: false, 
          headerStyle: { backgroundColor: colors.background },
          headerRight: () => (
            <View style={styles.headerActions}>
              <Pressable 
                style={styles.headerBtn}
                onPress={() => {
                  if (isReadLater) removeFromReadLater(bookId);
                  else if (book) addToReadLater(book);
                }}
              >
                <Feather name="clock" size={24} color={isReadLater ? colors.primary : colors.foreground} />
              </Pressable>
              <Pressable 
                style={styles.headerBtn}
                onPress={() => {
                  if (isWishlisted) removeFromWishlist(bookId);
                  else if (book) addToWishlist(book);
                }}
              >
                <Feather name="heart" size={24} color={isWishlisted ? colors.destructive : colors.foreground} style={isWishlisted ? { fill: colors.destructive } : undefined} />
              </Pressable>
            </View>
          )
        }} 
      />
      
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <View style={styles.header}>
          <View style={[styles.coverContainer, { backgroundColor: colors.muted, borderRadius: colors.radius }]}>
            {coverUrl ? (
              <Image 
                source={{ uri: coverUrl }} 
                style={styles.cover} 
                contentFit="cover"
                transition={200}
                cachePolicy="memory-disk"
              />
            ) : (
              <View style={styles.textCover}>
                <Text style={[styles.textCoverTitle, { color: colors.mutedForeground }]}>{book.title}</Text>
              </View>
            )}
          </View>
          
          <View style={styles.headerInfo}>
            <Text style={[styles.title, { color: colors.foreground }]}>{book.title}</Text>
            <Text style={[styles.author, { color: colors.mutedForeground }]}>{authorName}</Text>
            <Text style={[styles.downloads, { color: colors.mutedForeground }]}>
              <Feather name="download" size={12} /> {book.download_count.toLocaleString()} downloads
            </Text>
          </View>
        </View>

        <View style={styles.actions}>
          <Pressable 
            style={[styles.primaryBtn, { backgroundColor: colors.foreground, borderRadius: colors.radius }]}
            onPress={handleRead}
          >
            <Text style={[styles.primaryBtnText, { color: colors.background }]}>Read</Text>
          </Pressable>

          <Pressable 
            style={[styles.secondaryBtn, { backgroundColor: isDownloaded ? colors.primary + '1A' : colors.muted, borderRadius: colors.radius }]}
            onPress={handleDownloadToggle}
            disabled={isDownloading}
          >
            <Feather name={isDownloaded ? "check" : "download-cloud"} size={18} color={isDownloaded ? colors.primary : colors.foreground} />
            <Text style={[styles.secondaryBtnText, { color: isDownloaded ? colors.primary : colors.foreground }]}>
              {isDownloading ? "Downloading..." : isDownloaded ? "Saved offline" : "Save offline"}
            </Text>
          </Pressable>
        </View>

        {book.subjects && book.subjects.length > 0 && (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Subjects</Text>
            <View style={styles.chipContainer}>
              {book.subjects.map(subject => (
                <Chip key={subject} label={subject} />
              ))}
            </View>
          </View>
        )}

        {book.bookshelves && book.bookshelves.length > 0 && (
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Bookshelves</Text>
            <View style={styles.chipContainer}>
              {book.bookshelves.map(shelf => (
                <Chip key={shelf} label={shelf.replace('Browsing: ', '')} />
              ))}
            </View>
          </View>
        )}

      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 24,
  },
  scrollContent: {
    padding: 24,
    paddingBottom: 100,
  },
  headerActions: {
    flexDirection: 'row',
    gap: 8,
  },
  headerBtn: {
    padding: 8,
  },
  header: {
    flexDirection: 'row',
    gap: 20,
    marginBottom: 32,
  },
  coverContainer: {
    width: 140,
    height: 210,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(0,0,0,0.05)',
  },
  cover: {
    width: '100%',
    height: '100%',
  },
  textCover: {
    flex: 1,
    padding: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textCoverTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 16,
    textAlign: 'center',
  },
  headerInfo: {
    flex: 1,
    paddingTop: 8,
  },
  title: {
    fontFamily: 'Lora_700Bold',
    fontSize: 22,
    lineHeight: 28,
    marginBottom: 8,
  },
  author: {
    fontFamily: 'Inter_500Medium',
    fontSize: 16,
    marginBottom: 12,
  },
  downloads: {
    fontFamily: 'Inter_400Regular',
    fontSize: 12,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 32,
  },
  primaryBtn: {
    flex: 1,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryBtnText: {
    fontFamily: 'Inter_600SemiBold',
    fontSize: 16,
  },
  secondaryBtn: {
    flex: 1,
    height: 48,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  secondaryBtnText: {
    fontFamily: 'Inter_600SemiBold',
    fontSize: 14,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 18,
    marginBottom: 12,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  }
});

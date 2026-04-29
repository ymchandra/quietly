import React from 'react';
import { View, Text, StyleSheet, Pressable, ViewStyle } from 'react-native';
import { Image } from 'expo-image';
import { Link } from 'expo-router';
import { Book, getBookCoverUrl } from '@/lib/gutendex';
import { useColors } from '@/hooks/useColors';

interface BookCardProps {
  book: Book;
  style?: ViewStyle;
}

function BookCardImpl({ book, style }: BookCardProps) {
  const colors = useColors();
  const coverUrl = getBookCoverUrl(book);
  const authorName = book.authors?.[0]?.name?.split(',').reverse().join(' ').trim() || 'Unknown Author';

  return (
    <Link href={`/book/${book.id}`} asChild>
      <Pressable style={({ pressed }) => [styles.container, style, pressed && { opacity: 0.8 }]}>
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
              <Text style={[styles.textCoverTitle, { color: colors.mutedForeground }]} numberOfLines={3}>
                {book.title}
              </Text>
            </View>
          )}
        </View>
        <View style={styles.info}>
          <Text style={[styles.title, { color: colors.foreground }]} numberOfLines={2}>{book.title}</Text>
          <Text style={[styles.author, { color: colors.mutedForeground }]} numberOfLines={1}>{authorName}</Text>
        </View>
      </Pressable>
    </Link>
  );
}

// Memoize so a parent shelf scroll/re-render doesn't re-render every card.
export const BookCard = React.memo(BookCardImpl);

const styles = StyleSheet.create({
  container: {
    width: 120,
    gap: 8,
  },
  coverContainer: {
    width: 120,
    height: 180,
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
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textCoverTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 14,
    textAlign: 'center',
  },
  info: {
    gap: 2,
  },
  title: {
    fontFamily: 'Lora_500Medium',
    fontSize: 14,
    lineHeight: 18,
  },
  author: {
    fontFamily: 'Inter_400Regular',
    fontSize: 12,
  }
});

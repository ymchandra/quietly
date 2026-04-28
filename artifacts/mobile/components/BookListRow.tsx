import React from 'react';
import { View, Text, StyleSheet, Pressable, ViewStyle } from 'react-native';
import { Image } from 'expo-image';
import { Link } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { Book, getBookCoverUrl } from '@/lib/gutendex';
import { useColors } from '@/hooks/useColors';

interface BookListRowProps {
  book: Book;
  percentRead?: number;
  onLongPress?: () => void;
  style?: ViewStyle;
}

export function BookListRow({ book, percentRead, onLongPress, style }: BookListRowProps) {
  const colors = useColors();
  const coverUrl = getBookCoverUrl(book);
  const authorName = book.authors?.[0]?.name?.split(',').reverse().join(' ').trim() || 'Unknown Author';

  return (
    <Link href={`/book/${book.id}`} asChild>
      <Pressable 
        style={({ pressed }) => [styles.container, style, pressed && { opacity: 0.8 }]}
        onLongPress={onLongPress}
      >
        <View style={[styles.coverContainer, { backgroundColor: colors.muted, borderRadius: colors.radius / 2 }]}>
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
              <Text style={[styles.textCoverTitle, { color: colors.mutedForeground }]} numberOfLines={2}>
                {book.title}
              </Text>
            </View>
          )}
        </View>
        <View style={styles.info}>
          <Text style={[styles.title, { color: colors.foreground }]} numberOfLines={2}>{book.title}</Text>
          <Text style={[styles.author, { color: colors.mutedForeground }]} numberOfLines={1}>{authorName}</Text>
          
          {percentRead !== undefined && (
            <View style={styles.progressContainer}>
              <View style={[styles.progressBarBg, { backgroundColor: colors.border, borderRadius: 2 }]}>
                <View style={[styles.progressBarFill, { backgroundColor: colors.primary, width: `${Math.max(0, Math.min(100, percentRead))}%`, borderRadius: 2 }]} />
              </View>
              <Text style={[styles.progressText, { color: colors.mutedForeground }]}>{Math.round(percentRead)}%</Text>
            </View>
          )}
        </View>
        {onLongPress && (
          <View style={styles.moreIcon}>
            <Feather name="more-horizontal" size={20} color={colors.mutedForeground} />
          </View>
        )}
      </Pressable>
    </Link>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingVertical: 12,
    gap: 16,
    alignItems: 'center',
  },
  coverContainer: {
    width: 60,
    height: 90,
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
    padding: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textCoverTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 10,
    textAlign: 'center',
  },
  info: {
    flex: 1,
    gap: 4,
    justifyContent: 'center',
  },
  title: {
    fontFamily: 'Lora_500Medium',
    fontSize: 16,
    lineHeight: 22,
  },
  author: {
    fontFamily: 'Inter_400Regular',
    fontSize: 14,
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 4,
  },
  progressBarBg: {
    flex: 1,
    height: 4,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
  },
  progressText: {
    fontFamily: 'Inter_500Medium',
    fontSize: 12,
  },
  moreIcon: {
    padding: 8,
  }
});

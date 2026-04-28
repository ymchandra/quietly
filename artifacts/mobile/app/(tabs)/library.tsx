import React, { useState } from 'react';
import { View, StyleSheet, FlatList, Alert } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/useColors';
import { useLibrary } from '@/contexts/LibraryContext';
import { SegmentedControl } from '@/components/SegmentedControl';
import { BookListRow } from '@/components/BookListRow';
import { EmptyState } from '@/components/EmptyState';
import { Book } from '@/lib/gutendex';

export default function LibraryScreen() {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const { downloaded, progress, removeOffline } = useLibrary();
  
  const [selectedIndex, setSelectedIndex] = useState(0);
  const segments = ['Reading', 'Downloaded', 'Finished'];

  const allBooksWithProgress = Object.entries(progress).map(([id, p]) => {
    // Find book details from downloaded
    const book = downloaded.find(b => b.id === Number(id));
    return { book, percent: p.percent, updatedAt: p.updatedAt, id: Number(id) };
  }).filter(item => item.book) as { book: Book, percent: number, updatedAt: number, id: number }[];

  const reading = allBooksWithProgress
    .filter(item => item.percent > 0 && item.percent < 98)
    .sort((a, b) => b.updatedAt - a.updatedAt);
    
  const finished = allBooksWithProgress
    .filter(item => item.percent >= 98)
    .sort((a, b) => b.updatedAt - a.updatedAt);

  const handleLongPress = (book: Book, isDownloaded: boolean) => {
    if (isDownloaded) {
      Alert.alert(
        "Remove Download",
        `Remove "${book.title}" from offline storage?`,
        [
          { text: "Cancel", style: "cancel" },
          { text: "Remove", style: "destructive", onPress: () => removeOffline(book.id) }
        ]
      );
    }
  };

  const renderContent = () => {
    if (selectedIndex === 0) {
      // Reading
      if (reading.length === 0) {
        return (
          <EmptyState 
            icon="book-open" 
            title="Nothing currently reading" 
            subtitle="Start reading a book and it will appear here so you can easily pick up where you left off." 
          />
        );
      }
      return (
        <FlatList
          data={reading}
          keyExtractor={item => item.id.toString()}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <BookListRow 
              book={item.book} 
              percentRead={item.percent} 
              onLongPress={() => handleLongPress(item.book, downloaded.some(d => d.id === item.id))}
            />
          )}
        />
      );
    } else if (selectedIndex === 1) {
      // Downloaded
      if (downloaded.length === 0) {
        return (
          <EmptyState 
            icon="download" 
            title="No offline books" 
            subtitle="Download books to your device to read them anywhere, even without an internet connection." 
          />
        );
      }
      return (
        <FlatList
          data={downloaded}
          keyExtractor={item => item.id.toString()}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <BookListRow 
              book={item} 
              percentRead={progress[item.id]?.percent}
              onLongPress={() => handleLongPress(item, true)}
            />
          )}
        />
      );
    } else {
      // Finished
      if (finished.length === 0) {
        return (
          <EmptyState 
            icon="check-circle" 
            title="No finished books yet" 
            subtitle="Books you complete will be collected here." 
          />
        );
      }
      return (
        <FlatList
          data={finished}
          keyExtractor={item => item.id.toString()}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <BookListRow 
              book={item.book} 
              percentRead={item.percent}
              onLongPress={() => handleLongPress(item.book, downloaded.some(d => d.id === item.id))}
            />
          )}
        />
      );
    }
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background, paddingTop: Math.max(insets.top, 40) }]}>
      <View style={styles.header}>
        <SegmentedControl 
          segments={segments} 
          selectedIndex={selectedIndex} 
          onChange={setSelectedIndex} 
        />
      </View>
      <View style={styles.content}>
        {renderContent()}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  content: {
    flex: 1,
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 100,
  }
});

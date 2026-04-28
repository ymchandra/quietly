import React, { useState } from 'react';
import { View, StyleSheet, FlatList, Alert } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/useColors';
import { useLibrary } from '@/contexts/LibraryContext';
import { SegmentedControl } from '@/components/SegmentedControl';
import { BookListRow } from '@/components/BookListRow';
import { EmptyState } from '@/components/EmptyState';
import { Book } from '@/lib/gutendex';

export default function ListsScreen() {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const { wishlist, readLater, removeFromWishlist, removeFromReadLater } = useLibrary();
  
  const [selectedIndex, setSelectedIndex] = useState(0);
  const segments = ['Wishlist', 'Read Later'];

  const handleLongPress = (book: Book, type: 'wishlist' | 'readLater') => {
    Alert.alert(
      "Remove Book",
      `Remove "${book.title}" from this list?`,
      [
        { text: "Cancel", style: "cancel" },
        { 
          text: "Remove", 
          style: "destructive", 
          onPress: () => type === 'wishlist' ? removeFromWishlist(book.id) : removeFromReadLater(book.id) 
        }
      ]
    );
  };

  const renderContent = () => {
    if (selectedIndex === 0) {
      if (wishlist.length === 0) {
        return (
          <EmptyState 
            icon="heart" 
            title="Your wishlist is empty" 
            subtitle="Find books you love and add them to your wishlist to remember them." 
          />
        );
      }
      return (
        <FlatList
          data={wishlist}
          keyExtractor={item => item.id.toString()}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <BookListRow 
              book={item} 
              onLongPress={() => handleLongPress(item, 'wishlist')}
            />
          )}
        />
      );
    } else {
      if (readLater.length === 0) {
        return (
          <EmptyState 
            icon="clock" 
            title="Nothing saved for later" 
            subtitle="Save books here that you want to read but aren't quite ready to start." 
          />
        );
      }
      return (
        <FlatList
          data={readLater}
          keyExtractor={item => item.id.toString()}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <BookListRow 
              book={item} 
              onLongPress={() => handleLongPress(item, 'readLater')}
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

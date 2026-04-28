import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, RefreshControl, FlatList } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { fetchBooks, GutendexResponse, Book } from '@/lib/gutendex';
import { useColors } from '@/hooks/useColors';
import { SearchBar } from '@/components/SearchBar';
import { BookCard } from '@/components/BookCard';
import { Skeleton } from '@/components/Skeleton';
import { EmptyState } from '@/components/EmptyState';

const TOPICS = [
  { id: 'popular', title: 'Most Loved Classics', params: { sort: 'popular' as const } },
  { id: 'romance', title: 'Romance', params: { topic: 'romance', sort: 'popular' as const } },
  { id: 'mystery', title: 'Mystery & Detective', params: { topic: 'mystery', sort: 'popular' as const } },
  { id: 'philosophy', title: 'Philosophy', params: { topic: 'philosophy', sort: 'popular' as const } },
  { id: 'poetry', title: 'Poetry', params: { topic: 'poetry', sort: 'popular' as const } },
  { id: 'adventure', title: 'Adventure', params: { topic: 'adventure', sort: 'popular' as const } },
];

function TopicShelf({ title, params }: { title: string; params: any }) {
  const colors = useColors();
  const { data, isLoading, error } = useQuery<GutendexResponse>({
    queryKey: ['books', params],
    queryFn: () => fetchBooks({ ...params, languages: 'en' }),
  });

  if (error) return null;

  return (
    <View style={styles.shelfContainer}>
      <Text style={[styles.shelfTitle, { color: colors.foreground }]}>{title}</Text>
      {isLoading ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.shelfScroll}>
          {[1, 2, 3, 4].map(i => (
            <View key={i} style={styles.skeletonCard}>
              <Skeleton width={120} height={180} borderRadius={8} />
              <View style={styles.skeletonInfo}>
                <Skeleton width={100} height={14} />
                <Skeleton width={80} height={12} />
              </View>
            </View>
          ))}
        </ScrollView>
      ) : (
        <FlatList
          horizontal
          data={data?.results.slice(0, 10) || []}
          keyExtractor={(item) => item.id.toString()}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.shelfScroll}
          renderItem={({ item }) => <BookCard book={item} />}
        />
      )}
    </View>
  );
}

export default function DiscoverScreen() {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const [searchQuery, setSearchQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const { data: searchResults, isLoading: isSearching, refetch: refetchSearch } = useQuery<GutendexResponse>({
    queryKey: ['search', searchQuery],
    queryFn: () => fetchBooks({ search: searchQuery, languages: 'en' }),
    enabled: searchQuery.length > 0,
  });

  const onRefresh = async () => {
    setRefreshing(true);
    if (searchQuery.length > 0) {
      await refetchSearch();
    }
    setRefreshing(false);
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background, paddingTop: Math.max(insets.top, 40) }]}>
      <View style={styles.header}>
        <SearchBar 
          value={searchQuery} 
          onChangeText={setSearchQuery} 
          placeholder="Search author or title..." 
        />
      </View>

      <ScrollView 
        contentInsetAdjustmentBehavior="automatic"
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {searchQuery.length > 0 ? (
          <View style={styles.searchResults}>
            {isSearching ? (
              <View style={styles.searchGrid}>
                {[1, 2, 3, 4].map(i => (
                  <View key={i} style={styles.skeletonCard}>
                    <Skeleton width={120} height={180} borderRadius={8} />
                    <View style={styles.skeletonInfo}>
                      <Skeleton width={100} height={14} />
                      <Skeleton width={80} height={12} />
                    </View>
                  </View>
                ))}
              </View>
            ) : searchResults?.results.length === 0 ? (
              <EmptyState 
                icon="search" 
                title="No books found" 
                subtitle="Try a different search term or explore the categories." 
              />
            ) : (
              <View style={styles.searchGrid}>
                {searchResults?.results.map(book => (
                  <View key={book.id} style={styles.searchGridItem}>
                    <BookCard book={book} style={{ width: '100%' }} />
                  </View>
                ))}
              </View>
            )}
          </View>
        ) : (
          <View style={styles.shelves}>
            {TOPICS.map(topic => (
              <TopicShelf key={topic.id} title={topic.title} params={topic.params} />
            ))}
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
  header: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  shelves: {
    gap: 32,
    paddingTop: 8,
  },
  shelfContainer: {
    gap: 16,
  },
  shelfTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 22,
    paddingHorizontal: 16,
  },
  shelfScroll: {
    paddingHorizontal: 16,
    gap: 16,
  },
  skeletonCard: {
    width: 120,
    gap: 8,
  },
  skeletonInfo: {
    gap: 4,
  },
  searchResults: {
    padding: 16,
  },
  searchGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
    justifyContent: 'space-between',
  },
  searchGridItem: {
    width: '47%',
    marginBottom: 16,
  }
});

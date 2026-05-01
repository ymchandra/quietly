import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  RefreshControl,
  FlatList,
  useColorScheme,
} from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { fetchBooks, GutendexResponse } from '@/lib/gutendex';
import { useColors } from '@/hooks/useColors';
import { SearchBar } from '@/components/SearchBar';
import { BookCard } from '@/components/BookCard';
import { Skeleton } from '@/components/Skeleton';
import { EmptyState } from '@/components/EmptyState';

interface TopicDef {
  id: string;
  title: string;
  params: { sort?: 'popular' | 'ascending' | 'descending'; topic?: string };
}

const TOPICS: TopicDef[] = [
  { id: 'popular',    title: 'Most Loved Classics',   params: { sort: 'popular' } },
  { id: 'romance',    title: 'Romance',                params: { topic: 'romance',    sort: 'popular' } },
  { id: 'mystery',    title: 'Mystery & Detective',    params: { topic: 'mystery',    sort: 'popular' } },
  { id: 'philosophy', title: 'Philosophy',             params: { topic: 'philosophy', sort: 'popular' } },
  { id: 'poetry',     title: 'Poetry',                 params: { topic: 'poetry',     sort: 'popular' } },
  { id: 'adventure',  title: 'Adventure',              params: { topic: 'adventure',  sort: 'popular' } },
];

const ShelfSkeletonRow = React.memo(function ShelfSkeletonRow() {
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.shelfScroll}>
      {[0, 1, 2, 3].map(i => (
        <View key={i} style={styles.skeletonCard}>
          <Skeleton width={120} height={180} borderRadius={8} />
          <View style={styles.skeletonInfo}>
            <Skeleton width={100} height={14} />
            <Skeleton width={80} height={12} />
          </View>
        </View>
      ))}
    </ScrollView>
  );
});

const TopicShelf = React.memo(function TopicShelf({
  title,
  params,
}: {
  title: string;
  params: TopicDef['params'];
}) {
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
        <ShelfSkeletonRow />
      ) : (
        <FlatList
          horizontal
          data={(data?.results ?? []).slice(0, 10)}
          keyExtractor={(item) => item.id.toString()}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.shelfScroll}
          renderItem={({ item }) => <BookCard book={item} />}
          initialNumToRender={4}
          maxToRenderPerBatch={4}
          windowSize={2}
          removeClippedSubviews
        />
      )}
    </View>
  );
});

export default function DiscoverScreen() {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const colorScheme = useColorScheme();
  const [searchQuery, setSearchQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const { data: searchResults, isLoading: isSearching, refetch: refetchSearch } =
    useQuery<GutendexResponse>({
      queryKey: ['search', searchQuery],
      queryFn: () => fetchBooks({ search: searchQuery, languages: 'en' }),
      enabled: searchQuery.length > 0,
    });

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    if (searchQuery.length > 0) {
      await refetchSearch();
    }
    setRefreshing(false);
  }, [searchQuery, refetchSearch]);

  const renderShelf = useCallback(
    ({ item }: { item: TopicDef }) => (
      <TopicShelf title={item.title} params={item.params} />
    ),
    [],
  );

  return (
    <View
      style={[
        styles.container,
        { backgroundColor: colors.background, paddingTop: Math.max(insets.top, 40) },
      ]}
    >
      {/* Wordmark */}
      <View style={styles.header}>
        <Text style={[styles.wordmark, { color: colors.foreground }]}>Quietly</Text>
        <SearchBar
          value={searchQuery}
          onChangeText={setSearchQuery}
          placeholder="Search author or title…"
        />
      </View>

      {searchQuery.length > 0 ? (
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primary}
            />
          }
          contentContainerStyle={{ paddingBottom: 100 }}
        >
          <View style={styles.searchResults}>
            {isSearching ? (
              <View style={styles.searchGrid}>
                {[0, 1, 2, 3].map(i => (
                  <View key={i} style={[styles.skeletonCard, styles.searchGridItem]}>
                    <Skeleton width="100%" height={180} borderRadius={8} />
                    <View style={styles.skeletonInfo}>
                      <Skeleton width="80%" height={14} />
                      <Skeleton width="60%" height={12} />
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
        </ScrollView>
      ) : (
        // Outer FlatList lazy-mounts shelves. initialNumToRender=2 means
        // only the top two shelves fire requests on first paint; the rest
        // mount as they scroll into view. windowSize=2 keeps one viewport
        // worth of shelves rendered at a time, reducing memory pressure.
        <FlatList
          data={TOPICS}
          keyExtractor={(t) => t.id}
          renderItem={renderShelf}
          contentContainerStyle={styles.shelvesContent}
          ItemSeparatorComponent={() => <View style={{ height: 32 }} />}
          initialNumToRender={2}
          maxToRenderPerBatch={1}
          updateCellsBatchingPeriod={150}
          windowSize={2}
          removeClippedSubviews
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primary}
            />
          }
        />
      )}
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
    gap: 12,
  },
  wordmark: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 32,
    letterSpacing: -0.5,
  },
  shelvesContent: {
    paddingTop: 8,
    paddingBottom: 100,
  },
  shelfContainer: {
    gap: 16,
  },
  shelfTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 20,
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
  },
  searchGridItem: {
    width: '47%',
  },
});

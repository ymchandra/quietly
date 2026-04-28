import React from 'react';
import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { ReaderSettingsSheet } from '@/components/ReaderSettingsSheet';
import { useColors } from '@/hooks/useColors';
import { Stack } from 'expo-router';

export default function ReaderSettingsModal() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const colors = useColors();

  return (
    <View style={[styles.container, { backgroundColor: 'transparent' }]}>
      <Stack.Screen options={{ presentation: 'formSheet', sheetAllowedDetents: [0.5, 0.75], contentStyle: { backgroundColor: 'transparent' }, headerShown: false }} />
      <ReaderSettingsSheet bookId={id ? Number(id) : undefined} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'flex-end',
  }
});

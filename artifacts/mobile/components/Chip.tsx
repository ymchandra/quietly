import React from 'react';
import { View, Text, StyleSheet, ViewStyle } from 'react-native';
import { useColors } from '@/hooks/useColors';

interface ChipProps {
  label: string;
  style?: ViewStyle;
}

export function Chip({ label, style }: ChipProps) {
  const colors = useColors();
  
  return (
    <View style={[styles.container, { backgroundColor: colors.muted, borderRadius: colors.radius }, style]}>
      <Text style={[styles.text, { color: colors.mutedForeground }]} numberOfLines={1}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    alignSelf: 'flex-start',
  },
  text: {
    fontFamily: 'Inter_500Medium',
    fontSize: 12,
  }
});

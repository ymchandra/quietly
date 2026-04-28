import React, { useEffect, useRef } from 'react';
import { View, Text, StyleSheet, Pressable, Animated } from 'react-native';
import { useColors } from '@/hooks/useColors';

interface SegmentedControlProps {
  segments: string[];
  selectedIndex: number;
  onChange: (index: number) => void;
}

export function SegmentedControl({ segments, selectedIndex, onChange }: SegmentedControlProps) {
  const colors = useColors();
  const animatedValue = useRef(new Animated.Value(selectedIndex)).current;

  useEffect(() => {
    Animated.spring(animatedValue, {
      toValue: selectedIndex,
      useNativeDriver: true,
      friction: 8,
      tension: 40,
    }).start();
  }, [selectedIndex, animatedValue]);

  const segmentWidth = 100 / segments.length;

  return (
    <View style={[styles.container, { backgroundColor: colors.muted, borderRadius: 8 }]}>
      <Animated.View
        style={[
          styles.activeBg,
          {
            backgroundColor: colors.card,
            borderRadius: 6,
            width: `${segmentWidth}%`,
            transform: [
              {
                translateX: animatedValue.interpolate({
                  inputRange: segments.map((_, i) => i),
                  outputRange: segments.map((_, i) => `${i * 100}%`),
                }),
              },
            ],
            shadowColor: '#000',
            shadowOffset: { width: 0, height: 1 },
            shadowOpacity: 0.1,
            shadowRadius: 2,
            elevation: 2,
          },
        ]}
      />
      {segments.map((segment, index) => {
        const isActive = selectedIndex === index;
        return (
          <Pressable
            key={segment}
            style={styles.segment}
            onPress={() => onChange(index)}
          >
            <Text
              style={[
                styles.segmentText,
                { color: isActive ? colors.foreground : colors.mutedForeground },
                isActive && styles.segmentTextActive
              ]}
            >
              {segment}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    height: 36,
    padding: 2,
    position: 'relative',
  },
  activeBg: {
    position: 'absolute',
    top: 2,
    bottom: 2,
    left: 2,
  },
  segment: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 1,
  },
  segmentText: {
    fontFamily: 'Inter_500Medium',
    fontSize: 13,
  },
  segmentTextActive: {
    fontFamily: 'Inter_600SemiBold',
  }
});

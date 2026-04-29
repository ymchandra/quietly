import React, { useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, Pressable, Animated, LayoutChangeEvent } from 'react-native';
import { useColors } from '@/hooks/useColors';

interface SegmentedControlProps {
  segments: string[];
  selectedIndex: number;
  onChange: (index: number) => void;
}

export function SegmentedControl({ segments, selectedIndex, onChange }: SegmentedControlProps) {
  const colors = useColors();
  const [containerWidth, setContainerWidth] = useState(0);
  const animatedValue = useRef(new Animated.Value(0)).current;

  // Inner padding of the container (must match styles.container.padding).
  const PADDING = 2;
  const segmentWidth = containerWidth > 0
    ? (containerWidth - PADDING * 2) / segments.length
    : 0;

  useEffect(() => {
    Animated.spring(animatedValue, {
      toValue: selectedIndex,
      useNativeDriver: true,
      friction: 8,
      tension: 40,
    }).start();
  }, [selectedIndex, animatedValue]);

  const handleLayout = (e: LayoutChangeEvent) => {
    setContainerWidth(e.nativeEvent.layout.width);
  };

  // Pixel-based interpolation works reliably with the native driver
  // on both iOS and Android (percentage outputs do not).
  const translateX = segmentWidth > 0
    ? animatedValue.interpolate({
        inputRange: segments.map((_, i) => i),
        outputRange: segments.map((_, i) => i * segmentWidth),
      })
    : 0;

  return (
    <View
      style={[styles.container, { backgroundColor: colors.muted, borderRadius: 8 }]}
      onLayout={handleLayout}
    >
      {segmentWidth > 0 && (
        <Animated.View
          style={[
            styles.activeBg,
            {
              backgroundColor: colors.card,
              borderRadius: 6,
              width: segmentWidth,
              transform: [{ translateX }],
              shadowColor: '#000',
              shadowOffset: { width: 0, height: 1 },
              shadowOpacity: 0.1,
              shadowRadius: 2,
              elevation: 2,
            },
          ]}
        />
      )}
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
                isActive && styles.segmentTextActive,
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
  },
});

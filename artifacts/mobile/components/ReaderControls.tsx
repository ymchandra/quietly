import React from 'react';
import { View, StyleSheet, Pressable, Platform, Animated } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/useColors';
import { THEMES, ThemeName } from '@/contexts/ReaderSettingsContext';

interface ReaderControlsProps {
  visible: boolean;
  theme: ThemeName;
  percent: number;
  onSettingsPress: () => void;
}

export function ReaderControls({ visible, theme, percent, onSettingsPress }: ReaderControlsProps) {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const themeColors = THEMES[theme];

  const topInset = Platform.OS === 'web' ? Math.max(insets.top, 67) : insets.top;
  const bottomInset = Platform.OS === 'web' ? Math.max(insets.bottom, 34) : insets.bottom;

  // Simple opacity animation based on visible prop
  const [opacity] = React.useState(new Animated.Value(visible ? 1 : 0));

  React.useEffect(() => {
    Animated.timing(opacity, {
      toValue: visible ? 1 : 0,
      duration: 200,
      useNativeDriver: true,
    }).start();
  }, [visible, opacity]);

  if (!visible && opacity._value === 0) return null;

  return (
    <Animated.View style={[StyleSheet.absoluteFill, { opacity }]} pointerEvents={visible ? 'auto' : 'none'}>
      {/* Top Bar */}
      <View 
        style={[
          styles.topBar, 
          { 
            paddingTop: topInset || 16,
            backgroundColor: themeColors.bg,
            borderBottomColor: themeColors.text + '1A', // 10% opacity
            borderBottomWidth: StyleSheet.hairlineWidth,
          }
        ]}
      >
        <Pressable style={styles.iconBtn} onPress={() => router.back()}>
          <Feather name="arrow-left" size={24} color={themeColors.text} />
        </Pressable>
        <Pressable style={styles.iconBtn} onPress={onSettingsPress}>
          <Feather name="settings" size={24} color={themeColors.text} />
        </Pressable>
      </View>

      {/* Bottom Progress Bar */}
      <View 
        style={[
          styles.bottomBar, 
          { 
            paddingBottom: bottomInset || 16,
            backgroundColor: themeColors.bg,
            borderTopColor: themeColors.text + '1A',
            borderTopWidth: StyleSheet.hairlineWidth,
          }
        ]}
      >
        <View style={[styles.progressContainer, { backgroundColor: themeColors.text + '1A' }]}>
          <View style={[styles.progressFill, { width: `${Math.max(0, Math.min(100, percent))}%`, backgroundColor: themeColors.accent }]} />
        </View>
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  topBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  iconBtn: {
    padding: 8,
  },
  bottomBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingHorizontal: 24,
    paddingTop: 16,
  },
  progressContainer: {
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 2,
  }
});

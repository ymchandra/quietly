import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useColors } from '@/hooks/useColors';
import { useReaderSettings, THEMES, ThemeName, FontFamily, LineHeight, LINE_HEIGHTS } from '@/contexts/ReaderSettingsContext';
import * as Haptics from 'expo-haptics';

interface ReaderSettingsSheetProps {
  bookId?: number;
}

export function ReaderSettingsSheet({ bookId }: ReaderSettingsSheetProps) {
  const colors = useColors();
  const { getEffectiveSettings, updateGlobalSettings, updateBookSettings } = useReaderSettings();
  const settings = getEffectiveSettings(bookId);

  const updateSetting = (key: keyof typeof settings, value: any) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (bookId) {
      updateBookSettings(bookId, { [key]: value });
    } else {
      updateGlobalSettings({ [key]: value });
    }
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.handleContainer}>
        <View style={[styles.handle, { backgroundColor: colors.border }]} />
      </View>
      
      <Text style={[styles.title, { color: colors.foreground }]}>Appearance</Text>

      {/* Themes */}
      <View style={styles.section}>
        <View style={styles.themeRow}>
          {(Object.keys(THEMES) as ThemeName[]).map(theme => (
            <Pressable
              key={theme}
              style={[
                styles.themeCircle,
                { backgroundColor: THEMES[theme].bg },
                settings.theme === theme && { borderColor: colors.primary, borderWidth: 2 }
              ]}
              onPress={() => updateSetting('theme', theme)}
            >
              <Text style={{ color: THEMES[theme].text, fontFamily: 'Lora_600SemiBold', fontSize: 18 }}>Aa</Text>
            </Pressable>
          ))}
        </View>
      </View>

      {/* Font Family & Size */}
      <View style={styles.section}>
        <View style={styles.row}>
          <View style={[styles.segmentedControl, { backgroundColor: colors.muted }]}>
            {(['Lora', 'Inter'] as FontFamily[]).map(font => (
              <Pressable
                key={font}
                style={[
                  styles.segment,
                  settings.fontFamily === font && { backgroundColor: colors.card, shadowOpacity: 0.1 }
                ]}
                onPress={() => updateSetting('fontFamily', font)}
              >
                <Text style={[
                  styles.segmentText, 
                  { 
                    color: settings.fontFamily === font ? colors.foreground : colors.mutedForeground,
                    fontFamily: font === 'Lora' ? 'Lora_500Medium' : 'Inter_500Medium'
                  }
                ]}>{font}</Text>
              </Pressable>
            ))}
          </View>
          
          <View style={[styles.sizeControls, { backgroundColor: colors.muted }]}>
            <Pressable 
              style={styles.sizeBtn} 
              onPress={() => updateSetting('fontSize', Math.max(14, settings.fontSize - 2))}
            >
              <Feather name="minus" size={20} color={colors.foreground} />
            </Pressable>
            <Text style={[styles.sizeText, { color: colors.foreground }]}>{settings.fontSize}</Text>
            <Pressable 
              style={styles.sizeBtn} 
              onPress={() => updateSetting('fontSize', Math.min(26, settings.fontSize + 2))}
            >
              <Feather name="plus" size={20} color={colors.foreground} />
            </Pressable>
          </View>
        </View>
      </View>

      {/* Line Height */}
      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: colors.mutedForeground }]}>Line Height</Text>
        <View style={[styles.segmentedControl, { backgroundColor: colors.muted }]}>
          {(['Compact', 'Comfortable', 'Airy'] as LineHeight[]).map(lh => (
            <Pressable
              key={lh}
              style={[
                styles.segment,
                settings.lineHeight === lh && { backgroundColor: colors.card, shadowOpacity: 0.1 }
              ]}
              onPress={() => updateSetting('lineHeight', lh)}
            >
              <Text style={[
                styles.segmentText, 
                { color: settings.lineHeight === lh ? colors.foreground : colors.mutedForeground }
              ]}>{lh}</Text>
            </Pressable>
          ))}
        </View>
      </View>

    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
  },
  handleContainer: {
    alignItems: 'center',
    marginBottom: 24,
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
  },
  title: {
    fontFamily: 'Inter_600SemiBold',
    fontSize: 20,
    marginBottom: 24,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontFamily: 'Inter_500Medium',
    fontSize: 13,
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  themeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  themeCircle: {
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  row: {
    flexDirection: 'row',
    gap: 16,
  },
  segmentedControl: {
    flex: 1,
    flexDirection: 'row',
    padding: 4,
    borderRadius: 12,
  },
  segment: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 2,
  },
  segmentText: {
    fontFamily: 'Inter_500Medium',
    fontSize: 14,
  },
  sizeControls: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 12,
    paddingHorizontal: 4,
  },
  sizeBtn: {
    padding: 12,
  },
  sizeText: {
    fontFamily: 'Inter_500Medium',
    fontSize: 16,
    width: 24,
    textAlign: 'center',
  }
});

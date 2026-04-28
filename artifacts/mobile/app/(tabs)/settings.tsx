import React from 'react';
import { View, Text, StyleSheet, ScrollView, Pressable } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/useColors';
import { THEMES, ThemeName, FontFamily, LineHeight, useReaderSettings } from '@/contexts/ReaderSettingsContext';
import { Feather } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';

export default function SettingsScreen() {
  const insets = useSafeAreaInsets();
  const colors = useColors();
  const { settings, updateGlobalSettings } = useReaderSettings();

  const updateSetting = (key: keyof typeof settings.global, value: any) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    updateGlobalSettings({ [key]: value });
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background, paddingTop: Math.max(insets.top, 40) }]}>
      <Text style={[styles.headerTitle, { color: colors.foreground }]}>Reader Defaults</Text>
      
      <ScrollView contentContainerStyle={{ paddingBottom: 100 }}>
        <View style={styles.content}>
          {/* Themes */}
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.mutedForeground }]}>Theme</Text>
            <View style={styles.themeRow}>
              {(Object.keys(THEMES) as ThemeName[]).map(theme => (
                <Pressable
                  key={theme}
                  style={[
                    styles.themeCircle,
                    { backgroundColor: THEMES[theme].bg },
                    settings.global.theme === theme && { borderColor: colors.primary, borderWidth: 2 }
                  ]}
                  onPress={() => updateSetting('theme', theme)}
                >
                  <Text style={{ color: THEMES[theme].text, fontFamily: 'Lora_600SemiBold', fontSize: 18 }}>Aa</Text>
                </Pressable>
              ))}
            </View>
          </View>

          {/* Font Family */}
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.mutedForeground }]}>Font</Text>
            <View style={[styles.segmentedControl, { backgroundColor: colors.muted }]}>
              {(['Lora', 'Inter'] as FontFamily[]).map(font => (
                <Pressable
                  key={font}
                  style={[
                    styles.segment,
                    settings.global.fontFamily === font && { backgroundColor: colors.card, shadowOpacity: 0.1 }
                  ]}
                  onPress={() => updateSetting('fontFamily', font)}
                >
                  <Text style={[
                    styles.segmentText, 
                    { 
                      color: settings.global.fontFamily === font ? colors.foreground : colors.mutedForeground,
                      fontFamily: font === 'Lora' ? 'Lora_500Medium' : 'Inter_500Medium'
                    }
                  ]}>{font}</Text>
                </Pressable>
              ))}
            </View>
          </View>

          {/* Font Size */}
          <View style={styles.section}>
            <Text style={[styles.sectionTitle, { color: colors.mutedForeground }]}>Font Size</Text>
            <View style={[styles.sizeControls, { backgroundColor: colors.muted }]}>
              <Pressable 
                style={styles.sizeBtn} 
                onPress={() => updateSetting('fontSize', Math.max(14, settings.global.fontSize - 2))}
              >
                <Feather name="minus" size={20} color={colors.foreground} />
              </Pressable>
              <Text style={[styles.sizeText, { color: colors.foreground }]}>{settings.global.fontSize}</Text>
              <Pressable 
                style={styles.sizeBtn} 
                onPress={() => updateSetting('fontSize', Math.min(26, settings.global.fontSize + 2))}
              >
                <Feather name="plus" size={20} color={colors.foreground} />
              </Pressable>
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
                    settings.global.lineHeight === lh && { backgroundColor: colors.card, shadowOpacity: 0.1 }
                  ]}
                  onPress={() => updateSetting('lineHeight', lh)}
                >
                  <Text style={[
                    styles.segmentText, 
                    { color: settings.global.lineHeight === lh ? colors.foreground : colors.mutedForeground }
                  ]}>{lh}</Text>
                </Pressable>
              ))}
            </View>
          </View>

          <View style={[styles.aboutCard, { backgroundColor: colors.secondary, borderRadius: colors.radius }]}>
            <Text style={[styles.aboutTitle, { color: colors.foreground }]}>Quietread</Text>
            <Text style={[styles.aboutText, { color: colors.secondaryForeground }]}>
              A calm, unhurried reader for free public-domain classics. Take a deep breath and lose yourself in a good book.
            </Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  headerTitle: {
    fontFamily: 'Lora_600SemiBold',
    fontSize: 28,
    paddingHorizontal: 24,
    paddingBottom: 24,
  },
  content: {
    paddingHorizontal: 24,
  },
  section: {
    marginBottom: 32,
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
  segmentedControl: {
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
    justifyContent: 'center',
    borderRadius: 12,
    paddingVertical: 4,
  },
  sizeBtn: {
    padding: 16,
  },
  sizeText: {
    fontFamily: 'Inter_500Medium',
    fontSize: 18,
    width: 48,
    textAlign: 'center',
  },
  aboutCard: {
    padding: 24,
    marginTop: 24,
  },
  aboutTitle: {
    fontFamily: 'Lora_700Bold',
    fontSize: 20,
    marginBottom: 8,
  },
  aboutText: {
    fontFamily: 'Inter_400Regular',
    fontSize: 15,
    lineHeight: 22,
  }
});

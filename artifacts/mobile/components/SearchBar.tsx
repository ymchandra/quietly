import React, { useState, useEffect } from 'react';
import { View, TextInput, StyleSheet, Pressable } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useColors } from '@/hooks/useColors';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
  onSubmit?: () => void;
}

export function SearchBar({ value, onChangeText, placeholder = "Search Gutendex...", onSubmit }: SearchBarProps) {
  const colors = useColors();
  const [internalValue, setInternalValue] = useState(value);

  useEffect(() => {
    setInternalValue(value);
  }, [value]);

  useEffect(() => {
    const timeout = setTimeout(() => {
      onChangeText(internalValue);
    }, 350);
    return () => clearTimeout(timeout);
  }, [internalValue, onChangeText]);

  return (
    <View style={[styles.container, { backgroundColor: colors.muted, borderRadius: 100 }]}>
      <Feather name="search" size={20} color={colors.mutedForeground} style={styles.icon} />
      <TextInput
        style={[styles.input, { color: colors.foreground }]}
        placeholder={placeholder}
        placeholderTextColor={colors.mutedForeground}
        value={internalValue}
        onChangeText={setInternalValue}
        onSubmitEditing={onSubmit}
        returnKeyType="search"
      />
      {internalValue.length > 0 && (
        <Pressable onPress={() => setInternalValue('')} style={styles.clearBtn}>
          <Feather name="x-circle" size={18} color={colors.mutedForeground} />
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 48,
    paddingHorizontal: 16,
  },
  icon: {
    marginRight: 8,
  },
  input: {
    flex: 1,
    fontFamily: 'Inter_400Regular',
    fontSize: 16,
    height: '100%',
  },
  clearBtn: {
    padding: 4,
  }
});

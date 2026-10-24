// Qual sprite usar para cada cultivo e estágio, conforme o que existe no manifest das artes.
export type Manifest = Record<string, { file: string; size: [number, number]; anchor: [number, number]; frames?: number; frame_size?: [number, number] }>;

export function stageSprite(m: Manifest, crop: string, stage: number): string {
  if (stage >= 3) {
    if (m[`crop_${crop}_ready`]) return `crop_${crop}_ready`;
    if (m[`icon_${crop}`]) return `icon_${crop}`;
    return 'crop_generic_stage3';
  }
  const own = `crop_${crop}_stage${stage + 1}`;
  return m[own] ? own : `crop_generic_stage${stage + 1}`;
}

export function iconSprite(m: Manifest, item: string): string | null {
  for (const k of [`icon_${item}`, `crop_${item}_ready`, `seedbag_${item}`]) if (m[k]) return k;
  const v = ICON_VARIANTS[item];
  return v && m[`icon_${v.base}`] ? `icon_${v.base}` : null;
}

// produtos que a prancha pede como "variação de cor": usam o ícone base com um filtro de cor (só visual)
export const ICON_VARIANTS: Record<string, { base: string; filter: string }> = {
  leite_de_cabra: { base: 'leite', filter: 'sepia(0.45) saturate(1.3)' },
  ovo_de_ganso: { base: 'ovo', filter: 'sepia(0.35) saturate(1.6) brightness(0.95)' },
  la_de_alpaca: { base: 'la', filter: 'sepia(0.7) saturate(1.5) hue-rotate(-12deg) brightness(0.85)' },
};

/** sprite do pet (2 quadros parados) quando a arte existe */
export function petSprite(m: Manifest, pet: string, frame: 1 | 2 = 1): string | null {
  const k = `pet_${pet}_idle${frame}`;
  return m[k] ? k : null;
}

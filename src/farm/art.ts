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
  return null;
}

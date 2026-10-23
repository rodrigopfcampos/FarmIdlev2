// Dados do jogo vindos de config/*.json (só leitura no cliente; o servidor confere tudo).
import cropsCfg from '../config/crops.json';
import farmCfg from '../config/farm.json';
import mapCfg from '../config/mapConfig.json';
import expeditionsCfg from '../config/expeditions.json';
import charactersCfg from '../config/characters.json';

export type Crop = (typeof cropsCfg.crops)[number];
export const CROPS: Record<string, Crop> = Object.fromEntries(cropsCfg.crops.map((c) => [c.id, c]));
export const FARM = farmCfg;
export const MAP = mapCfg;
export const STALL_RATIO = expeditionsCfg.stall_price_ratio;
export const CLASSES = charactersCfg.classes;
export const UNLOCKED_CROPS: Crop[] = farmCfg.phase1_unlocked_crops.map((id) => CROPS[id]);

export type Pt = [number, number];
export type Plot = { id: string; polygon: Pt[]; center: Pt };
export type Lot = { id: string; type: string; polygon: Pt[]; plots?: Plot[]; center: Pt };
export const LOTS = MAP.lots as unknown as Lot[];
export type Zone = { id: string; hit_rects: number[][]; parked_vehicle_anchor?: number[] };
export const ZONES = MAP.functional_zones as unknown as Zone[];

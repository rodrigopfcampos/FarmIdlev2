// Dados do jogo vindos de config/*.json (só leitura no cliente; o servidor confere tudo).
import cropsCfg from '../config/crops.json';
import farmCfg from '../config/farm.json';
import mapCfg from '../config/mapConfig.json';
import mapRulesCfg from '../config/map_rules.json';
import lotsCfg from '../config/lots.json';
import levelsCfg from '../config/levels.json';
import toolsCfg from '../config/tools_and_items.json';
import expeditionsCfg from '../config/expeditions.json';
import charactersCfg from '../config/characters.json';
import rarityCfg from '../config/rarity.json';

export type Crop = (typeof cropsCfg.crops)[number] & { sapling_cost?: number; seed_cost?: number; tree_base?: string };
export const CROP_LIST = cropsCfg.crops as Crop[];
export const CROPS: Record<string, Crop> = Object.fromEntries(CROP_LIST.map((c) => [c.id, c]));
export const WORK = cropsCfg.rules.work_units;
export const FARM = farmCfg;
export const MAP = mapCfg;
export const MAP_RULES = mapRulesCfg;
export const LOT_RULES = lotsCfg.rules;
export const PURCHASES = lotsCfg.purchases;
export const LEVELS = levelsCfg.levels;
export const MAX_LEVEL = levelsCfg.max_level;
export const TOOL_MATERIALS = toolsCfg.tool_materials;
export const STALL_RATIO = expeditionsCfg.stall_price_ratio;
export const VEHICLES = expeditionsCfg.vehicles;
export const CLASSES = charactersCfg.classes;
export const CHARS = charactersCfg;
export type SkillNode = { effect: string; text_pt: string; phase?: number; per_point?: number; value?: number };
export type SkillBranch = { id: string; name_pt: string; a: SkillNode; b: SkillNode; mastery: SkillNode };
export const SKILL_TREE = charactersCfg.skill_tree as unknown as Record<string, SkillBranch[]>;
export const PETS = charactersCfg.pets;
export const SNACKS = toolsCfg.snack_cards;
export const CLASS_TOOLS = toolsCfg.class_tool_cards;
export const RARITIES = rarityCfg.tiers;
export const RARITY_BY_ID: Record<string, (typeof rarityCfg.tiers)[number]> = Object.fromEntries(rarityCfg.tiers.map((t) => [t.id, t]));

export type Pt = [number, number];
export type Plot = { id: string; polygon: Pt[]; center: Pt };
export type Lot = {
  id: string; type: string; polygon: Pt[]; plots?: Plot[]; center: Pt; neighbors: string[];
  sign_anchor?: Pt; debris_anchors?: Pt[]; tree_slots?: Pt[]; building?: string; building_anchor?: Pt;
};
export const LOTS = MAP.lots as unknown as Lot[];
export const LOT_BY_ID: Record<string, Lot> = Object.fromEntries(LOTS.map((l) => [l.id, l]));
export type Zone = { id: string; hit_rects: number[][]; parked_vehicle_anchor?: number[] };
export const ZONES = MAP.functional_zones as unknown as Zone[];

export const LOT_TYPE_NAMES: Record<string, string> = {
  lavoura: 'Lavoura', pomar: 'Pomar', pasto_galinheiro: 'Pasto do Galinheiro', pasto_celeiro: 'Pasto do Celeiro', pasto_lago: 'Lago',
};

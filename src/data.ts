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
import animalsCfg from '../config/animals.json';
import animationsCfg from '../config/animations.json';
import weatherCfg from '../config/weather.json';
import cardsCfg from '../config/cards.json';
import missionsCfg from '../config/missions.json';
import fishingCfg from '../config/fishing.json';
import socialCfg from '../config/social.json';
import villageCfg from '../config/village.json';
import anticheatCfg from '../config/anticheat.json';

/** fichas das animações (tempo por quadro, pixels inteiros) */
export const ANIM = animationsCfg;
export const WEATHER = weatherCfg;
export const CARDS = cardsCfg;
export const MISSIONS = missionsCfg;
export const SOCIAL = socialCfg;
export const VILLAGE = villageCfg;
export const ANTICHEAT = anticheatCfg;

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
// R3: árvore de habilidades da conta (substitui as dos personagens)
export type AccountReq = { node: string; min: number };
export type AccountNode = { id: string; name_pt: string; icon: string; text_pt: string; max: number; cost: number; effects: { effect: string; per_point: number }[];
  pos: [number, number]; requires?: AccountReq[]; requires_any?: AccountReq[]; requires_branch_points?: number; ultimate?: boolean };
export type AccountBranch = { id: string; name_pt: string; color_hex: string; nodes: AccountNode[] };
export const ACCOUNT_TREE = charactersCfg.account_tree as unknown as { name_pt: string; points_per_level: number; from_level: number; free_resets_per_week: number;
  extra_reset_cost_R_ratio: number; canvas: [number, number]; root: { id: string; name_pt: string; icon: string; pos: [number, number] }; branches: AccountBranch[] };
// R3: pesca no Lago
export const FISHING = fishingCfg as unknown as { cycle_minutes: number; max_cycles: number; value_share_of_R: number; cycles_per_day_reference: number; team: { efficiency: number }; rod: { wear_per_cycle: number; low_threshold: number; low_multiplier: number };
  species: { id: string; name_pt: string; unlock_level: number; fair_price_per_unit: number; sprite: string }[] };
export const PETS = charactersCfg.pets;
export const SNACKS = toolsCfg.snack_cards;
export const CLASS_TOOLS = toolsCfg.class_tool_cards;
export const RARITIES = rarityCfg.tiers;
export const RARITY_BY_ID: Record<string, (typeof rarityCfg.tiers)[number]> = Object.fromEntries(rarityCfg.tiers.map((t) => [t.id, t]));

export type Pt = [number, number];
export type Plot = { id: string; polygon: Pt[]; center: Pt };
export type Lot = {
  id: string; type: string; polygon: Pt[]; plots?: Plot[]; center: Pt; neighbors: string[];
  sign_anchor?: Pt; debris_anchors?: Pt[]; tree_slots?: Pt[]; building?: string; building_anchor?: Pt; building_hit_rect?: [number, number, number, number];
};
export const LOTS = MAP.lots as unknown as Lot[];
export const LOT_BY_ID: Record<string, Lot> = Object.fromEntries(LOTS.map((l) => [l.id, l]));
export type Zone = { id: string; hit_rects: number[][]; parked_vehicle_anchor?: number[] };
export const ZONES = MAP.functional_zones as unknown as Zone[];

export const LOT_TYPE_NAMES: Record<string, string> = {
  lavoura: 'Lavoura', pomar: 'Pomar', pasto_galinheiro: 'Pasto do Galinheiro', pasto_celeiro: 'Pasto do Celeiro', pasto_lago: 'Lago',
};

// ---------- animais (fase 4) ----------
export type Animal = (typeof animalsCfg.animals)[number];
export const ANIMALS = animalsCfg.animals as Animal[];
export const ANIMAL_BY_ID: Record<string, Animal> = Object.fromEntries(ANIMALS.map((a) => [a.id, a]));
export const ANIMAL_RULES = animalsCfg.rules;
export const HOUSES = animalsCfg.houses as Record<string, { lot_type: string; slots: { slots: number; min_level: number | null; cost: number }[] }>;
export const HOUSE_NAMES: Record<string, string> = { galinheiro: 'Galinheiro', celeiro: 'Celeiro' };
// emojis provisórios até as artes dos animais e dos produtos chegarem
export const ANIMAL_EMOJI: Record<string, string> = { galinha: '🐔', coelho: '🐰', vaca: '🐄', pato: '🦆', ovelha: '🐑', porco: '🐖', cabra: '🐐', ganso: '🪿', peru: '🦃', alpaca: '🦙' };
const PRODUCT_EMOJI: Record<string, string> = { ovo: '🥚', pelo_de_coelho: '🧶', leite: '🥛', ovo_de_pata: '🥚', la: '🧶', trufa: '🍄', leite_de_cabra: '🥛', ovo_de_ganso: '🥚', pena_de_peru: '🪶', la_de_alpaca: '🧶' };
const PRODUCTS: Record<string, { name_pt: string; price: number; emoji: string }> = Object.fromEntries(
  ANIMALS.map((a) => [a.product.id, { name_pt: a.product.name_pt, price: a.product.fair_price_per_unit, emoji: PRODUCT_EMOJI[a.product.id] ?? '📦' }]));

/** nome, preço da Feira e (se for produto animal) emoji de um item do Silo */
export function itemInfo(id: string): { name_pt: string; price: number; emoji: string | null } {
  const c = CROPS[id];
  if (c) return { name_pt: c.name_pt, price: c.fair_price_per_unit, emoji: null };
  const p = PRODUCTS[id];
  if (p) return { name_pt: p.name_pt, price: p.price, emoji: p.emoji };
  const f = FISHING.species.find((x) => x.id === id);
  return f ? { name_pt: f.name_pt, price: f.fair_price_per_unit, emoji: '🐟' } : { name_pt: id, price: 0, emoji: null };
}

// ---------- expedições (fase 5) ----------
export const EXP = expeditionsCfg;
export type Route = (typeof expeditionsCfg.routes)[number];
export type VehicleDef = (typeof expeditionsCfg.vehicles)[number];
export const ROUTES = expeditionsCfg.routes as Route[];
export const ROUTE_BY_ID: Record<string, Route> = Object.fromEntries(ROUTES.map((r) => [r.id, r]));
export const VEHICLE_BY_ID: Record<string, VehicleDef> = Object.fromEntries(VEHICLES.map((v) => [v.id, v]));
export const EQUIP_CARDS = [...toolsCfg.clothing_cards, ...toolsCfg.amulet_cards] as unknown as { id: string; name_pt: string; base_effect: Record<string, number> }[];
export const EQUIP_RARITIES = toolsCfg.equipment_rarities as Record<string, { multiplier: number; color_hex: string; merge_count_to_upgrade: number | null }>;

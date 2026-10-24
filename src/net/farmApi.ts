// Chamadas da fazenda ao servidor. O cliente só manda intenções; o servidor calcula e devolve o estado.
import { supabase } from './supabase';
import type { TreeState } from '../farm/rules';

export type PlotState = {
  plot_id: string; crop_id: string | null; state: 'empty' | 'growing'; planted_crop_id: string | null;
  planted_at: number | null; ready_at: number | null; harvests_done: number; stalled_reason: string | null; rarity?: string | null;
};
export type CharacterState = {
  class_id: string; slot: 'field' | 'bench'; energy: number; parked: boolean; level: number; work_hours: number;
  skills: Record<string, number>; skill_choice: string | null; reset_week: string | null; debt: number; unpaid_days: number;
  snack_id: string | null; snack_qty: number; cloth_id: string | null; amulet_id: string | null; material: string; durability: number;
  rate: number; energy_max: number; energy_use: number; energy_rest: number; active: boolean; salary: number;
};
export type AnimalState = { house_id: string; slot: number; animal_id: string; rarity: string; state: 'growing' | 'hungry'; cycle_start: number | null; ready_at: number | null };
export type HouseState = { owned: boolean; tier: number; slots: number; bird_slots: number; lot: string };
export type PetState = { pet_id: string; affinity: number; last_care: string | null; active: boolean; linked_class: string | null };
export type TeamFx = {
  stall_ratio: number; seed_discount: number; sales_gold: number; shop_discount: number; auto_sell: boolean; auto_pay: boolean;
  rare_seed: number; seed_refund: number; gerente_cut: number; early_unlock: { crop: string; levels: number } | null; daily_boost: number;
  growth_crop: number; growth_orchard: number; tree_initial: number; cleanup: number; tool_cost: number; harvest_xp: number; golden: number;
  feed_discount: number; animal_production: number; animal_cap: number; animal_double: number; expansion_cost: number; rancheira: boolean;
};
export type LotState = { lot_id: string; ready_at: number; purchase_n: number | null };
export type FarmState = {
  server_now: string; farm_time: number; synced_at: string; last_activity_at: string; offline_cap_hours: number;
  labor_bank: number; labor_per_hour: number; labor_cap_hours: number;
  nickname: string; is_admin: boolean; gold: number; level: number; xp: number; xp_to_next: number | null;
  lots: LotState[]; plots: PlotState[]; trees: TreeState[];
  silo: Record<string, number>; inventory: Record<string, number>; tools: Record<string, string>;
  game_day: string; labor_nominal: number; last_payday: string | null; boosted_sale_day: string | null; pet_swapped_at: string | null;
  auto_sell: string[]; characters: CharacterState[]; pets: PetState[]; pet: { id: string; level: number; factor: number; linked: string | null } | null;
  snack_prices: Record<string, number>; fx: TeamFx;
  animals: AnimalState[]; houses: Record<string, HouseState>; lake: boolean;
};

const ERRORS: Record<string, string> = {
  'cultivo não liberado': 'Esse cultivo ainda não está liberado no seu nível.',
  'cultivo inválido': 'Esse cultivo não vai em canteiro.',
  'canteiro não encontrado': 'Esse canteiro não é seu.',
  'quantidade maior que o Silo': 'Você não tem tudo isso no Silo.',
  'precisa estar logado': 'Sua sessão terminou. Entre de novo.',
  'ouro insuficiente': 'Falta ouro.',
  'lote não é vizinho': 'Só dá para comprar um lote vizinho de um lote seu.',
  'nível insuficiente': 'Seu nível ainda não chega.',
  'precisa de Escritura': 'Essa compra precisa de 1 Escritura.',
  'esse lote já é seu': 'Esse lote já é seu.',
  'todos os lotes já foram comprados': 'Você já comprou todos os lotes.',
  'lote ainda em limpeza': 'O lote ainda está em limpeza.',
  'vaga de árvore não encontrada': 'Essa vaga de árvore não é sua.',
  'fruta inválida': 'Isso não é uma muda de árvore.',
  'ferramenta já está no máximo': 'A ferramenta já está no material mais alto.',
  'personagem já contratado': 'Esse personagem já trabalha para você.',
  'personagem não contratado': 'Esse personagem ainda não foi contratado.',
  'campo cheio': 'Os 3 Slots de Campo estão ocupados. Mande alguém para o banco antes.',
  'nenhum salário atrasado': 'Não há salário atrasado.',
  'sem lanche no inventário': 'Você não tem esse lanche. Compre na Barraca.',
  'sem pontos de habilidade': 'Sem pontos livres: o personagem ganha 1 ponto por nível.',
  'habilidade no máximo': 'Esse nó já está completo.',
  'complete os dois nós antes da Mestria': 'Complete os dois nós do ramo antes da Mestria.',
  'nada para resetar': 'Não há pontos gastos para resetar.',
  'precisa da Mestria': 'Precisa da Mestria da Pesquisa.',
  'ferramenta já está inteira': 'A ferramenta já está inteira.',
  'pet já adotado': 'Esse pet já é seu.',
  'pet não adotado': 'Adote esse pet primeiro.',
  'esse pet já está ativo': 'Esse pet já está ativo.',
  'troca do pet em espera': 'A troca do pet ativo tem espera de 7 dias.',
  'nenhum pet ativo': 'Nenhum pet ativo.',
  'carinho de hoje já foi dado': 'O carinho de hoje já foi dado. Volte amanhã.',
  'semente rara não encontrada': 'Você não tem essa semente rara.',
  'canteiro ocupado': 'O canteiro está ocupado. Colha primeiro.',
  'casa ainda não existe': 'Compre o pasto e espere a limpeza acabar.',
  'animal não é dessa casa': 'Esse animal mora na outra casa.',
  'vaga não existe': 'Essa vaga ainda não existe. Amplie a casa.',
  'vaga do Lago é só para aves': 'As vagas do Lago são só para aves.',
  'vaga ocupada': 'Essa vaga já tem um animal.',
  'vaga vazia': 'Essa vaga está vazia.',
  'casa já está no máximo': 'A casa já tem o máximo de vagas.',
};

function normalize(s: FarmState): FarmState {
  s.gold = Number(s.gold);
  s.xp = Number(s.xp);
  s.xp_to_next = s.xp_to_next === null ? null : Number(s.xp_to_next);
  s.lots ??= []; s.trees ??= []; s.inventory ??= {}; s.tools ??= {};
  s.characters ??= []; s.pets ??= []; s.auto_sell ??= []; s.snack_prices ??= {}; s.animals ??= []; s.houses ??= {};
  for (const c of s.characters) { c.debt = Number(c.debt); c.salary = Number(c.salary); }
  return s;
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<FarmState> {
  if (mock) return normalize(await mock.rpc(fn, args));
  const { data, error } = await supabase!.rpc(fn, args);
  if (error) throw new Error(ERRORS[error.message] ?? 'Não deu certo. Tente de novo.');
  return normalize(data as FarmState);
}

export const getFarm = () => rpc('get_farm');
export const setCrop = (target: string, crop: string | null) => rpc('set_crop', { p_target: target, p_crop: crop });
export const sellAtStall = (item: string, qty: number) =>
  rpc('sell_at_stall', { p_item: item, p_qty: qty, p_idempotency_key: crypto.randomUUID() });
export const buyLot = (lot: string) => rpc('buy_lot', { p_lot: lot });
/** clique do jogador: colhe o que está maduro e planta o que está vazio (canteiro, lote ou null = fazenda toda) */
export const tendFarm = (target: string | null) => rpc('tend_farm', { p_target: target });
export const plantTree = (lot: string, slot: number, fruit: string) => rpc('plant_tree', { p_lot: lot, p_slot: slot, p_fruit: fruit });
export const chopTree = (lot: string, slot: number) => rpc('chop_tree', { p_lot: lot, p_slot: slot });
export const upgradeTool = (cls: string) => rpc('upgrade_tool', { p_class: cls });
export const repairTool = (cls: string) => rpc('repair_tool', { p_class: cls });
export const plantRareTree = (lot: string, slot: number, fruit: string, rarity: string) => rpc('plant_tree', { p_lot: lot, p_slot: slot, p_fruit: fruit, p_rarity: rarity });
export const plantRareSeed = (plot: string, crop: string, rarity: string) => rpc('plant_rare_seed', { p_plot: plot, p_crop: crop, p_rarity: rarity });
export const setAutoSell = (item: string, on: boolean) => rpc('set_auto_sell', { p_item: item, p_on: on });
export const hire = (cls: string) => rpc('hire', { p_class: cls });
export const setSlot = (cls: string, slot: 'field' | 'bench') => rpc('set_slot', { p_class: cls, p_slot: slot });
export const paySalaries = () => rpc('pay_salaries');
export const buySnack = (snack: string, qty: number) => rpc('buy_snack', { p_snack: snack, p_qty: qty });
export const equipSnack = (cls: string, snack: string | null) => rpc('equip_snack', { p_class: cls, p_snack: snack });
export const skillAdd = (cls: string, node: string) => rpc('skill_add', { p_class: cls, p_node: node });
export const skillReset = (cls: string) => rpc('skill_reset', { p_class: cls });
export const skillChoose = (cls: string, crop: string) => rpc('skill_choose', { p_class: cls, p_crop: crop });
export const adoptPet = (pet: string) => rpc('adopt_pet', { p_pet: pet });
export const setActivePet = (pet: string) => rpc('set_active_pet', { p_pet: pet });
export const linkPet = (cls: string) => rpc('link_pet', { p_class: cls });
export const buyAnimal = (house: string, slot: number, animal: string) => rpc('buy_animal', { p_house: house, p_slot: slot, p_animal: animal });
export const removeAnimal = (house: string, slot: number) => rpc('remove_animal', { p_house: house, p_slot: slot });
export const upgradeHouse = (house: string) => rpc('upgrade_house', { p_house: house });
export const carePet = (pet: string) => rpc('care_pet', { p_pet: pet });

// modo de demonstração só no desenvolvimento (?mock=1): estado falso para conferir a tela sem servidor
let mock: { rpc: (fn: string, args: Record<string, unknown>) => Promise<FarmState> } | null = null;
export async function enableMockIfAsked(): Promise<boolean> {
  if (!import.meta.env.DEV || !new URLSearchParams(location.search).has('mock')) return false;
  mock = (await import('./mockFarm')).mockFarm;
  return true;
}

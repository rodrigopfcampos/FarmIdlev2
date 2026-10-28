// Chamadas da fazenda ao servidor. O cliente só manda intenções; o servidor calcula e devolve o estado.
import { supabase } from './supabase';
import type { TreeState } from '../farm/rules';

import type { WeatherView } from '../farm/weather';
export type PlotState = {
  plot_id: string; crop_id: string | null; state: 'empty' | 'growing'; planted_crop_id: string | null;
  planted_at: number | null; ready_at: number | null; harvests_done: number; stalled_reason: string | null; rarity?: string | null;
};
export type CharacterState = {
  class_id: string; slot: 'field' | 'bench'; energy: number; parked: boolean; level: number; work_hours: number;
  skills: Record<string, number>; skill_choice: string | null; reset_week: string | null; debt: number; unpaid_days: number;
  snack_id: string | null; snack_qty: number; cloth_id: string | null; amulet_id: string | null; material: string; durability: number;
  rate: number; energy_max: number; energy_use: number; energy_rest: number; active: boolean; salary: number; leading?: boolean;
};
export type VehicleState = { vehicle_id: string; rarity: string; durability: number; active: boolean; refurb_rarity: string | null; refurb_until: number | null };
export type ExpeditionState = {
  id: string; convoy_id: string; vehicle_id: string; route_id: string; cargo: Record<string, number>; insurance: number; led: boolean; minigame: string;
  started_at: number; returns_at: number; seq: number; repeat_left: number; status: 'travel' | 'back';
};
export type LeadInfo = {
  available: boolean; leading: boolean; vehicles: number; success_pts: number; duration_mult: number; capacity_pct: number; loss_pct: number;
  insurance_pct: number; item_pct: number; deed_pct: number; crit_pts: number; extra_seconds: number;
};
export type CollectedTrip = {
  id: string; vehicle_id: string; route_id: string; seq: number; outcome: 'crit' | 'success' | 'fail'; gold: number; refund: number;
  cargo: Record<string, number>; cargo_back: Record<string, number>; loss_frac: number | null; drops: string[]; report: string;
  insurance: number; minigame: string; chance: number;
};
export type MinigameStart = { id: string; arrows: string[]; limit_ms: number };
export type MinigameEval = { result: 'perfect' | 'done' | 'incomplete' | 'failed'; robot: boolean; errors?: number; done?: number; of?: number };
export type AnimalState = { house_id: string; slot: number; animal_id: string; rarity: string; state: 'growing' | 'hungry'; cycle_start: number | null; ready_at: number | null };
export type HouseState = { owned: boolean; tier: number; slots: number; bird_slots: number; lot: string };
export type PetState = { pet_id: string; affinity: number; last_care: string | null; active: boolean; linked_class: string | null };
export type TeamFx = {
  stall_ratio: number; seed_discount: number; sales_gold: number; shop_discount: number; auto_sell: boolean; auto_pay: boolean;
  rare_seed: number; seed_refund: number; gerente_cut: number; early_unlock: { crop: string; levels: number } | null; daily_boost: number;
  growth_crop: number; growth_orchard: number; tree_initial: number; cleanup: number; tool_cost: number; harvest_xp: number; golden: number;
  feed_discount: number; animal_production: number; animal_cap: number; animal_double: number; expansion_cost: number; rancheira: boolean;
  exp_success: number; exp_duration: number; vehicle_wear: number; dog_recover: number;
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
  vehicles: VehicleState[]; expeditions: ExpeditionState[]; exp_fail_streak: number; lead: LeadInfo | null;
  demand: Record<string, string[]>; demand_tomorrow: Record<string, string[]> | null;
  collected?: CollectedTrip[]; minigame?: MinigameEval;
  weather: WeatherView;
  // fase 7: missões e cartas
  missions: MissionState[]; mission_week: { daily_packs: number; weekly_rewards: number }; reroll_used: boolean; pack_today: boolean;
  cards: CardState[]; new_cards: { serial: number; card_id: string; rarity: string; origin: string }[];
  buffs: BuffState[]; armory: { card_id: string; rarity: string }[]; pity: { rare: number; legendary: number; mythic: number };
  binder_slots: number; prod_ref: { value_h: number; xp_h: number }; collector: Record<string, number>; binder_expand_cost: number;
};
export type MissionState = { kind: 'daily' | 'weekly'; slot: number; id: string; metric: string; target: number; progress: number; done: boolean; reward: { gold?: number; xp?: number } };
export type CardState = { serial: number; card_id: string; rarity: string; state: 'binder' | 'inbox'; inbox_until: string | null; seen: boolean; origin: string };
export type BuffState = { card_id: string; rarity: string; started_at: string; ends_at: string; coin_value: number };

const ERRORS: Record<string, string> = {
  'fuso horário inválido': 'Esse fuso horário não existe.',
  'carta não encontrada': 'Essa carta não está mais no seu fichário.',
  'raridade menor que a do buff ativo': 'Essa carta já está ativa com raridade maior. Use uma de raridade igual ou maior.',
  'já tem 3 buffs ativos': 'Já tem 3 cartas ativas. Espere uma acabar.',
  'essa raridade já está no Armory': 'Essa raridade dessa carta já está no Armory.',
  'fichário já está no máximo': 'O fichário já está no tamanho máximo (200).',
  'a troca grátis de hoje já foi usada': 'A troca grátis de hoje já foi usada.',
  'missão não pode ser trocada': 'Essa missão não pode ser trocada.',
  'não há outra missão disponível': 'Não há outra missão disponível para trocar agora.',
  'semente de outro cultivo': 'Essa semente rara é de outro cultivo. Escolha esse cultivo no lote antes.',
  'esse já é o seu fuso': 'Esse já é o seu fuso horário.',
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
  'rota não existe': 'Essa rota não existe.',
  'número de veículos inválido': 'Escolha de 1 a 4 veículos.',
  'minigame inválido': 'A partida expirou. Comece de novo.',
  'minigame não confere com a expedição': 'A partida não confere com a expedição. Comece de novo.',
  'nível insuficiente para a rota': 'Seu nível ainda não libera essa rota.',
  'essa rota não tem seguro': 'A Feira da Vila não tem seguro.',
  'escolha a carga': 'Escolha o que levar.',
  'o Gerente não pode conduzir agora': 'O Gerente não pode conduzir agora (já está viajando ou com salário atrasado).',
  'veículo não é seu': 'Esse veículo não é seu.',
  'veículo na reforma': 'O veículo está na reforma.',
  'veículo ocupado (viajando ou esperando Receber)': 'O veículo está viajando ou esperando você Receber.',
  'esse veículo não vai até essa rota': 'Esse veículo não vai até essa rota.',
  'carga vazia para um dos veículos': 'Sobrou veículo sem carga. Leve mais ou mande menos veículos.',
  'ouro insuficiente para o seguro': 'Falta ouro para o seguro.',
  'carga maior que a capacidade': 'A carga passa da capacidade dos veículos.',
  'nada para receber': 'Não há nada para receber.',
  'veículo não existe': 'Esse veículo não existe.',
  'você já tem esse veículo': 'Você já tem esse veículo.',
  'veículo já está na reforma': 'O veículo já está na reforma.',
  'veículo já é Mítico': 'O veículo já é Mítico.',
  'falta o Kit de Reforma': 'Falta o Kit de Reforma da raridade nova.',
  'veículo já está inteiro': 'O veículo já está inteiro.',
  'veículo está viajando': 'O veículo está viajando.',
  'item não pode ser juntado': 'Esse item não pode ser juntado.',
  'já é Mítico': 'Já é Mítico.',
  'precisa de 3 iguais': 'Precisa de 3 iguais.',
  'espaço inválido': 'Espaço inválido.',
  'item não serve nesse espaço': 'Esse item não serve nesse espaço.',
  'item não está no inventário': 'Você não tem esse item.',
};

function normalize(s: FarmState): FarmState {
  s.gold = Number(s.gold);
  s.xp = Number(s.xp);
  s.xp_to_next = s.xp_to_next === null ? null : Number(s.xp_to_next);
  s.lots ??= []; s.trees ??= []; s.inventory ??= {}; s.tools ??= {};
  s.characters ??= []; s.pets ??= []; s.auto_sell ??= []; s.snack_prices ??= {}; s.animals ??= []; s.houses ??= {};
  s.vehicles ??= []; s.expeditions ??= []; s.demand ??= {}; s.exp_fail_streak ??= 0; s.lead ??= null; s.demand_tomorrow ??= null;
  for (const x of s.expeditions) x.insurance = Number(x.insurance);
  for (const c of s.collected ?? []) { c.gold = Number(c.gold); c.refund = Number(c.refund); c.insurance = Number(c.insurance); }
  for (const c of s.characters) { c.debt = Number(c.debt); c.salary = Number(c.salary); }
  return s;
}

/** mensagens do servidor em texto do jogo; a de troca de fuso já vem pronta com a data */
function friendly(msg: string): string {
  if (msg.startsWith('o fuso só pode')) return `O${msg.slice(1)}.`;
  return ERRORS[msg] ?? 'Não deu certo. Tente de novo.';
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<FarmState> {
  if (mock) return normalize(await mock.rpc(fn, args));
  const { data, error } = await supabase!.rpc(fn, args);
  if (error) throw new Error(friendly(error.message));
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
// expedições
export async function startMinigame(route: string, vehicles: number, manager: boolean, calm: boolean): Promise<MinigameStart> {
  if (mock) return (await mock.rpc('start_minigame', { p_route: route, p_vehicles: vehicles, p_manager: manager, p_calm: calm })) as unknown as MinigameStart;
  const { data, error } = await supabase!.rpc('start_minigame', { p_route: route, p_vehicles: vehicles, p_manager: manager, p_calm: calm });
  if (error) throw new Error(friendly(error.message));
  return data as MinigameStart;
}
export const launchExpedition = (o: { minigame: string; keys: { k: string; t: number }[]; vehicles: string[]; route: string; cargo: Record<string, number>; insurance: boolean; manager: boolean; repeat: boolean }) =>
  rpc('launch_expedition', { p_minigame: o.minigame, p_keys: o.keys, p_vehicles: o.vehicles, p_route: o.route, p_cargo: o.cargo, p_insurance: o.insurance, p_manager: o.manager, p_repeat: o.repeat });
export const collectExpeditions = (vehicle: string | null) => rpc('collect_expeditions', { p_vehicle: vehicle });
export const buyVehicle = (v: string) => rpc('buy_vehicle', { p_vehicle: v });
export const setActiveVehicle = (v: string) => rpc('set_active_vehicle', { p_vehicle: v });
export const refurbishVehicle = (v: string) => rpc('refurbish_vehicle', { p_vehicle: v });
export const repairVehicle = (v: string) => rpc('repair_vehicle', { p_vehicle: v });
export const mergeItems = (item: string) => rpc('merge_items', { p_item: item });
export const setTimezone = (tz: string) => rpc('set_timezone', { p_tz: tz });
// cartas e missões
export const useCard = (serial: number) => rpc('use_card', { p_serial: serial });
export const armoryPlace = (serial: number) => rpc('armory_place', { p_serial: serial });
export const sellCard = (serial: number) => rpc('sell_card', { p_serial: serial });
export const binderExpand = () => rpc('binder_expand');
export const rerollMission = (slot: number) => rpc('reroll_mission', { p_slot: slot });
export const cardsSeen = () => rpc('cards_seen');
export const equipItem = (cls: string, slot: 'cloth' | 'amulet', item: string | null) => rpc('equip_item', { p_class: cls, p_slot: slot, p_item: item });

// modo de demonstração só no desenvolvimento (?mock=1): estado falso para conferir a tela sem servidor
let mock: { rpc: (fn: string, args: Record<string, unknown>) => Promise<FarmState> } | null = null;
export async function enableMockIfAsked(): Promise<boolean> {
  if (!import.meta.env.DEV || !new URLSearchParams(location.search).has('mock')) return false;
  mock = (await import('./mockFarm')).mockFarm;
  return true;
}

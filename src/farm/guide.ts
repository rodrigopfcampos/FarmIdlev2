// Guia do jogo (08/11): cada mecânica explicada por partes, com uma arte em cada parte.
// Os números vêm das configs (nunca fixos aqui): se a config mudar, o guia muda junto.
import { ANIMAL_RULES, ANIMALS, CARDS, CHARS, CLASSES, EXP, FARM, HOUSES, LOT_RULES, MISSIONS, PETS, SOCIAL, STALL_RATIO, WEATHER } from '../data';

export type GuidePage = { art: string; title: string; text: string[] };
export type GuideTopic = { id: string; name: string; icon: string; pages: GuidePage[] };

const pct = (x: number) => `${Math.round(x * 100)}%`;
const nf = (x: number) => x.toLocaleString('pt-BR', { maximumFractionDigits: 2 });
const cls = (id: string) => CLASSES.find((c) => c.id === id)!;
const pet = (id: string) => PETS.list.find((p) => p.id === id)!;
const usesBy = ['common', 'uncommon', 'rare', 'legendary', 'mythic'].map((r) => (CARDS.rarities as Record<string, { uses: number; name_pt: string }>)[r]);
const fish = ANIMALS.filter((a) => a.house === 'lago');
const ev = WEATHER.night_event;

export const GUIDE: GuideTopic[] = [
  { id: 'comecar', name: 'Começando', icon: 'crop_cenoura_ready', pages: [
    { art: 'char_agricultor_portrait', title: 'Sua fazenda', text: [
      'Você começa com o Agricultor e um lote de lavoura. Plante, colha, venda e use o ouro para comprar mais terra, contratar ajudantes e liberar novidades.',
      'Cada colheita dá XP. Subindo de nível, aparecem cultivos, animais, personagens, veículos e lotes novos.'] },
    { art: 'ui_coin', title: 'O topo da tela', text: [
      'À esquerda: seu nível com a barra de XP e o seu ouro.',
      'À direita: o clima, a equipe em campo (com a energia de cada um), Colher e plantar, Tempos, Missões, Cartas, Amigos, Vila e a Casa.',
      'Passe o mouse em qualquer botão para ver o nome dele.'] },
    { art: 'lot_sign', title: 'O jogo anda sozinho', text: [
      `Com o jogo aberto, você planta e colhe com cliques, de graça. Fechado, a equipe em campo trabalha por você por até ${FARM.offline_cap_hours} h.`,
      'O botão Tempos (ampulheta) mostra quanto falta para cada coisa ficar pronta, separado por atividade.',
      'Os painéis têm um [?] no topo com a explicação completa daquela tela.'] },
  ] },
  { id: 'lavoura', name: 'Lavoura', icon: 'crop_batata_ready', pages: [
    { art: 'crop_batata_ready', title: 'Plantar e colher', text: [
      `Cada lote tem ${FARM.plots_per_crop_lot} canteiros e planta um cultivo só. Clique no lote, escolha o cultivo e todos os canteiros são plantados.`,
      'Quando fica pronto, clique para colher: a produção vai para o Silo. Culturas curtas rendem mais por hora com você jogando; as longas são melhores para quando você sai.',
      'Recorrentes (como o Morango) dão várias colheitas por plantio.'] },
    { art: 'lot_sign', title: 'Comprar terra', text: [
      'Clique na placa de um lote vizinho a um seu para ver preço e nível exigido. Galinheiro e Celeiro podem ser comprados de qualquer lugar.',
      `O lote novo vem com mato e precisa de limpeza (a partir de ${LOT_RULES.cleanup.base_minutes} min, mais a cada compra). Com o Ferreiro em campo a limpeza é ${LOT_RULES.cleanup.other_class_multiplier}× mais rápida.`,
      'Você já pode escolher o cultivo durante a limpeza: ele começa sozinho quando o lote fica limpo.'] },
    { art: 'seedbag_morango', title: 'Sementes raras', text: [
      'A Barraca vende sementes Comuns. Sementes raras caem em pacotes, missões e eventos e multiplicam o ouro e o XP daquele plantio.',
      'O canteiro com semente rara mostra uma estrelinha da cor da raridade.'] },
  ] },
  { id: 'pomar', name: 'Pomar', icon: 'orchard_adult', pages: [
    { art: 'orchard_sprout', title: 'Árvores ficam', text: [
      'O pomar tem 4 vagas de árvore. A muda é paga uma vez e a árvore produz para sempre, sem semente.',
      'Ela passa por muda, jovem e adulta. Depois de adulta, dá frutas de novo a cada ciclo.'] },
    { art: 'orchard_adult', title: 'Colher e trocar', text: [
      'Clique na árvore com frutas para colher. Fora do jogo a equipe colhe (a Rancheira trabalha a 100% no pomar).',
      'Quer uma fruta melhor? Escolha outra muda para a vaga: a árvore antiga é derrubada de graça e a nova cresce do zero.'] },
  ] },
  { id: 'animais', name: 'Animais', icon: 'animal_galinha_f1', pages: [
    { art: 'building_galinheiro', title: 'Galinheiro e Celeiro', text: [
      `Cada casa tem ${HOUSES.galinheiro.slots[0].slots} vagas no começo e pode ser ampliada. Clique numa vaga e escolha o animal entre os liberados pelo seu nível.`,
      'A raridade do animal é sorteada na compra: quanto mais raro, mais ele produz.'] },
    { art: 'animal_vaca_f1', title: 'Produção e ração', text: [
      'Cada animal produz sozinho de tempos em tempos (ovo, leite, lã…). A ração é cobrada no começo de cada ciclo; sem ouro para a ração, ele para.',
      `Clique na casa para coletar a 100%. Fora do jogo a equipe coleta: ${pct(ANIMAL_RULES.collector_efficiency.specialist)} com a Rancheira em campo, ${pct(ANIMAL_RULES.collector_efficiency.other_class)} sem ela.`,
      'O Lago dá vagas extras para aves no Galinheiro.'] },
  ] },
  { id: 'lago', name: 'Lago e Pescador', icon: 'fish_1', pages: [
    { art: 'fish_2', title: 'Peixes no Lago', text: [
      `O Lago funciona como o Galinheiro: ${HOUSES.lago.slots.map((x) => x.slots).join(', ')} vagas, peixe escolhido por você e raridade sorteada na compra.`,
      `Espécies: ${fish.map((f) => `${f.name_pt} (nível ${f.unlock_level})`).join(', ')}.`,
      'Cada peixe produz sozinho e come ração. O peixe vai para o Silo.'] },
    { art: 'char_pescador_portrait', title: 'O Pescador', text: [
      `O Pescador libera no nível ${cls('pescador').unlock_level}. Com ele em campo, a equipe coleta o Lago a ${pct(ANIMAL_RULES.collector_efficiency.specialist)}; sem ele, a ${pct(ANIMAL_RULES.collector_efficiency.other_class)}.`,
      'A ferramenta dele é a Vara de Pescar, que sobe de nível sozinha com a fazenda e é consertada na Forja.',
      'A carta Pesca aumenta o que o Lago rende.'] },
  ] },
  { id: 'equipe', name: 'Equipe', icon: 'char_rancheira_portrait', pages: [
    { art: 'char_rancheira_portrait', title: 'Personagens', text: [
      `Cada personagem libera num nível: ${CLASSES.map((c) => `${c.name_pt} (${c.unlock_level})`).join(', ')}. Contrate na Casa, guia Operadores.`,
      'Cada um tem uma função: Agricultor e Rancheira na lavoura e no pomar, Rancheira nos animais, Ferreiro na limpeza e nos consertos, Comerciante na venda, Gerente nas expedições e salários, Pescador no Lago.'] },
    { art: 'char_ferreiro_portrait', title: 'Campo e Banco', text: [
      `Só ${CHARS.field_slots} trabalham ao mesmo tempo (Slots de Campo); ${CHARS.bench_slots} descansam no Banco.`,
      `Trabalhando, a energia cai ${nf(CHARS.energy.use_per_work_hour)} por hora; no banco sobe ${nf(CHARS.energy.recover_per_rest_hour)}. Com mais gente que vagas, o rodízio é automático: quem chega a ${CHARS.energy.leave_field_at} sai e entra quem tem ${CHARS.energy.enter_field_at} ou mais.`,
      'Cada card mostra a barra de energia, o trabalho por hora e o salário.'] },
    { art: 'snack_coffee', title: 'Salário e lanches', text: [
      `O salário é cobrado à meia-noite. Sem ouro, vira dívida: o personagem fica Desmotivado (rende ${pct(CHARS.salary.unpaid_efficiency)}) e para depois de ${CHARS.salary.stops_after_days} dias devendo. Pague na Casa (ou o Gerente paga sozinho).`,
      'Lanches da Barraca recuperam energia: o personagem come sozinho quando a energia fica baixa.'] },
  ] },
  { id: 'venda', name: 'Silo e Barraca', icon: 'building_celeiro_silo_a', pages: [
    { art: 'building_celeiro_silo_a', title: 'O Silo', text: [
      'Tudo o que você colhe e coleta vai para o Silo (na Casa).',
      'Daqui a produção sai de duas formas: na Barraca ou numa expedição pela Garagem.'] },
    { art: 'result_coins', title: 'Barraca', text: [
      `A Barraca compra na hora, sem risco, a ${pct(STALL_RATIO)} do preço da Feira.`,
      'Com o Comerciante em campo, o preço melhora e você pode marcar produtos para venda automática.',
      'A Barraca também vende sementes, mudas e lanches.'] },
  ] },
  { id: 'expedicoes', name: 'Expedições', icon: 'vehicle_carroca_idle', pages: [
    { art: 'vehicle_carroca_idle', title: 'Vender longe', text: [
      `Na Garagem você manda a produção para longe: ${EXP.routes.map((r) => `${r.name_pt} (nível ${r.unlock_level})`).join(', ')}.`,
      'Quanto mais longe, maior o preço e maior o risco. A carga nunca se perde toda.'] },
    { art: 'vehicle_carro_idle', title: 'Veículos', text: [
      `Os veículos liberam sozinhos: ${EXP.vehicles.map((v) => `${v.name_pt} (${v.unlock_level})`).join(', ')}. Cada um leva uma carga e vai até uma rota máxima.`,
      'Escolha a rota no mapa, o que levar (− / + / MÁX) e clique em Iniciar. Dá para mandar vários veículos juntos.',
      `Cada viagem gasta ${EXP.wear_per_trip_pct}% do veículo: conserte na própria Garagem.`] },
    { art: 'result_chest', title: 'Volta e achados', text: [
      'Quando o veículo volta, clique em Receber na Garagem. O ouro e o relatório aparecem ali.',
      'Cada viagem tem chance de trazer uma carta (maior nas rotas longas). O veículo pode repetir a rota sozinho enquanto você está fora.',
      'O Gerente em campo aumenta a chance de sucesso e encurta a viagem.'] },
  ] },
  { id: 'cartas', name: 'Cartas', icon: 'card_art_01_sun', pages: [
    { art: 'card_art_01_sun', title: 'O que é uma carta', text: [
      'Cartas dão bônus: crescer mais rápido, colher mais, expedição com mais carga, menos energia gasta…',
      `Cada carta vale por usos, pela raridade: ${usesBy.map((r) => `${r.name_pt} ${r.uses}`).join(', ')}. 1 uso = colher um lote inteiro, um pomar, uma casa de animais ou o lago, ou mandar 1 expedição.`,
      'Cada carta só gasta na atividade que ela melhora.'] },
    { art: 'deck_crate', title: 'Usar', text: [
      'A mão fica no canto de baixo. Arraste a carta para o mapa, ou clique nela e depois em Usar.',
      'Ela voa para a barra do canto de cima. Clique numa carta em uso para ver os usos que faltam ou Pausar (ela volta para a mão guardando os usos).',
      `A mão tem ${CARDS.rules.hand.slots_by_level.map(([lv, n]) => `${n} vagas no nível ${lv}`).join(', ')}.`] },
    { art: 'ui_binder_book', title: 'De onde vêm', text: [
      `Qualquer coleta pode trazer uma carta (até ${CARDS.rules.collect_drop.max_per_day} por dia). Também vêm das missões, dos níveis, das expedições, dos pets e da Vila.`,
      'As cartas guardadas ficam no Fichário (botão Cartas). O Álbum registra cada carta que você já teve e dá bônus permanentes.',
      'Quando os usos acabam, a Comum fica gasta e pode ser reparada com ouro; as outras somem.'] },
  ] },
  { id: 'missoes', name: 'Missões', icon: 'item_deed', pages: [
    { art: 'item_deed', title: 'Diárias e semanais', text: [
      `Todo dia aparecem ${MISSIONS.daily.count} missões diárias, com metas do tamanho da sua produção. Cada uma paga ouro e XP.`,
      'Completando todas as diárias, você ganha um pacote de cartas. As semanais (renovam na segunda) dão cartas também.',
      `Não gostou de uma? Dá para trocar ${MISSIONS.daily.free_rerolls} por dia de graça.`] },
  ] },
  { id: 'pets', name: 'Pets', icon: 'pet_idle_cachorro', pages: [
    { art: 'pet_idle_cachorro', title: 'Chegam sozinhos', text: [
      `Os pets chegam sem custo: ${PETS.list.map((p) => `${p.name_pt} no nível ${p.unlock_level}`).join(', ')}. Eles andam no pátio da Casa e todos valem ao mesmo tempo.`,
      `Cachorro: mais sucesso nas expedições. Gato: +${pet('gato').animal_production_pct}% de produção dos animais e recuperação de energia. Papagaio: +${pet('papagaio').sales_gold_pct}% de ouro nas vendas e aviso antes do evento da noite.`] },
    { art: 'result_chest', title: 'Achados e carinho', text: [
      `De tempos em tempos cada pet traz um achado: baú do Cachorro (a cada ${pet('cachorro').find_hours} h), energia do Gato (${pet('gato').find_hours} h), moedas do Papagaio (${pet('papagaio').find_hours} h). Um balão aparece em cima dele: clique no pet.`,
      'Dê 1 carinho por dia em cada pet (Casa → Pets): o nível sobe e o efeito e o achado melhoram.'] },
  ] },
  { id: 'passivas', name: 'Árvore de Passivas', icon: 'tree_leafy_adult', pages: [
    { art: 'tree_leafy_adult', title: 'Pontos de nível', text: [
      'A cada nível você ganha 1 ponto para a Árvore de Passivas (botão do livro no topo).',
      'São 3 caminhos (Natureza, Comércio e Resistência). Os nós do começo abrem os de cima, e cada caminho termina numa passiva especial.',
      'Errou a escolha? 1 reset grátis por semana.'] },
  ] },
  { id: 'clima', name: 'Clima e noite', icon: 'tree_palm_fruit', pages: [
    { art: 'lot_tilled_wet', title: 'Clima', text: [
      'O clima muda a cada 3 horas no seu horário: sol, sol forte, nublado, chuva ou neblina. O ícone no topo mostra o tempo agora e a previsão.',
      'Cada clima dá um bônus pequeno; chuva e neblina deixam as expedições mais arriscadas.'] },
    { art: 'result_jackpot', title: 'Evento da noite', text: [
      `Toda noite, entre ${ev.window[0]} e ${ev.window[1]}, acontece um evento de ${ev.duration_minutes} min: ${ev.events.map((e) => e.name_pt).join(', ')}.`,
      `Um aviso aparece ${ev.warning_minutes} min antes. Vale também para a produção de quem está fora.`] },
  ] },
  { id: 'vizinhos', name: 'Amigos e Vila', icon: 'building_estufa', pages: [
    { art: 'building_estufa', title: 'Visitar e ajudar', text: [
      'No botão Amigos você procura vizinhos pelo apelido, faz amizade e visita fazendas.',
      `Na visita, Ajudar dá +${SOCIAL.help.growth_pct}% de crescimento por ${SOCIAL.help.growth_minutes} min num lote do dono (ou corta a limpeza). Você pode ajudar ${SOCIAL.help.given_per_day} vezes por dia e ganha XP.`,
      'Também dá para Curtir e deixar um recado com emojis.'] },
    { art: 'item_feed', title: 'Encomenda da Vila', text: [
      'Toda semana a Vila faz uma encomenda coletiva. Doe produção do Silo ou ouro para somar pontos.',
      'Batendo a meta, você ganha carta e título. Depois do nível 50, o XP vira Estrelas da Vila para trocar por pacotes e sementes raras.'] },
  ] },
];

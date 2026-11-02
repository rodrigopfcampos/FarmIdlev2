-- Limpeza v3 (pedido do dono em 02/11/2026, depois do mapa do código): tira do banco as funções de sistemas que acabaram
-- (itens de funcionário, Kits e reforma, compra de veículo, Forja vendendo ferramenta, árvores dos personagens,
-- adoção/vínculo de pet, Armory à mão) e as que ninguém chamava mais. Nenhum dado é apagado (ledger e inventário ficam).
drop function if exists public.adopt_pet(p_pet text);
drop function if exists public.armory_place(p_serial bigint);
drop function if exists public.buy_vehicle(p_vehicle text);
drop function if exists public.equip_item(p_class text, p_slot text, p_item text);
drop function if exists public.labor_rate(p_user uuid);
drop function if exists public.link_pet(p_class text);
drop function if exists public.merge_items(p_item text);
drop function if exists public.pick_rarity(p_odds jsonb);
drop function if exists public.refurbish_vehicle(p_vehicle text);
drop function if exists public.set_active_pet(p_pet text);
drop function if exists public.skill_add(p_class text, p_node text);
drop function if exists public.skill_choose(p_class text, p_crop text);
drop function if exists public.skill_reset(p_class text);
drop function if exists public.upgrade_tool(p_class text);
drop function if exists public.use_card(p_serial bigint);
drop function if exists public.admin_grant_item(p_user uuid, p_item text, p_qty integer, p_reason text);

-- versão atual (veio de supabase/migrations/20261030000100_phase8b_village.sql)
create or replace function public.village_settle(p_user uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  c jsonb := public.config_get('village') -> 'encomenda'; o record; r jsonb; n int; k int; v_title text;
begin
  for o in select vo.* from public.village_orders vo
           where vo.ends_at <= now() and exists (select 1 from public.village_donations d where d.order_id = vo.id and d.user_id = p_user)
             and not exists (select 1 from public.village_rewards w where w.order_id = vo.id and w.user_id = p_user)
           order by vo.id loop
    r := public.village_result(o.id, p_user);
    n := 0; v_title := null;
    if (r ->> 'qualified')::boolean then
      if (r ->> 'goal_reached')::boolean then n := n + (c -> 'reward' ->> 'card_if_goal_and_qualified')::int; v_title := c -> 'titles' ->> 'participant'; end if;
      if (r ->> 'top')::boolean and ((r ->> 'goal_reached')::boolean or not (c -> 'reward' ->> 'top_needs_goal')::boolean) then
        n := n + (c -> 'reward' ->> 'card_if_top')::int; v_title := c -> 'titles' ->> 'top';
      end if;
    end if;
    insert into public.village_rewards (order_id, user_id, points, cards, title) values (o.id, p_user, (r ->> 'points')::numeric, n, v_title)
      on conflict do nothing;
    if found then
      for k in 1 .. n loop perform public.draw_card(p_user, 'encomenda'); end loop;
      insert into public.audit_log (actor_id, action, target_user_id, data)
        values (null, 'village.reward', p_user, jsonb_build_object('order', o.id, 'cards', n, 'title', v_title) || r);
    end if;
  end loop;
end;
$$;

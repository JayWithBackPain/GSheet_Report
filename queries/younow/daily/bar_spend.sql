with
-- ── 共用：bars→USD 30 日 rolling 換算率 ──────────────────
    daily_agg as (
        select
            date_trunc('day', st.datecreated) as dt,
            sum(amountdollars) as total_cost,
            sum(amountbars) as total_bars
        from store_transaction st
                 left join users_data ud on st.userid = ud.userid
        where st.datecreated >= current_date - 10 - interval '30 days'
    and st.status in ('AUTHORIZED','COMPLETED')
    and st.productid not in (154, 155)
    and ud.terminated = 0
group by 1
    ),
    rolling_ratio as (
select
    dt,
    sum(total_cost) over (order by dt rows between 29 preceding and current row)::float
    / sum(total_bars) over (order by dt rows between 29 preceding and current row) as daily_ratio
from daily_agg
    ),

    -- ── dino（global-only、近 5 天）──────────────────────────────
    dino_agg as (
select
    date_trunc('day', flow.createdat) as dt,
    sum(coins) - sum(
    case when optiontype = g.winner then
    case when optiontype in ('tiger','dragon') then coins*2 else coins*22 end
    else 0 end
    ) as bar_burned
from game.coin_pool_game_flow flow
    inner join game.games g on g.id = flow.gameId::integer
-- [優化]: 直接將 -5 條件推到最底層掃描，不浪費資源掃描 -10 到 -6 天的資料
where flow.createdAt >= current_date - 5
  and g.winner is not null
group by 1
    ),
    dino as (
select
    d.dt,
    'global' as region,
    d.bar_burned * rr.daily_ratio as dino_burn
from dino_agg d
    left join rolling_ratio rr on d.dt = rr.dt
    ),

    -- ── plinko（global/regional/na、近 10 天）───────────────────
    plinko_raw as (
select
    gr.userid,
    date_trunc('day', gt.datecreated) as dt,
    sum(gr.bet_size) as bet_size,
    sum(gr.return_size) as return_size
from games_records gr
    inner join public.goodie_transaction gt on gr.extbetid = gt.id
where gt.datecreated >= current_date - 10
  and gt.amountbars > 0
group by 1, 2
    ),
    plinko_src as (
select
    pr.dt,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    sum( (pr.bet_size - pr.return_size) * rr.daily_ratio ) as bars_burned
from plinko_raw pr
    left join users_data ud on pr.userid = ud.userid
    left join rolling_ratio rr on rr.dt = pr.dt
group by 1,2,3
    ),
    plinko as (
-- [優化]: 在極小的聚合表上做 UNION，速度極快
select dt, 'global' as region, sum(bars_burned) as plinko_burn from plinko_src group by 1
union all
select dt, 'na' as region, sum(bars_burned) from plinko_src where is_na group by 1
union all
select dt, locale as region, sum(bars_burned) from plinko_src group by 1,2
    ),


    casino_bet as (
select
    date_trunc('day', datecreated) as dt,
    fromuserid as userid,
    sum(amountbars) as bars
from goodie_transaction
where touserid = 60080959
  and datecreated >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE))
  and status = 'DELIVERED'
group by 1,2
    ),
    casino_win as (
select
    date_trunc('day', datecreated) as dt,
    userid,
    sum(amountbars) as bars
from store_transaction
where productid in (154, 155)
  and sourceextra like '%bars_game%'
  and datecreated >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE))
group by 1,2
    ),
    casino_src as (
select
    bet.dt,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    sum(bet.bars * rr.daily_ratio) as bet_bars,
    sum(coalesce(win.bars, 0) * rr.daily_ratio) as win_bars
from casino_bet bet
    left join casino_win win on bet.dt = win.dt and bet.userid = win.userid
    left join users_data ud on bet.userid = ud.userid
    left join rolling_ratio rr on bet.dt = rr.dt
group by 1,2,3
    ),
    casino as (
select dt, 'global' as region, sum(bet_bars - win_bars) as casino_burn from casino_src group by 1
union all
select dt, 'na' as region, sum(bet_bars - win_bars) from casino_src where is_na group by 1
union all
select dt, locale as region, sum(bet_bars - win_bars) from casino_src group by 1,2
    ),


    producers_ranks as (
select
    date_trunc('day', datecreated) as dt,
    fromuserid as userid,
    max(case when reserved_int_5 = -1 then 0 else reserved_int_5 end) as crown_levels
from public.goodie_transaction
where datecreated >= current_date - 10
group by 1,2
    ),
    spend_combined as (
-- [優化]: 將日期條件推至 UNION 內部，減少大量的表掃描與記憶體交換
select date_trunc('day', datecreated) as dt, fromuserid as userid, amountbars as total_bars, 0 as total_diamonds, 'gift' as spent_type
from public.goodie_transaction
where datecreated >= current_date - 10
  and status in ('DELIVERED','FRAUD')
  and amountbars <> 0
  and objecttype <> 'SPIN_FREE'
  and touserid not in (60774865,60080959)
union all
select date_trunc('day', st.datecreated) as dt, userid, -1 * amountbars as total_bars, 0 as total_diamonds,
    case when sp.id in (164,165) then 'badge' else null end as spent_type
from store_transaction st
    left join store_product sp on st.productid = sp.id
where st.datecreated >= current_date - 10
  and st.productid <> 50
  and st.status in ('AUTHORIZED','COMPLETED')
  and st.amountbars < 0
union all
select date_trunc('day', datecreated) as dt, userid, 0 as total_bars, -1*totaldiamonds::float/10000 as total_diamonds, 'badge' as spent_type
from diamond_transactions
where datecreated >= current_date - 10
  and type = 'BADGE_PURCHASE'
  and status = 'COMPLETED'
    ),
    spend_src as (
select
    combined.dt,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    case
    -- [優化]: 用 GREATEST 替換肥大的 case when，並一次性計算 crown_tier
    when coalesce(cl.crown_levels, GREATEST(ud.globalspenderrank, 0)) >= 13 then 'golden crown'
    when coalesce(cl.crown_levels, GREATEST(ud.globalspenderrank, 0)) >= 11 then 'titanium crown'
    when coalesce(cl.crown_levels, GREATEST(ud.globalspenderrank, 0)) >= 6 then 'platinum crown'
    when coalesce(cl.crown_levels, GREATEST(ud.globalspenderrank, 0)) >= 1 then 'red crown'
    else 'no crown'
    end as crown_tier,
    sum(combined.total_bars * rr.daily_ratio) as total_spent,
    sum(case when combined.spent_type = 'gift' then combined.total_bars * rr.daily_ratio else 0 end) as total_gift_spent,
    sum(case when combined.spent_type = 'badge' then combined.total_bars * rr.daily_ratio else 0 end) as total_badge_spent,
    sum(case when combined.spent_type = 'badge' then combined.total_diamonds else 0 end) as total_badge_spent_internal
from spend_combined combined
    left join producers_ranks cl on combined.dt = cl.dt and combined.userid = cl.userid
    left join users_data ud on combined.userid = ud.userid
    left join rolling_ratio rr on combined.dt = rr.dt
group by 1,2,3,4
    ),
    spend as (
select
    dt, 'global' as region,
    sum(total_spent) as total_spent,
    sum(total_gift_spent) as total_gift_spent,
    sum(total_badge_spent) as total_badge_spent,
    sum(total_badge_spent_internal) as total_badge_spent_internal,
    sum(case when crown_tier = 'golden crown' then total_spent else 0 end) as g_spent,
    sum(case when crown_tier = 'titanium crown' then total_spent else 0 end) as t_spent,
    sum(case when crown_tier = 'platinum crown' then total_spent else 0 end) as p_spent,
    sum(case when crown_tier = 'red crown' then total_spent else 0 end) as r_spent,
    sum(case when crown_tier = 'no crown' then total_spent else 0 end) as n_spent
from spend_src group by 1
union all
select
    dt, 'na' as region,
    sum(total_spent), sum(total_gift_spent), sum(total_badge_spent), sum(total_badge_spent_internal),
    sum(case when crown_tier = 'golden crown' then total_spent else 0 end),
    sum(case when crown_tier = 'titanium crown' then total_spent else 0 end),
    sum(case when crown_tier = 'platinum crown' then total_spent else 0 end),
    sum(case when crown_tier = 'red crown' then total_spent else 0 end),
    sum(case when crown_tier = 'no crown' then total_spent else 0 end)
from spend_src where is_na group by 1
union all
select
    dt, locale as region,
    sum(total_spent), sum(total_gift_spent), sum(total_badge_spent), sum(total_badge_spent_internal),
    sum(case when crown_tier = 'golden crown' then total_spent else 0 end),
    sum(case when crown_tier = 'titanium crown' then total_spent else 0 end),
    sum(case when crown_tier = 'platinum crown' then total_spent else 0 end),
    sum(case when crown_tier = 'red crown' then total_spent else 0 end),
    sum(case when crown_tier = 'no crown' then total_spent else 0 end)
from spend_src group by 1,2
    ),

                   -- ── (dt,region) spine：對齊四個指標各自的日期/地區覆蓋 ──────
    spine as (
select dt, region from dino
union select dt, region from plinko
union select dt, region from casino
union select dt, region from spend
    )

select
    s.dt as dt,
    rtrim(s.region)::varchar as region,
    d.dino_burn,
    p.plinko_burn,
    sc.casino_burn,
    sp.total_spent,
    sp.total_gift_spent,
    sp.total_badge_spent,
    sp.total_badge_spent_internal,
    sp.g_spent,
    sp.t_spent,
    sp.p_spent,
    sp.r_spent,
    sp.n_spent
from spine s
         left join dino   d  on d.dt  = s.dt and d.region  = s.region
         left join plinko p  on p.dt  = s.dt and p.region  = s.region
         left join casino sc on sc.dt = s.dt and sc.region = s.region
         left join spend  sp on sp.dt = s.dt and sp.region = s.region
where s.dt >= current_date - 4;
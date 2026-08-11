with
    -- 共用：producer crown level（給 revenue 段的 crown 分級 fallback 用）
    producers_ranks as (
        select
            date_trunc('day', datecreated) as dt,
            fromuserid,
            max(case when reserved_int_5 = -1 then 0 else reserved_int_5 end) as crown_levels
        from public.goodie_transaction
        group by 1,2
    ),

    -- ── revenue 段（近 10 天）────────────────────────────────────
    rev_src as (
        select
            date_trunc('day', st.datecreated) as dt,
            st.userid as userid,
            case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
            case when ud.country in ('US','CA') then true else false end as is_na,
            case when sp.type in ('SUBSCRIPTION','SUBSCRIPTION_RENEWAL') then true else false end as is_sub,
            coalesce(case when ud.globalspenderrank is not null and ud.globalspenderrank < 0 then 0 else ud.globalspenderrank end, pr.crown_levels) as crown_levels,
            sum(amountdollars) as ext_revenue,
            sum(-1*totaldiamonds) as int_revenue
        from store_transaction st
                 left join public.diamond_transactions dt on st.exttransactionid = dt.exttransactionid and (dt.status = 'COMPLETED' or dt.status = 'AUTHORIZED')
                 left join public.users_data ud on st.userid = ud.userid
                 left join producers_ranks pr on date(st.datecreated) = pr.dt and st.userid = pr.fromuserid
    left join store_product sp on st.productid = sp.id
where st.datecreated >= current_Date - 10
  and st.status in ('AUTHORIZED','COMPLETED')
  and terminated = 0
group by 1,2,3,4,5,6
    ),
    rev_agg as (
select
    dt, region,
    sum(ext_revenue) as revenue,
    sum(case when is_sub then ext_revenue else 0 end) as sub_revenue,
    sum(case when not is_sub then ext_revenue else 0 end) as bar_revenue,
    sum(case when crown_levels>=13 then ext_revenue else 0 end)::float as g_revenue,
    sum(case when crown_levels>=11 and crown_levels < 13 then ext_revenue else 0 end)::float as t_revenue,
    sum(case when crown_levels>=6 and crown_levels < 11 then ext_revenue else 0 end)::float as p_revenue,
    sum(case when crown_levels>=1 and crown_levels < 6 then ext_revenue else 0 end)::float as r_revenue,
    sum(case when crown_levels=0 then ext_revenue else 0 end)::float as n_revenue,
    count(distinct(case when ext_revenue > 0 then userid else null end)) as ext_payers,
    count(distinct(case when int_revenue > 0 then userid else null end)) as int_payers,
    count(distinct userid) as payers,
    count(distinct(case when crown_levels>=13 and ext_revenue > 0 then userid else null end)) as g_payers,
    count(distinct(case when crown_levels>=11 and crown_levels < 13 and ext_revenue > 0 then userid else null end)) as t_payers,
    count(distinct(case when crown_levels>=6 and crown_levels < 11 and ext_revenue > 0 then userid else null end)) as p_payers,
    count(distinct(case when crown_levels>=1 and crown_levels < 6 and ext_revenue > 0 then userid else null end)) as r_payers,
    count(distinct(case when crown_levels=0 and ext_revenue > 0 then userid else null end)) as n_payers
from (
    select dt, 'global' as region, userid, is_sub, crown_levels, ext_revenue, int_revenue from rev_src where ext_revenue > 0 or int_revenue > 0
    union all
    select dt, 'na' as region, userid, is_sub, crown_levels, ext_revenue, int_revenue from rev_src where is_na and (ext_revenue > 0 or int_revenue > 0)
    union all
    select dt, locale as region, userid, is_sub, crown_levels, ext_revenue, int_revenue from rev_src where ext_revenue > 0 or int_revenue > 0
    ) x
group by dt, region
    ),

    -- ── internal_revenue 段（近 10 天；含 diamond_transactions_est）──
    int_src as (
select
    date_trunc('day', st.datecreated) as dt,
    st.userid,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    sum(total_amountdollars) as int_revenue
from (
    (select coalesce(-totaldiamonds,0)/10000+amountdollars as total_amountdollars,
    st.userid,
    st.datecreated,
    st.status
    from public.store_transaction st
    left join public.diamond_transactions dt on st.exttransactionid = dt.exttransactionid and (dt.status = 'COMPLETED' or dt.status = 'AUTHORIZED')
    where st.exttransactionid like 'diamond%'
    and amountdollars <= 0)
    union all
    (select -totaldiamonds/10000 as total_amountdollars,
    userid,
    datecreated,
    status
    from public.diamond_transactions_est
    where type in ('BUY_GIFT_SUBSCRIPTION','BADGE_PURCHASE'))
    ) st
    join public.users_data ud on st.userid = ud.userid
where st.datecreated >= current_date - 10
  and st.datecreated < current_date
  and status in ('AUTHORIZED','COMPLETED')
  and terminated = 0
group by 1,2,3,4
    ),
    int_agg as (
select dt, region, sum(int_revenue) as int_rev_est
from (
    select dt, 'global' as region, int_revenue from int_src
    union all
    select dt, 'na' as region, int_revenue from int_src where is_na
    union all
    select dt, locale as region, int_revenue from int_src
    ) x
group by dt, region
    ),

    -- ── payers 段（近 10 天輸出，母體回溯 40 天供 lag reactivation）──
    paying as (
select
    date_trunc('day', st.datecreated) as dt,
    st.userid as userid,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    sum(amountdollars) as ext_revenue
from store_transaction st
    left join public.users_data ud on st.userid = ud.userid
where st.datecreated >= current_date - 10 - '30 days'::interval
  and status in ('AUTHORIZED','COMPLETED')
  and terminated = 0
  and amountdollars > 0
group by 1,2,3,4
    ),
    paying_agg as (
select *,
    lag(dt) over (partition by userid order by dt) as prev_dt
from paying
    ),
    payers_agg as (
select
    dt, region,
    sum(case when prev_dt is not null and datediff('day',prev_dt,dt) >7 then ext_revenue else 0 end) as reactived_revenue,
    sum(case when prev_dt is not null and datediff('day',prev_dt,dt)<=7 then ext_revenue else 0 end) as continuing_revenue,
    count(distinct(case when prev_dt is not null and datediff('day',prev_dt,dt)>7 then userid else null end)) as reactived_payers,
    count(distinct(case when prev_dt is not null and datediff('day',prev_dt,dt)<=7 then userid else null end)) as continuing_payers
from (
    select dt, 'global' as region, userid, prev_dt, ext_revenue from paying_agg
    union all
    select dt, 'na' as region, userid, prev_dt, ext_revenue from paying_agg where is_na
    union all
    select dt, locale as region, userid, prev_dt, ext_revenue from paying_agg
    ) x
group by dt, region
    ),

    -- ── (dt,region) spine：對齊三段各自的日期覆蓋 ────────────────
    spine as (
select dt, region from rev_agg
union select dt, region from int_agg
union select dt, region from payers_agg
    )

select
    date(s.dt) as dt,
    rtrim(s.region)::varchar as region,
    r.revenue,
    r.sub_revenue,
    r.bar_revenue,
    r.g_revenue,
    r.t_revenue,
    r.p_revenue,
    r.r_revenue,
    r.n_revenue,
    r.ext_payers,
    r.int_payers,
    r.payers,
    r.g_payers,
    r.t_payers,
    r.p_payers,
    r.r_payers,
    r.n_payers,
    ir.int_rev_est as int_rev,
    pa.reactived_revenue,
    pa.continuing_revenue,
    pa.reactived_payers,
    pa.continuing_payers
from spine s
         left join rev_agg    r  on r.dt  = s.dt and r.region  = s.region
         left join int_agg    ir on ir.dt = s.dt and ir.region = s.region
         left join payers_agg pa on pa.dt = s.dt and pa.region = s.region
where s.dt > current_date - 5;

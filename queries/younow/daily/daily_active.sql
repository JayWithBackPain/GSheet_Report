with broadcast as (
    select
        date_trunc('day',date_created) as dt,
        user_id as userid,
        case when partner > 0 then true else false end as is_partner,
        max(case when origin_id = 1 then 1 else 0 end) as is_ios_bc,
        max(case when origin_id = 2 then 1 else 0 end) as is_aos_bc,
        max(case when origin_id = 3 then 1 else 0 end) as is_web_bc,
        sum(length)::float/3600 as duration_h
    from archivedbroadcasts
    where date_created >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE))
    group by 1,2,3
),
     mysource as (
         select
             date_trunc('day',day) as dt,
             da.userid,
             case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
             case when ud.country in ('US','CA') then true else false end as is_na,
             case when ios_logins > 0 then true else false end as ios_login,
             case when android_logins > 0 then true else false end as aos_login,
             case when web_logins > 0 then true else false end as web_login,
             case when bc.userid is not null then true else false end as is_bcr,
             case when is_ios_bc > 0 then true else false end as ios_bc,
             case when is_aos_bc > 0 then true else false end as aos_bc,
             case when is_web_bc > 0 then true else false end as web_bc,
             is_partner,
             case when da.userdays = 0 then true else false end as is_new,
             duration_h
         from dailyactives da
                  left join users_data ud on da.userid = ud.userid
                  left join broadcast bc on da.userid = bc.userid and bc.dt = date_trunc('day',day)
         where da.day >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE))
     ),
     global_agg as (
         select
             dt,
             'global' as region,
             count(distinct(userid)) as dau,
             count(distinct(case when web_login then userid else null end)) as dau_web,
             count(distinct(case when ios_login then userid else null end)) as dau_ios,
             count(distinct(case when aos_login then userid else null end)) as dau_aos,
             count(distinct(case when is_new then userid else null end)) as nru,
             count(distinct(case when is_new and web_login then userid else null end)) as nru_web,
             count(distinct(case when is_new and ios_login then userid else null end)) as nru_ios,
             count(distinct(case when is_new and aos_login then userid else null end)) as nru_aos,
             count(distinct(case when is_bcr then userid else null end)) as dab,
             count(distinct(case when web_bc then userid else null end)) as dab_web,
             count(distinct(case when ios_bc then userid else null end)) as dab_ios,
             count(distinct(case when aos_bc then userid else null end)) as dab_aos,
             count(distinct(case when is_partner then userid else null end)) as dab_partner,
             sum(duration_h) as bc_hours,
             sum(case when is_partner then duration_h else 0 end) as bc_hours_partner,
             sum(case when not is_partner then duration_h else 0 end) as bc_hours_npartner
         from mysource
         group by 1,2
     ),
     regional_agg as (
         select
             dt,
             locale as region,
             count(distinct(userid)) as dau,
             count(distinct(case when web_login then userid else null end)) as dau_web,
             count(distinct(case when ios_login then userid else null end)) as dau_ios,
             count(distinct(case when aos_login then userid else null end)) as dau_aos,
             count(distinct(case when is_new then userid else null end)) as nru,
             count(distinct(case when is_new and web_login then userid else null end)) as nru_web,
             count(distinct(case when is_new and ios_login then userid else null end)) as nru_ios,
             count(distinct(case when is_new and aos_login then userid else null end)) as nru_aos,
             count(distinct(case when is_bcr then userid else null end)) as dab,
             count(distinct(case when web_bc then userid else null end)) as dab_web,
             count(distinct(case when ios_bc then userid else null end)) as dab_ios,
             count(distinct(case when aos_bc then userid else null end)) as dab_aos,
             count(distinct(case when is_partner then userid else null end)) as dab_partner,
             sum(duration_h) as bc_hours,
             sum(case when is_partner then duration_h else 0 end) as bc_hours_partner,
             sum(case when not is_partner then duration_h else 0 end) as bc_hours_npartner
         from mysource
         group by 1,2
     ),
     na_agg as (
         select
             dt,
             'na' as region,
             count(distinct(userid)) as dau,
             count(distinct(case when web_login then userid else null end)) as dau_web,
             count(distinct(case when ios_login then userid else null end)) as dau_ios,
             count(distinct(case when aos_login then userid else null end)) as dau_aos,
             count(distinct(case when is_new then userid else null end)) as nru,
             count(distinct(case when is_new and web_login then userid else null end)) as nru_web,
             count(distinct(case when is_new and ios_login then userid else null end)) as nru_ios,
             count(distinct(case when is_new and aos_login then userid else null end)) as nru_aos,
             count(distinct(case when is_bcr then userid else null end)) as dab,
             count(distinct(case when web_bc then userid else null end)) as dab_web,
             count(distinct(case when ios_bc then userid else null end)) as dab_ios,
             count(distinct(case when aos_bc then userid else null end)) as dab_aos,
             count(distinct(case when is_partner then userid else null end)) as dab_partner,
             sum(duration_h) as bc_hours,
             sum(case when is_partner then duration_h else 0 end) as bc_hours_partner,
             sum(case when not is_partner then duration_h else 0 end) as bc_hours_npartner
         from mysource
         where is_na
         group by 1,2
     )
select * from global_agg
union all
select * from regional_agg
union all
select * from na_agg
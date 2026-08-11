with mysource as (
    select
        date_trunc('day',te.dateday) as dt,
        te.userid,
        case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
        case when ud.country in ('US','CA') then true else false end as is_na,
        sum(points)::float/3600 as view_hours
    from trackevents te
             left join users_data ud on te.userid = ud.userid
    where event = 'VIEWTIME'
      and te.broadcastid > 0
      and te.doorid > 0
      and te.userid > 0
      and te.points > 0
      and te.points < 100000
      and te.dateday>=current_date-10
    group by 1,2,3,4
),
     global_agg as (
         select
             dt,
             'global' as region,
             count(distinct(userid)) as live_dau,
             sum(view_hours) as total_view_hours
         from mysource
         group by 1,2
     ),
     regional_agg as (
         select
             dt,
             locale as region,
             count(distinct(userid)) as live_dau,
             sum(view_hours) as total_view_hours
         from mysource
         group by 1,2
     ),
     na_agg as (
         select
             dt,
             'na' as region,
             count(distinct(userid)) as live_dau,
             sum(view_hours) as total_view_hours
         from mysource
         where is_na
         group by 1,2
     )

select * from global_agg
union all
select * from regional_agg
union all
select * from na_agg
with mysource as (
    select
        date_trunc('day',gt.datecreated) as dt,
        fromuserid,
        case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
        case when ud.country in ('US','CA') then true else false end as is_na,
        sum(reserved_int_4) as likes
    from public.goodie_transaction gt
             left join users_data ud on gt.fromuserid = ud.userid
    where gt.datecreated >= current_date- 10
    group by 1,2,3,4
),
     global_agg as (
         select
             dt,
             'global' as region,
             sum(likes) as total_likes
         from mysource
         group by 1,2
     ),
     regional_agg as (
         select
             dt,
             locale as region,
             sum(likes) as total_likes
         from mysource
         group by 1,2
     ),
     na_agg as (
         select
             dt,
             'na' as region,
             sum(likes) as total_likes
         from mysource
         where is_na
         group by 1,2
     )

select * from global_agg
union all
select * from regional_agg
union all
select * from na_agg
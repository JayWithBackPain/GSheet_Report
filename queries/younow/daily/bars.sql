with mysource as (
    select
        date_trunc('day',bt.datecreated) as dt,
        bt.userid,
        case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
        case when ud.country in ('US','CA') then true else false end as is_na,
        product_name||'-'||product_currency||' paid' as item,
        case when cost > 0 then 'paid' else 'free' end as is_paid,
        sum(bars) as total_bars
    from datamart_bar_transactions bt
             left join users_data ud on bt.userid = ud.userid
    where bt.datecreated >= current_date- 10
      and product_name not in ('Games Free Bars Reward','Games Paid Bars Reward')
    group by 1,2,3,4,5,6
),
     global_agg as (
         select
             dt,
             'global' as region,
             sum(case when is_paid ='free' then total_bars else 0 end) as free_bars,
             sum(case when item like '%Mission%' then total_bars else 0 end) as mission_bars
         from mysource
         group by 1,2
     ),
     regional_agg as (
         select
             dt,
             locale as region,
             sum(case when is_paid ='free' then total_bars else 0 end) as free_bars,
             sum(case when item like '%Mission%' then total_bars else 0 end) as mission_bars
         from mysource
         group by 1,2
     ),
     na_agg as (
         select
             dt,
             'na' as region,
             sum(case when is_paid ='free' then total_bars else 0 end) as free_bars,
             sum(case when item like '%Mission%' then total_bars else 0 end) as mission_bars
         from mysource
         where is_na
         group by 1,2
     )

select * from global_agg
union all
select * from regional_agg
union all
select * from na_agg
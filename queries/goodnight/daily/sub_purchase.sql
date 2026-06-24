with base_data as (
	select
		date_trunc('day',purchased_at) as dt,
		case when ppu.country_code in ('TW','KR','JP','TH','US','HK','MO','SG','MY','PH') then ppu.country_code else 'Others' end as region,
		sum(usd_price) as revenue,
		count(distinct user_id) as payers
	from fact.subscription_purchase sp
		     left join prod_pg_users ppu on sp.user_id = ppu.id
	where purchased_at >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
	group by 1,2
)
select dt,'global' as region,sum(revenue) as revenue,sum(payers) as payers from base_data group by 1,2
union all  select * from base_data;
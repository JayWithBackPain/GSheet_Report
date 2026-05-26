select
	date_trunc('day',purchased_at) as dt,
	'global' as region,
	sum(usd_price) as revenue,
	count(distinct user_id) as payers
from fact.can_purchase
where purchased_at >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
group by 1,2
select
	dt,
	'global' as region,
	sum(gross_revenue) as revenue
from admob_revenue
where dt >= DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE
group by 1,2
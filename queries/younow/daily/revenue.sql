with producers_ranks as (
	select date(datecreated),fromuserid,max(case when reserved_int_5 = -1 then 0 else reserved_int_5 end) as crown_levels
from public.goodie_transaction
group by 1,2
	),

	mysource as (
select date_trunc('day',st.datecreated) as day,
	st.userid,
	ud.locale,
	coalesce(crown_levels,case when globalspenderrank<=0 then 0 else globalspenderrank end) as crown_levels,
	case when amountdollars = 0 then 'internal' else 'external' end as txn_type,
	case when language in ('en','es','de','tr') then language
	when language in ('ar') and country in ('SA','AE','KW') then 'mena-gulf'
	when language in ('fr','ar') and country in ('MA','DZ','CH','US','ES','IT','GB','CA','FR') then 'mena-na'
	when language in ('ar') then 'mena-other'
	else 'other' end as language,
	sum(total_amountdollars) as dollars,
	count(distinct st.userid) as payers_ct
from
	(
	(select coalesce(-totaldiamonds,0)/10000+amountdollars as total_amountdollars,
	st.userid,
	st.touserid,
	st.storename,
	st.amountdollars,
	st.datecreated,
	st.status,
	st.productid,
	st.amountbars,
	'non_diamond_sub' as diamond_sub_flag
	from public.store_transaction st left join public.diamond_transactions dt on st.exttransactionid = dt.exttransactionid and (dt.status = 'COMPLETED' or dt.status = 'AUTHORIZED')
	where (amountdollars > 0 or st.exttransactionid like 'diamond%')
	)
	union all
	(
	select -totaldiamonds/10000 as total_amountdollars,
	userid,
	0 as touserid,
	'WEB' as storename,
	0 as amountdollars,
	datecreated,
	status,
	-1 as productid,
	0 as amountdollars,
	'diamond_sub' as diamond_sub_flag
	from public.diamond_transactions_est
	where type = 'BUY_GIFT_SUBSCRIPTION'
	)
	) st
	join public.users_data ud on st.userid = ud.userid
	left join producers_ranks pr on date(st.datecreated) = pr.date and st.userid = pr.fromuserid
where st.datecreated>=DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))
  and st.datecreated < current_date
  and status in ('AUTHORIZED','COMPLETED')
  and terminated = 0
--and amountdollars > 0
group by 1,2,3,4,5,6
	)

select
	mysource."day" as dt,
	locale::varchar as region,
	sum(dollars) as total_gross,
	sum(case when txn_type = 'external' then dollars else 0 end)::DOUBLE PRECISION as external_rev,
	sum(case when txn_type = 'internal' then dollars else 0 end)::DOUBLE PRECISION as internal_rev,
	sum(case when crown_levels >= 11 then dollars else 0 end)::DOUBLE PRECISION as golden_crown_rev,
	sum(case when crown_levels >= 6 and crown_levels <11 then dollars else 0 end)::DOUBLE PRECISION as pla_crown_rev,
	sum(case when crown_levels >= 1 and crown_levels < 6 then dollars else 0 end)::DOUBLE PRECISION as red_crown_rev,
	sum(case when crown_levels = 0 then dollars else 0 end)::DOUBLE PRECISION as no_crown_rev,
	sum(case when txn_type = 'external' then payers_ct else 0 end) as external_payers,
	sum(case when txn_type = 'internal' then payers_ct else 0 end) as interanl_payers,
	sum(case when crown_levels >= 11 then payers_ct else 0 end) as golden_payers,
	sum(case when crown_levels >= 6 and crown_levels <11 then payers_ct else 0 end) as pla_payers,
	sum(case when crown_levels >= 1 and crown_levels <6 then payers_ct else 0 end) as red_payers,
	sum(case when crown_levels = 0 then payers_ct else 0 end) as no_crown_payers
from mysource
group by dt, region
order by dt asc
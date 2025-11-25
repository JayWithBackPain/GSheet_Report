with revenue_info as  ((select coalesce(-totaldiamonds,0)/10000+amountdollars as total_amountdollars,
                               st.userid,
                               st.touserid,
                               st.storename,
                               st.amountdollars,
                               st.datecreated,
                               st.status,
                               st.productid,
                               st.amountbars,
                               'non_diamond_sub' as diamond_sub_flag
                        from public.store_transaction st
	                             left join public.diamond_transactions dt
	                                       on st.exttransactionid = dt.exttransactionid
		                                       and (dt.status = 'COMPLETED' or dt.status = 'AUTHORIZED')
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
		                     and status = 'COMPLETED'
                       )),
     rev_summary as (
	     select *,
	            lag(day) over (partition by userid order by day) as previous_gross_pay_day,
	            lead(day) over (partition by userid order by day) as next_gross_pay_day,
	            lag(case when external_rev > 0 then day end) over (partition by userid order by day) as previous_external_pay_day,
	            lead(case when external_rev > 0 then day end) over (partition by userid order by day) as next_external_pay_day
	     from
		     (select
			      date(revenue_info.datecreated) as day,
			      revenue_info.userid,
                  ud.locale,
			      sum(total_amountdollars) as gross_rev,
			      sum(amountdollars) as external_rev,
			      sum(total_amountdollars) - sum(amountdollars) as internal_rev
		      from revenue_info
			           left join users_data ud on revenue_info.userid = ud.userid
		      WHERE status in ('COMPLETED','AUTHORIZED')
			    and terminated = 0
		      group by 1,2,3
		     ))

select
	day as dt,
    locale::varchar as region,
	count(case when previous_gross_pay_day is not null and day - previous_gross_pay_day > 7 then 1 end) as reactivated_payers,
	count(case when previous_gross_pay_day is not null and day - previous_gross_pay_day <= 7 then 1 end) as continuing_payers,
	count(case when previous_gross_pay_day is null then 1 end) as new_payers,
	count(distinct userid) as payers,
	sum(case when previous_gross_pay_day is not null and day - previous_gross_pay_day > 7 then gross_rev end) as reactivated_payers_gross,
	sum(case when previous_gross_pay_day is not null and day - previous_gross_pay_day <= 7 then gross_rev end) as continuing_payers_gross,
	sum(case when previous_gross_pay_day is null then gross_rev end) as new_payers_gross,
	sum(gross_rev) as payers_gross

from rev_summary
where day >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))
  and day < current_date
group by 1,2
order by 1
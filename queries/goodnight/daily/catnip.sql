select
	date_trunc('day',timestamp_tw) as dt,
	'global' as region,
	count(distinct case when he_yue_lei_xing_ like '%聲音%' then sender_id else null end) as voice_senders,
	count(distinct case when he_yue_lei_xing_ not like '%聲音%' and he_yue_lei_xing_ is not null then sender_id else null end) as video_senders,
	count(distinct case when he_yue_lei_xing_ is null then sender_id else null end) as ametuer_senders,
	sum(case when he_yue_lei_xing_ like '%聲音%' then can else 0 end) as voice_can,
	sum(case when he_yue_lei_xing_ not like '%聲音%' and he_yue_lei_xing_ is not null then can else 0 end) as video_can,
	sum(case when he_yue_lei_xing_ is null then can else 0 end) as ametuer_can,
	sum(case when he_yue_lei_xing_ like '%聲音%' then catnip else 0 end) as voice_catnip,
	sum(case when he_yue_lei_xing_ not like '%聲音%' and he_yue_lei_xing_ is not null then catnip else 0 end) as video_catnip,
	sum(case when he_yue_lei_xing_ like '%聲音%' then catnip/cr.usd_currency else 0 end)*0.187 as voice_share,
	sum(case when he_yue_lei_xing_ not like '%聲音%' and he_yue_lei_xing_ is not null then catnip/cr.usd_currency else 0 end)*0.235 as video_share
from fact.catnip_generate cg
	     left join public.finance_contract fc
	               on cg.receiver_id = fc.uid
	     left join currency_records cr
	               on date_trunc('month',timestamp_tw) = cr.currency_month
where timestamp_tw >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
	and re
group by 1,2
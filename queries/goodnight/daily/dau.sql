with base_data as (
	select
		dt,
		case when country_code in ('TW','KR','JP','TH','US') then country_code else 'Others' end as region,
		count(distinct user_id) as dau,
		count(distinct case when audience_dim.voice.rooms::int > 0 then user_id else null end) as live_voice_dau,
		count(distinct case when audience_dim.video.rooms::int > 0 then user_id else null end) as live_video_dau,
		count(distinct case when matching_dim.voice.attempts::int > 0 then user_id else null end) as voice_match_dau,
		count(distinct case when matching_dim.video.attempts::int > 0 then user_id else null end) as video_match_dau,
		count(distinct case when matching_dim.text.attempts::int > 0 then user_id else null end) as text_match_dau,
		count(distinct case when can_purchasing_dim.revenue::float > 0 or sub_purchasing_dim.revenue::float > 0  then user_id else null end) as payers
	from datamart.daily_user_activities
	where dt >= DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE
	  and dt < current_date
	group by 1,2
)
select dt,'global' as region,sum(dau) as dau,sum(live_voice_dau) as live_voice_dau,sum(live_video_dau) as live_video_dau,sum(voice_match_dau) as voice_match_dau,sum(video_match_dau) as video_match_dau,sum(text_match_dau) as text_match_dau,sum(payers) as payers from base_data group by 1,2
union all
select * from base_data;
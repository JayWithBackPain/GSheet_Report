SELECT
	DATE_TRUNC('day', mr.join_time)::DATE AS dt,
	'global' AS region,

	-- Matchers (不重複配對人數)
	COUNT(DISTINCT CASE WHEN ppu.gender = true  AND mr.match_mode = 'video' THEN mr.user_id END) AS video_male_matchers,
	COUNT(DISTINCT CASE WHEN ppu.gender = false AND mr.match_mode = 'video' THEN mr.user_id END) AS video_female_matchers,
	COUNT(DISTINCT CASE WHEN ppu.gender = true  AND mr.match_mode = 'voice' THEN mr.user_id END) AS voice_male_matchers,
	COUNT(DISTINCT CASE WHEN ppu.gender = false AND mr.match_mode = 'voice' THEN mr.user_id END) AS voice_female_matchers,
	-- Attempts ()嘗試配對次數
	COUNT(CASE WHEN ppu.gender = true  AND mr.match_mode = 'video' THEN 1 else null END) AS video_male_attempts,
	COUNT(CASE WHEN ppu.gender = false AND mr.match_mode = 'video' THEN 1 else null END) AS video_female_attempts,
	COUNT(CASE WHEN ppu.gender = true  AND mr.match_mode = 'voice' THEN 1 else null END) AS voice_male_attempts,
	COUNT(CASE WHEN ppu.gender = false AND mr.match_mode = 'voice' THEN 1 else null END) AS voice_female_attempts,
	-- Wait Time (等待時間)
	SUM(CASE WHEN ppu.gender = true  AND mr.match_mode = 'video' THEN mr.wait_time ELSE 0 END) AS video_male_wait,
	SUM(CASE WHEN ppu.gender = false AND mr.match_mode = 'video' THEN mr.wait_time ELSE 0 END) AS video_female_wait,
	SUM(CASE WHEN ppu.gender = true  AND mr.match_mode = 'voice' THEN mr.wait_time ELSE 0 END) AS voice_male_wait,
	SUM(CASE WHEN ppu.gender = false AND mr.match_mode = 'voice' THEN mr.wait_time ELSE 0 END) AS voice_female_wait,

	-- Mates (不重複對象數)
	COUNT(DISTINCT CASE WHEN ppu.gender = true  AND mr.match_mode = 'video' THEN mr.mate_id END) AS video_male_mates,
	COUNT(DISTINCT CASE WHEN ppu.gender = false AND mr.match_mode = 'video' THEN mr.mate_id END) AS video_female_mates,
	COUNT(DISTINCT CASE WHEN ppu.gender = true  AND mr.match_mode = 'voice' THEN mr.mate_id END) AS voice_male_mates,
	COUNT(DISTINCT CASE WHEN ppu.gender = false AND mr.match_mode = 'voice' THEN mr.mate_id END) AS voice_female_mates,

	-- Duration (通話時長)
	SUM(CASE WHEN ppu.gender = true  AND mr.match_mode = 'video' THEN mr.mate_duration ELSE 0 END) AS video_male_duration,
	SUM(CASE WHEN ppu.gender = false AND mr.match_mode = 'video' THEN mr.mate_duration ELSE 0 END) AS video_female_duration,
	SUM(CASE WHEN ppu.gender = true  AND mr.match_mode = 'voice' THEN mr.mate_duration ELSE 0 END) AS voice_male_duration,
	SUM(CASE WHEN ppu.gender = false AND mr.match_mode = 'voice' THEN mr.mate_duration ELSE 0 END) AS voice_female_duration,

	-- Friends (配對成功且加為好友)
	COUNT(DISTINCT CASE WHEN mr.success AND ppu.gender = true  AND mr.match_mode = 'video' THEN mr.mate_id END) AS video_male_friends,
	COUNT(DISTINCT CASE WHEN mr.success AND ppu.gender = false AND mr.match_mode = 'video' THEN mr.mate_id END) AS video_female_friends,
	COUNT(DISTINCT CASE WHEN mr.success AND ppu.gender = true  AND mr.match_mode = 'voice' THEN mr.mate_id END) AS voice_male_friends,
	COUNT(DISTINCT CASE WHEN mr.success AND ppu.gender = false AND mr.match_mode = 'voice' THEN mr.mate_id END) AS voice_female_friends

FROM fact.match_record mr
	     LEFT JOIN prod_pg_users ppu
	               ON mr.user_id = ppu.id
WHERE mr.join_time >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
GROUP BY 1;
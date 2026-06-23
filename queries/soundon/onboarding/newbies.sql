-- ============================================================================
-- 步驟 0: 報表範圍參數設定與資料時間鎖
-- ============================================================================
WITH params AS (
	SELECT
		date_trunc('month',CURRENT_DATE - INTERVAL '3 months')::DATE AS report_start,
		(CURRENT_DATE - INTERVAL '1 day')::DATE AS report_end,
		-- 精確推算資料撈取起點 (報表 30 天 + 世代 84 天 + 時區容錯 6 天 = 120 天)
		date_trunc('month',CURRENT_DATE - INTERVAL '3 months')::DATE - interval '84 days' AS data_start
),
     date_series AS (
	     SELECT generate_series(
			            (SELECT report_start FROM params),
			            (SELECT report_end FROM params),
			            '1 day'::interval
	            )::date AS dt
     ),

-- ============================================================================
-- 步驟 1: 提煉全部有效集數 (攔截歷史鉅量資料)
-- ============================================================================
     all_valid_episodes AS (
	     SELECT
		     p."ownerId" AS uid,
		     e."podcastId" AS pid,
		     CAST(e."episode" AS bigint) AS ep_num,
		     DATE_TRUNC('day', e."publishDate" + INTERVAL '8 hours')::date AS publish_date
	     FROM episodes e
		          JOIN podcasts p ON e."podcastId" = p.id
	     WHERE e."publishStatus" IS TRUE
		   AND e."publishDate" >= (SELECT data_start FROM params)
     ),

-- ============================================================================
-- 步驟 2: 第一層聚合 (計算單一個體在生命週期內的表現，並同步加上時間鎖)
-- ============================================================================
     user_summary AS (
	     SELECT
		     u.id AS uid,
		     DATE_TRUNC('day', u."createdAt" + INTERVAL '8 hours')::date AS cohort_date,
		     MIN(CASE WHEN e.ep_num = 1 THEN e.publish_date END) AS first_ep1_date,
		     MIN(CASE WHEN e.ep_num = 2 THEN e.publish_date END) AS first_ep2_date,
		     COUNT(CASE WHEN e.publish_date <= DATE_TRUNC('day', u."createdAt" + INTERVAL '8 hours')::date + 28 THEN 1 END) AS total_eps_28d,
		     COUNT(CASE WHEN e.publish_date <= DATE_TRUNC('day', u."createdAt" + INTERVAL '8 hours')::date + 84 THEN 1 END) AS total_eps_84d
	     FROM users u
		          LEFT JOIN all_valid_episodes e ON u.id = e.uid
	     WHERE u."createdAt" >= (SELECT data_start FROM params)
	     GROUP BY 1, 2
     ),
     channel_summary AS (
	     SELECT
		     p.id AS pid,
		     DATE_TRUNC('day', p."createdAt" + INTERVAL '8 hours')::date AS cohort_date,
		     MIN(CASE WHEN e.ep_num = 1 THEN e.publish_date END) AS first_ep1_date,
		     MIN(CASE WHEN e.ep_num = 2 THEN e.publish_date END) AS first_ep2_date,
		     COUNT(CASE WHEN e.publish_date <= DATE_TRUNC('day', p."createdAt" + INTERVAL '8 hours')::date + 28 THEN 1 END) AS total_eps_28d,
		     COUNT(CASE WHEN e.publish_date <= DATE_TRUNC('day', p."createdAt" + INTERVAL '8 hours')::date + 84 THEN 1 END) AS total_eps_84d
	     FROM podcasts p
		          LEFT JOIN all_valid_episodes e ON p.id = e.pid
	     WHERE p."createdAt" >= (SELECT data_start FROM params)
	     GROUP BY 1, 2
     ),

-- ============================================================================
-- 步驟 3: 第二層聚合 (捲總為每日世代資料 Cohort Aggregation)
-- ============================================================================
     user_cohorts AS (
	     SELECT
		     cohort_date,
		     COUNT(uid) AS cohort_size,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 1 THEN 1 END) AS ep1_1d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 7 THEN 1 END) AS ep1_7d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 28 THEN 1 END) AS ep1_28d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 84 THEN 1 END) AS ep1_84d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 28 AND first_ep2_date <= cohort_date + 28 THEN 1 END) AS ep2_28d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 84 AND first_ep2_date <= cohort_date + 84 THEN 1 END) AS ep2_84d,
		     SUM(total_eps_28d) AS sum_eps_28d,
		     SUM(total_eps_84d) AS sum_eps_84d
	     FROM user_summary
	     GROUP BY 1
     ),
     channel_cohorts AS (
	     SELECT
		     cohort_date,
		     COUNT(pid) AS cohort_size,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 1 THEN 1 END) AS ep1_1d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 7 THEN 1 END) AS ep1_7d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 28 THEN 1 END) AS ep1_28d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 84 THEN 1 END) AS ep1_84d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 28 AND first_ep2_date <= cohort_date + 28 THEN 1 END) AS ep2_28d,
		     COUNT(CASE WHEN first_ep1_date <= cohort_date + 84 AND first_ep2_date <= cohort_date + 84 THEN 1 END) AS ep2_84d,
		     SUM(total_eps_28d) AS sum_eps_28d,
		     SUM(total_eps_84d) AS sum_eps_84d
	     FROM channel_summary
	     GROUP BY 1
     )

-- ============================================================================
-- 步驟 4: 最終組裝 (運用 Shifted Join 錯位對齊日期，輸出 1~16 項指標)
-- ============================================================================
SELECT
	ds.dt AS dt,
	'global' as region,
	-- 1~2. 當日基礎營運指標 (NRU 新註冊用戶數 / NPC 新建立頻道數)
	COALESCE(uc0.cohort_size, 0) AS nru,
	COALESCE(cc0.cohort_size, 0) AS npc,

	-- 3~8. EP1 首發轉換率
	ROUND(uc1.ep1_1d::NUMERIC / NULLIF(uc1.cohort_size, 0), 4) AS User_1d_EP1_Rate,
	ROUND(uc7.ep1_7d::NUMERIC / NULLIF(uc7.cohort_size, 0), 4) AS User_7d_EP1_Rate,
	ROUND(uc28.ep1_28d::NUMERIC / NULLIF(uc28.cohort_size, 0), 4) AS User_28d_EP1_Rate,
	ROUND(cc1.ep1_1d::NUMERIC / NULLIF(cc1.cohort_size, 0), 4) AS Channel_1d_EP1_Rate,
	ROUND(cc7.ep1_7d::NUMERIC / NULLIF(cc7.cohort_size, 0), 4) AS Channel_7d_EP1_Rate,
	ROUND(cc28.ep1_28d::NUMERIC / NULLIF(cc28.cohort_size, 0), 4) AS Channel_28d_EP1_Rate,

	-- 9~12. EP2 留存率 (分母為：期限內有發過 EP1 的個體)
	ROUND(uc28.ep2_28d::NUMERIC / NULLIF(uc28.ep1_28d, 0), 4) AS User_28d_EP2_Given_EP1,
	ROUND(uc84.ep2_84d::NUMERIC / NULLIF(uc84.ep1_84d, 0), 4) AS User_84d_EP2_Given_EP1,
	ROUND(cc28.ep2_28d::NUMERIC / NULLIF(cc28.ep1_28d, 0), 4) AS Channel_28d_EP2_Given_EP1,
	ROUND(cc84.ep2_84d::NUMERIC / NULLIF(cc84.ep1_84d, 0), 4) AS Channel_84d_EP2_Given_EP1,

	-- 13~16. 世代生命週期人均產值 (Avg Episodes)
	ROUND(uc28.sum_eps_28d::NUMERIC / NULLIF(uc28.cohort_size, 0), 2) AS User_28d_Avg_EP,
	ROUND(uc84.sum_eps_84d::NUMERIC / NULLIF(uc84.cohort_size, 0), 2) AS User_84d_Avg_EP,
	ROUND(cc28.sum_eps_28d::NUMERIC / NULLIF(cc28.cohort_size, 0), 2) AS Channel_28d_Avg_EP,
	ROUND(cc84.sum_eps_84d::NUMERIC / NULLIF(cc84.cohort_size, 0), 2) AS Channel_84d_Avg_EP

FROM date_series ds
	     LEFT JOIN user_cohorts uc0 ON ds.dt = uc0.cohort_date
	     LEFT JOIN channel_cohorts cc0 ON ds.dt = cc0.cohort_date
	     LEFT JOIN user_cohorts uc1 ON ds.dt = uc1.cohort_date + 1
	     LEFT JOIN channel_cohorts cc1 ON ds.dt = cc1.cohort_date + 1
	     LEFT JOIN user_cohorts uc7 ON ds.dt = uc7.cohort_date + 7
	     LEFT JOIN channel_cohorts cc7 ON ds.dt = cc7.cohort_date + 7
	     LEFT JOIN user_cohorts uc28 ON ds.dt = uc28.cohort_date + 28
	     LEFT JOIN channel_cohorts cc28 ON ds.dt = cc28.cohort_date + 28
	     LEFT JOIN user_cohorts uc84 ON ds.dt = uc84.cohort_date + 84
	     LEFT JOIN channel_cohorts cc84 ON ds.dt = cc84.cohort_date + 84
ORDER BY ds.dt DESC;
-- ============================================================================
-- 步驟 0: 統一參數管理區 (統一設定報表範圍與 Buffer)
-- ============================================================================
WITH params AS (
	SELECT
		date_trunc('month',current_date - interval '3 month') AS report_start,  -- 報表起始日: 最近 3 個月 (90天)
		(CURRENT_DATE - INTERVAL '1 day')::DATE AS report_end,      -- 報表結束日: 昨天
		date_trunc('month',current_date - interval '3 month') - interval '28 day' AS data_start    -- 資料撈取起點: 90天 + 28天(4週 Buffer) + 2天容錯
),

-- ============================================================================
-- 步驟 1: 建立日期序列 (鎖定在最近三個月)
-- ============================================================================
     date_series AS (
	     SELECT generate_series(
			            (SELECT report_start FROM params),
			            (SELECT report_end FROM params),
			            '1 day'::interval
	            )::date AS report_date
     ),

-- ============================================================================
-- 步驟 2: 基礎資料前處理 (減少重複掃描)
-- ============================================================================
-- 2-1: 每日下載數據
     daily_downloads AS (
	     SELECT
		     items.date AS activity_date,
		     SUM(items.count) AS distinct_download,
		     SUM(items."rawCount") AS total_download
	     FROM analytics_podcast_level_timeseries,
	          jsonb_to_recordset(counts) AS items("date" date, "count" bigint, "rawCount" bigint)
	     WHERE items.date >= (SELECT data_start FROM params)
		   AND "podcastId" != '9ff9da9c-68ba-48f9-93a7-3a8142131ad1'
		   AND "podcastId" != '19abbb88-cbb2-4fd2-8551-c6df9b915ad9'
		   AND items."rawCount" < items.count * 1000000
	     GROUP BY 1
     ),

-- 2-2: 統一撈取 Episodes 的 Base Table (轉換時區並過濾有效集數)
     base_episodes AS (
	     SELECT
		     e.id,
		     e."podcastId" AS pid,
		     p."title" AS p_title,
		     DATE_TRUNC('day', e."publishDate" + '8 hours'::interval)::DATE AS upload_date,
		     e."daiStatus",
		     e.episode
	     FROM episodes e
		          LEFT JOIN podcasts p ON e."podcastId" = p.id
	     WHERE e."publishStatus" IS TRUE
		   AND e."publishDate" >= (SELECT data_start FROM params)
     ),

-- ============================================================================
-- 步驟 3: 每日核心維度計算
-- ============================================================================
-- 3-1: 計算每日第一集的數量
     newep AS (
	     SELECT
		     upload_date AS report_date,
		     COUNT(DISTINCT id) AS new_ep1
	     FROM base_episodes
	     WHERE cast("episode" AS bigint) = 1
	     GROUP BY 1
     ),

-- 3-2: 計算每日活躍上傳創作者
     daily_active_source AS (
	     SELECT
		     upload_date AS report_date,
		     pid,
		     p_title,
		     COUNT(DISTINCT id) AS eps,
		     COUNT(DISTINCT CASE WHEN "daiStatus" = 'active' THEN id END) AS eps_with_campaign
	     FROM base_episodes
	     GROUP BY 1, 2, 3
     ),

-- 3-3: 🎯 新增需求：計算「過去 4 週每週都有新單集」的創作者
-- 邏輯：當日有上傳為第 1 週 (包含當日往前推 7 天內)。再去檢查過去第 2, 3, 4 週區間是否有紀錄。
     consistent_creators AS (
	     SELECT
		     a.report_date AS dt,
		     COUNT(DISTINCT a.pid) AS consistent_podcasters
	     FROM daily_active_source a
	     WHERE
	       -- 檢查第 2 週 (T-13 到 T-7)
		     EXISTS (SELECT 1 FROM daily_active_source b WHERE b.pid = a.pid AND b.report_date BETWEEN a.report_date - 13 AND a.report_date - 7)
	       -- 檢查第 3 週 (T-20 到 T-14)
		   AND EXISTS (SELECT 1 FROM daily_active_source c WHERE c.pid = a.pid AND c.report_date BETWEEN a.report_date - 20 AND a.report_date - 14)
	       -- 檢查第 4 週 (T-27 到 T-21)
		   AND EXISTS (SELECT 1 FROM daily_active_source d WHERE d.pid = a.pid AND d.report_date BETWEEN a.report_date - 27 AND a.report_date - 21)
	     GROUP BY 1
     ),

-- 3-4: 計算每日的「活躍 Podcast 數」
     active_podcasts AS (
	     SELECT
		     report_date,
		     COUNT(DISTINCT CASE WHEN eps < 15 AND p_title !~ '^[\x00-\x7F]*$' THEN pid END) AS dap,
		     COUNT(DISTINCT CASE WHEN eps >= 15 AND p_title ~ '^[\x00-\x7F]*$' THEN pid END) AS dap_ad,
		     COUNT(DISTINCT CASE WHEN eps < 15 AND p_title !~ '^[\x00-\x7F]*$' AND eps_with_campaign > 0 THEN pid END) AS dapwc,
		     COUNT(DISTINCT CASE WHEN eps >= 15 AND p_title ~ '^[\x00-\x7F]*$' AND eps_with_campaign > 0 THEN pid END) AS dapwc_ad,
		     SUM(CASE WHEN eps >= 15 AND p_title ~ '^[\x00-\x7F]*$' THEN eps ELSE 0 END) AS deps_ad,
		     SUM(CASE WHEN eps >= 15 AND p_title ~ '^[\x00-\x7F]*$' THEN eps_with_campaign ELSE 0 END) AS depswc_ad,
		     SUM(CASE WHEN eps < 15 AND p_title !~ '^[\x00-\x7F]*$' THEN eps ELSE 0 END) AS deps,
		     SUM(CASE WHEN eps < 15 AND p_title !~ '^[\x00-\x7F]*$' THEN eps_with_campaign ELSE 0 END) AS depswc
	     FROM daily_active_source
	     GROUP BY 1
     ),

-- 3-5: 其他每日營運數據
     daily_impressions AS (
	     SELECT
		     DATE_TRUNC('day', "createdAt" + '8 hours'::interval)::DATE AS dt,
		     SUM(count) AS actual_impressions
	     FROM analytics_campaign_timeseries
	     WHERE "createdAt" >= (SELECT data_start FROM params)
	     GROUP BY 1
     ),

     users_created AS (
	     SELECT
		     DATE_TRUNC('day', "createdAt" + '8 hour'::interval)::DATE AS dt,
		     COUNT(DISTINCT id) AS nru
	     FROM users
	     WHERE "createdAt" >= (SELECT data_start FROM params)
	     GROUP BY 1
     )

-- ============================================================================
-- 步驟 4: 最終報表組合 (以 date_series 驅動，確保產出近 3 個月數據)
-- ============================================================================
SELECT
	ds.report_date AS dt,
	'global' AS region,
	COALESCE(rap.dap, 0) AS dap,
	COALESCE(rap.dapwc, 0) AS dapwc,
	COALESCE(rap.dap_ad, 0) AS dap_ad,
	COALESCE(rap.dapwc_ad, 0) AS dapwc_ad,
	COALESCE(dd.distinct_download, 0) AS ddd,
	COALESCE(dd.total_download, 0) AS dtd,
	COALESCE(rap.deps, 0) AS deps,
	COALESCE(rap.depswc, 0) AS depswc,
	COALESCE(users_created.nru, 0) AS nru,
	COALESCE(newep.new_ep1, 0) AS new_ep1,
	COALESCE(rap.deps_ad, 0) AS deps_ad,
	COALESCE(rap.depswc_ad, 0) AS depswc_ad,
	COALESCE(cc.consistent_podcasters, 0) AS consistent_creators_4w
FROM date_series ds
	     LEFT JOIN daily_downloads dd ON ds.report_date = dd.activity_date
	     LEFT JOIN active_podcasts rap ON ds.report_date = rap.report_date
	     LEFT JOIN daily_impressions di ON ds.report_date = di.dt
	     LEFT JOIN users_created ON ds.report_date = users_created.dt
	     LEFT JOIN newep ON ds.report_date = newep.report_date
	     LEFT JOIN consistent_creators cc ON ds.report_date = cc.dt  -- 關聯新增的 CTE
ORDER BY ds.report_date DESC;
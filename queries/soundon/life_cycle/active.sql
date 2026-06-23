-- ============================================================================
-- 步驟 0: 參數集中管理
-- ============================================================================
WITH params AS (
	SELECT
		date_trunc('month',current_date - '3 month'::interval) AS report_start,  -- 報表起始日 (近3個月)
		(CURRENT_DATE - INTERVAL '1 day')::DATE AS report_end,      -- 報表結束日 (昨天)
		-- 💡 重要：因為要回溯上一次發布與計算流失，資料起點必須往前多留充足的 Buffer (至少 90+60 天)
		date_trunc('month',current_date - '3 month'::interval) - '2 month'::interval AS data_start
),

-- 步驟 1: 建立近三個月的每日時間序列
     date_series AS (
	     SELECT generate_series(
			            (SELECT report_start FROM params),
			            (SELECT report_end FROM params),
			            '1 day'::interval
	            )::date AS report_date
     ),

-- ============================================================================
-- 步驟 2: 創作者發布事件鏈前處理
-- ============================================================================
     raw_episodes AS (
	     SELECT
		     "podcastId" AS pid,
		     DATE_TRUNC('day', "publishDate" + '8 hours'::interval)::DATE AS upload_date,
		     CASE WHEN CAST(episode AS BIGINT) = 1 THEN TRUE ELSE FALSE END AS is_first_ep
	     FROM episodes
	     WHERE "publishStatus" IS TRUE
		   AND "publishDate" >= (SELECT data_start FROM params)
		   AND "podcastId" NOT IN ('9ff9da9c-68ba-48f9-93a7-3a8142131ad1', '19abbb88-cbb2-4fd2-8551-c6df9b915ad9')
     ),

-- 2-1: 處理同天發布多集的極端狀況，確保一天一個 pid 只有一筆紀錄
     distinct_uploads AS (
	     SELECT
		     pid,
		     upload_date,
		     BOOL_OR(is_first_ep) AS has_first_ep -- 當天只要有一集是第一集，即視為首發
	     FROM raw_episodes
	     GROUP BY 1, 2
     ),

-- 2-2: 利用 Window Function 建立鏈結（找出上一次與下一次發布時間）
     ordered_history AS (
	     SELECT
		     pid,
		     upload_date AS p_date,
		     LAG(upload_date) OVER (PARTITION BY pid ORDER BY upload_date) AS prev_date,
		     -- 如果後面沒有新單集了，就把邊界設定為報表結束日的隔天，代表此集的狀態一直延續到現在
		     COALESCE(
						     LEAD(upload_date) OVER (PARTITION BY pid ORDER BY upload_date),
						     (SELECT report_end FROM params) + INTERVAL '1 day'
		     )::DATE AS next_date,
		     has_first_ep
	     FROM distinct_uploads
     )

-- ============================================================================
-- 步驟 3: 每日時間序列與事件鏈進行區間 Join 並聚合指標
-- ============================================================================
SELECT
	ds.report_date AS dt,
	'global' AS region,

	-- 1. 留存用戶：距離上一次發布在 14 天內 (含當天，即差距 0~13 天)
	COUNT(DISTINCT CASE
		               WHEN ds.report_date - oh.p_date <= 13 THEN oh.pid
		END) AS rolling_retained_creators,

	-- 2. 首發用戶：當天發布，且該集為第一集
	COUNT(DISTINCT CASE
		               WHEN ds.report_date = oh.p_date AND oh.has_first_ep IS TRUE THEN oh.pid
		END) AS daily_new_creators,

	-- 3. 喚回用戶：當天有發布，且距離上一次發布超過 14 天 (即差距 >= 15 天)
	COUNT(DISTINCT CASE
		               WHEN ds.report_date = oh.p_date
			               AND oh.has_first_ep IS FALSE
			               AND (oh.p_date - oh.prev_date) >= 15 THEN oh.pid
		END) AS daily_reactivated_creators,

	-- 4. 沈睡用戶：距離上一次發布剛好在 15-28 天內 (即差距 14~27 天)
	-- 💡 註：若您的「剛好在 15 前」是指「第 15 天當天」，可將 BETWEEN 14 AND 27 改為 = 14
	COUNT(DISTINCT CASE
		               WHEN ds.report_date - oh.p_date = 14 THEN oh.pid
		END) AS rolling_sleeping_creators,

	-- 5. 流失用戶：距離上一次發布在當天剛好滿 29 天 (即差距剛好為 28 天)
	COUNT(DISTINCT CASE
		               WHEN ds.report_date - oh.p_date = 28 THEN oh.pid
		END) AS daily_churned_creators

FROM date_series ds
-- 核心效能魔法：用每天的日期去夾「當前這則單集作為最新單集的有效時間軸」
	     LEFT JOIN ordered_history oh
	               ON ds.report_date >= oh.p_date
		               AND ds.report_date < oh.next_date
GROUP BY 1
ORDER BY 1 DESC;
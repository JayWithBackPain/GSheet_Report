WITH filtered_purchase AS (
	SELECT
		user_id,
		usd_price,
		can_gain,
		DATE_TRUNC('day', purchased_at)::DATE AS dt
	FROM fact.can_purchase
	WHERE purchased_at >= DATEADD(day, -90, DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE)
),
     user_daily_history AS (
	     SELECT
		     user_id,
		     dt
	     FROM filtered_purchase
	     GROUP BY 1, 2
     ),
     user_lifecycle AS (
	     SELECT
		     user_id,
		     dt,
		     LAG(dt) OVER (PARTITION BY user_id ORDER BY dt) AS prev_dt
	     FROM user_daily_history
     ),
     lifecycle_flags AS (
	     SELECT
		     user_id,
		     dt,
		     CASE
			     WHEN prev_dt IS NULL THEN 'new'
			     WHEN DATEDIFF(day, prev_dt, dt) <= 7 THEN 'continuing'
			     WHEN DATEDIFF(day, prev_dt, dt) BETWEEN 8 AND 30 THEN 'lapsing'
			     WHEN DATEDIFF(day, prev_dt, dt) BETWEEN 31 AND 90 THEN 'resurrected'
			     ELSE 'new' -- 超過 90 天（或因追溯限制未阻截到歷史），依邏輯定義回歸 new
			     END AS payer_type
	     FROM user_lifecycle
	     WHERE dt >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
     ),
     base_tx AS (
	     SELECT
		     t.dt,
		     t.user_id,
		     case when ppu.country_code in ('TW','KR','JP','TH','US') then ppu.country_code else 'Others' end as region,
		     t.usd_price,
		     CASE
			     WHEN t.can_gain <= 100 THEN '1-100'
			     WHEN t.can_gain > 100 AND t.can_gain <= 1500 THEN '101-1500'
			     WHEN t.can_gain > 1500 AND t.can_gain <= 2000 THEN '1501-2000'
			     WHEN t.can_gain > 2000 AND t.can_gain <= 15000 THEN '2001-15000'
			     ELSE 'Over 15001'
			     END AS price_group,
		     l.payer_type
	     FROM filtered_purchase t
		          JOIN lifecycle_flags l ON t.user_id = l.user_id AND t.dt = l.dt
	              left join prod_pg_users ppu on t.user_id = ppu.id
	     WHERE t.dt >= DATE_TRUNC('month', DATEADD(month, -3, CURRENT_DATE))::DATE
     ),
	global_agg as (
		SELECT
			dt,
			-- 總體指標
			'global' as region,
			COUNT(DISTINCT user_id) AS total_payers,
			SUM(usd_price) AS total_revenue,

			-- 各價格帶營收 (Revenue by Price Group)
			SUM(CASE WHEN price_group = '1-100' THEN usd_price ELSE 0 END) AS "1-100_revenue",
			SUM(CASE WHEN price_group = '101-1500' THEN usd_price ELSE 0 END) AS "101-1500_revenue",
			SUM(CASE WHEN price_group = '1501-2000' THEN usd_price ELSE 0 END) AS "1501-2000_revenue",
			SUM(CASE WHEN price_group = '2001-15000' THEN usd_price ELSE 0 END) AS "2001-15000_revenue",
			SUM(CASE WHEN price_group = 'Over 15001' THEN usd_price ELSE 0 END) AS "over_15001_revenue",

			-- 各價格帶人數 (Payers by Price Group)
			COUNT(DISTINCT CASE WHEN price_group = '1-100' THEN user_id END) AS "1-100_payers",
			COUNT(DISTINCT CASE WHEN price_group = '101-1500' THEN user_id END) AS "101-1500_payers",
			COUNT(DISTINCT CASE WHEN price_group = '1501-2000' THEN user_id END) AS "1501-2000_payers",
			COUNT(DISTINCT CASE WHEN price_group = '2001-15000' THEN user_id END) AS "2001-15000_payers",
			COUNT(DISTINCT CASE WHEN price_group = 'Over 15001' THEN user_id END) AS "over_15001_payers",

			-- 用戶生命週期人數 (Payers by Lifecycle)
			COUNT(DISTINCT CASE WHEN payer_type = 'continuing' THEN user_id END) AS continuing_payers,
			COUNT(DISTINCT CASE WHEN payer_type = 'lapsing' THEN user_id END) AS lapsing_payers,
			COUNT(DISTINCT CASE WHEN payer_type = 'resurrected' THEN user_id END) AS resurrected_payers,
			COUNT(DISTINCT CASE WHEN payer_type = 'new' THEN user_id END) AS new_payers,

			-- 用戶生命週期營收 (Revenue by Lifecycle)
			sum(case when payer_type = 'continuing' then usd_price else 0 end) as continuing_revenue,
			sum(case when payer_type = 'lapsing' then usd_price else 0 end) as continuing_revenue,
			sum(case when payer_type = 'resurrected' then usd_price else 0 end) as continuing_revenue,
			sum(case when payer_type = 'new' then usd_price else 0 end) as continuing_revenue
		FROM base_tx
		GROUP BY 1,2
	),
	 regional_agg as (
		 SELECT
			 dt,
			 -- 總體指標
			 region,
			 COUNT(DISTINCT user_id) AS total_payers,
			 SUM(usd_price) AS total_revenue,

			 -- 各價格帶營收 (Revenue by Price Group)
			 SUM(CASE WHEN price_group = '1-100' THEN usd_price ELSE 0 END) AS "1-100_revenue",
			 SUM(CASE WHEN price_group = '101-1500' THEN usd_price ELSE 0 END) AS "101-1500_revenue",
			 SUM(CASE WHEN price_group = '1501-2000' THEN usd_price ELSE 0 END) AS "1501-2000_revenue",
			 SUM(CASE WHEN price_group = '2001-15000' THEN usd_price ELSE 0 END) AS "2001-15000_revenue",
			 SUM(CASE WHEN price_group = 'Over 15001' THEN usd_price ELSE 0 END) AS "over_15001_revenue",

			 -- 各價格帶人數 (Payers by Price Group)
			 COUNT(DISTINCT CASE WHEN price_group = '1-100' THEN user_id END) AS "1-100_payers",
			 COUNT(DISTINCT CASE WHEN price_group = '101-1500' THEN user_id END) AS "101-1500_payers",
			 COUNT(DISTINCT CASE WHEN price_group = '1501-2000' THEN user_id END) AS "1501-2000_payers",
			 COUNT(DISTINCT CASE WHEN price_group = '2001-15000' THEN user_id END) AS "2001-15000_payers",
			 COUNT(DISTINCT CASE WHEN price_group = 'Over 15001' THEN user_id END) AS "over_15001_payers",

			 -- 用戶生命週期人數 (Payers by Lifecycle)
			 COUNT(DISTINCT CASE WHEN payer_type = 'continuing' THEN user_id END) AS continuing_payers,
			 COUNT(DISTINCT CASE WHEN payer_type = 'lapsing' THEN user_id END) AS lapsing_payers,
			 COUNT(DISTINCT CASE WHEN payer_type = 'resurrected' THEN user_id END) AS resurrected_payers,
			 COUNT(DISTINCT CASE WHEN payer_type = 'new' THEN user_id END) AS new_payers,

			 -- 用戶生命週期營收 (Revenue by Lifecycle)
			 sum(case when payer_type = 'continuing' then usd_price else 0 end) as continuing_revenue,
			 sum(case when payer_type = 'lapsing' then usd_price else 0 end) as continuing_revenue,
			 sum(case when payer_type = 'resurrected' then usd_price else 0 end) as continuing_revenue,
			 sum(case when payer_type = 'new' then usd_price else 0 end) as continuing_revenue
		 FROM base_tx
		 GROUP BY 1,2
	 )
select * from global_agg
union all
select * from regional_agg
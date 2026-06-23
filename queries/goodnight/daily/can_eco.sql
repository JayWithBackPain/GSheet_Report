WITH cp AS (
	SELECT
		DATE_TRUNC('day', purchased_at)::DATE AS dt,
		SUM(usd_price) AS revenue
	FROM fact.can_purchase
	WHERE purchased_at >= DATEADD(month, -4, DATE_TRUNC('month', CURRENT_DATE))::DATE
	GROUP BY 1
),
     can_gain AS (
	     SELECT
		     DATE_TRUNC('day', timestamp_tw)::DATE AS dt,
		     SUM(cans) AS total_can
	     FROM fact.can_usage
	     WHERE timestamp_tw >= DATEADD(month, -4, DATE_TRUNC('month', CURRENT_DATE))::DATE
		   AND can_property NOT IN ('game', 'red_envelop')
		   AND flow_type = 'gain'
	     GROUP BY 1
     ),
     daily_combined AS (
	     SELECT
		     COALESCE(c.dt, g.dt) AS dt,
		     COALESCE(c.revenue, 0) AS daily_revenue,
		     COALESCE(g.total_can, 0) AS daily_total_can
	     FROM cp c
		          FULL OUTER JOIN can_gain g
		                          ON c.dt = g.dt
     ),
     rolling_summary AS (
	     SELECT
		     dt,
		     daily_total_can,
		     SUM(daily_revenue) OVER (
			     ORDER BY dt
			     ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
			     ) AS rolling_30d_revenue,

		     SUM(daily_total_can) OVER (
			     ORDER BY dt
			     ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
			     ) AS rolling_30d_cans

	     FROM daily_combined
     )
SELECT
	dt,
	'global' as region,
	daily_total_can,
	CASE
		WHEN rolling_30d_cans = 0 THEN 0
		ELSE rolling_30d_revenue / NULLIF(rolling_30d_cans, 0)
		END AS rolling_ratio,
	case
		when rolling_30d_cans = 0 then 0
		else rolling_30d_cans / nullif(rolling_30d_revenue,0)
		end as can_per_daollar
FROM rolling_summary
where dt >= DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE
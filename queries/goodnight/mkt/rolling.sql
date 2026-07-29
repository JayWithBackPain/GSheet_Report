WITH RECURSIVE report_config AS (
    SELECT DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE AS start_dt
),

               calendar(dt) AS (
                   SELECT start_dt FROM report_config
                   UNION ALL
                   SELECT (dt + INTERVAL '1 day')::DATE
                   FROM calendar
                   WHERE dt < CURRENT_DATE
               ),

               raw_dau AS (
                   SELECT
                       dt,
                       user_id
                   FROM datamart.daily_user_activities
                   WHERE dt >= (SELECT start_dt - 29 FROM report_config)
               )

SELECT
    c.dt,
    'global' as region,
    COUNT(DISTINCT CASE WHEN r.dt >= c.dt - 6 THEN r.user_id END) AS rolling_7d_wau,
    COUNT(DISTINCT r.user_id) AS rolling_30d_mau
FROM calendar c
         LEFT JOIN raw_dau r
                   ON r.dt BETWEEN c.dt - 29 AND c.dt
GROUP BY 1;
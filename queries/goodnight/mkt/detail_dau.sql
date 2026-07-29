WITH RECURSIVE calendar(dt) AS (
    SELECT DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE AS dt
    UNION ALL
    SELECT (dt + INTERVAL '1 day')::DATE
    FROM calendar
    WHERE dt < CURRENT_DATE
),

user_activity_lags AS (
                   SELECT
                       user_id,
                       dt AS active_date,
                       day_index,
                       LAG(dt) OVER (PARTITION BY user_id ORDER BY dt) AS prev_active_date,
                       LEAD(dt) OVER (PARTITION BY user_id ORDER BY dt) AS next_active_date
                   FROM datamart.daily_user_activities
                   WHERE dt >= DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE - '31 days'::interval
    ),

user_states AS (
    SELECT
        active_date AS report_date,
        user_id,
        CASE WHEN day_index = 0 THEN 1 ELSE 0 END AS is_new,
        CASE WHEN active_date - prev_active_date <= 7 THEN 1 ELSE 0 END AS is_retained,
        CASE WHEN active_date - prev_active_date <= 30 and active_date - prev_active_date > 7 THEN 1 ELSE 0 END AS is_awoken,
        CASE WHEN (active_date - prev_active_date > 30)
        OR (prev_active_date IS NULL AND day_index > 0) THEN 1 ELSE 0 END AS is_resurrected,
        0 AS is_sleeping,
        0 AS is_churned
    FROM user_activity_lags

    UNION ALL

    SELECT
        (active_date + 8) AS report_date,
        user_id,
        0 AS is_new,
        0 AS is_retained,
        0 as is_awoken,
        0 AS is_resurrected,
        1 AS is_sleeping,
        0 AS is_churned
    FROM user_activity_lags
    WHERE next_active_date IS NULL OR next_active_date > active_date + 7

    UNION ALL

    SELECT
        (active_date + 31) AS report_date,
        user_id,
        0 AS is_new,
        0 AS is_retained,
        0 as is_awoken,
        0 AS is_resurrected,
        0 AS is_sleeping,
        1 AS is_churned
    FROM user_activity_lags
    WHERE next_active_date IS NULL OR next_active_date > active_date + 30
    )

SELECT
    c.dt,
    'global' as region,
    COALESCE(SUM(s.is_new), 0) AS new_users,
    COALESCE(SUM(s.is_retained), 0) AS retained_users,
    coalesce(sum(s.is_awoken), 0) AS awoken_users,
    COALESCE(SUM(s.is_sleeping), 0) AS sleeping_users,
    COALESCE(SUM(s.is_churned), 0) AS churned_users,
    COALESCE(SUM(s.is_resurrected), 0) AS resurrected_users
FROM calendar c
         LEFT JOIN user_states s ON c.dt = s.report_date
GROUP BY 1,2;
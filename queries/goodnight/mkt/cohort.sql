WITH RECURSIVE
    report_config AS (
        SELECT DATEADD(month, -7, DATE_TRUNC('month', CURRENT_DATE))::DATE AS base_start_dt
    ),
    calendar(dt) AS (
        SELECT DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE as dt
        UNION ALL
        SELECT (dt + INTERVAL '1 day')::DATE
        FROM calendar
        WHERE dt < CURRENT_DATE - 1
    ),
    cohort_base AS (
        SELECT
            dt AS cohort_date,
            user_id
        FROM datamart.daily_user_activities
        WHERE dt >= (SELECT base_start_dt FROM report_config)
          AND day_index = 0
    ),
    user_milestones AS (
        SELECT
            cb.cohort_date,
            cb.user_id,

            -- [組別 1: Lifetime-to-Date (LTD) 截至最新進度]
            -- 留存：看最新一天 (CURRENT_DATE) 該用戶是否有上線。
            MAX(CASE WHEN dua.dt = CURRENT_DATE-1 THEN 1 ELSE 0 END) AS is_active_ltd,
            SUM(COALESCE(dua.can_purchasing_dim.revenue::float, 0)) AS ltd_can_rev,
            SUM(COALESCE(dua.sub_purchasing_dim.revenue::float, 0)) AS ltd_sub_rev,
            MAX(CASE WHEN dua.can_purchasing_dim.revenue > 0 OR dua.sub_purchasing_dim.revenue::float > 0 THEN 1 ELSE 0 END) AS is_paid_ltd,

            -- D30
            MAX(CASE WHEN dua.dt = cb.cohort_date + 30 THEN 1 ELSE 0 END) AS is_active_d30,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 30 THEN COALESCE(dua.can_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d30_can_rev,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 30 THEN COALESCE(dua.sub_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d30_sub_rev,
            MAX(CASE WHEN dua.dt <= cb.cohort_date + 30 AND (dua.can_purchasing_dim.revenue::float > 0 OR dua.sub_purchasing_dim.revenue::float > 0) THEN 1 ELSE 0 END) AS is_paid_d30,

            -- D90
            MAX(CASE WHEN dua.dt = cb.cohort_date + 90 THEN 1 ELSE 0 END) AS is_active_d90,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 90 THEN COALESCE(dua.can_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d90_can_rev,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 90 THEN COALESCE(dua.sub_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d90_sub_rev,
            MAX(CASE WHEN dua.dt <= cb.cohort_date + 90 AND (dua.can_purchasing_dim.revenue::float > 0 OR dua.sub_purchasing_dim.revenue::float > 0) THEN 1 ELSE 0 END) AS is_paid_d90,

            -- D180
            MAX(CASE WHEN dua.dt = cb.cohort_date + 180 THEN 1 ELSE 0 END) AS is_active_d180,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 180 THEN COALESCE(dua.can_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d180_can_rev,
            SUM(CASE WHEN dua.dt <= cb.cohort_date + 180 THEN COALESCE(dua.sub_purchasing_dim.revenue::float, 0) ELSE 0 END) AS d180_sub_rev,
            MAX(CASE WHEN dua.dt <= cb.cohort_date + 180 AND (dua.can_purchasing_dim.revenue::float > 0 OR dua.sub_purchasing_dim.revenue::float > 0) THEN 1 ELSE 0 END) AS is_paid_d180

        FROM cohort_base cb
                 LEFT JOIN datamart.daily_user_activities dua
                           ON cb.user_id = dua.user_id
                               AND dua.dt >= cb.cohort_date
        GROUP BY 1, 2
    ),
    cohort_aggregated AS (
        SELECT
            cohort_date,
            COUNT(user_id) AS cohort_users,

            SUM(is_active_ltd) AS ltd_active_users,
            SUM(ltd_can_rev) AS ltd_total_can,
            SUM(ltd_sub_rev) AS ltd_total_sub,
            SUM(is_paid_ltd) AS ltd_pay_users,

            SUM(is_active_d30) AS d30_active_users,
            SUM(d30_can_rev) AS d30_total_can,
            SUM(d30_sub_rev) AS d30_total_sub,
            SUM(is_paid_d30) AS d30_pay_users,

            SUM(is_active_d90) AS d90_active_users,
            SUM(d90_can_rev) AS d90_total_can,
            SUM(d90_sub_rev) AS d90_total_sub,
            SUM(is_paid_d90) AS d90_pay_users,

            SUM(is_active_d180) AS d180_active_users,
            SUM(d180_can_rev) AS d180_total_can,
            SUM(d180_sub_rev) AS d180_total_sub,
            SUM(is_paid_d180) AS d180_pay_users
        FROM user_milestones
        GROUP BY 1
    )
SELECT
    cal.dt AS dt,
    'global' as region,
    -- 【組別 1: report_date = cohort_date】(截至最新的 LTD 累計表現，每天刷新)
    c_ltd.cohort_users AS ltd_cohort_size,
    c_ltd.ltd_active_users::FLOAT / NULLIF(c_ltd.cohort_users, 0) AS ltd_retention_rate,
    c_ltd.ltd_total_can,
    c_ltd.ltd_total_sub,
    c_ltd.ltd_pay_users::FLOAT / NULLIF(c_ltd.cohort_users, 0) AS ltd_pay_rate,
    (c_ltd.ltd_total_can + c_ltd.ltd_total_sub)::FLOAT / NULLIF(c_ltd.cohort_users, 0) AS ltd_arpu,

    -- 【組別 2: 在 report_date 滿 30 天結算的 cohort】(鎖死不變)
    c30.cohort_users AS d30_cohort_size,
    c30.d30_active_users::FLOAT / NULLIF(c30.cohort_users, 0) AS d30_retention_rate,
    c30.d30_total_can,
    c30.d30_total_sub,
    c30.d30_pay_users::FLOAT / NULLIF(c30.cohort_users, 0) AS d30_pay_rate,
    (c30.d30_total_can + c30.d30_total_sub)::FLOAT / NULLIF(c30.cohort_users, 0) AS d30_arpu,

    -- 【組別 3: 在 report_date 滿 90 天結算的 cohort】(鎖死不變)
    c90.cohort_users AS d90_cohort_size,
    c90.d90_active_users::FLOAT / NULLIF(c90.cohort_users, 0) AS d90_retention_rate,
    c90.d90_total_can,
    c90.d90_total_sub,
    c90.d90_pay_users::FLOAT / NULLIF(c90.cohort_users, 0) AS d90_pay_rate,
    (c90.d90_total_can + c90.d90_total_sub)::FLOAT / NULLIF(c90.cohort_users, 0) AS d90_arpu,

    -- 【組別 4: 在 report_date 滿 180 天結算的 cohort】(鎖死不變)
    c180.cohort_users AS d180_cohort_size,
    c180.d180_active_users::FLOAT / NULLIF(c180.cohort_users, 0) AS d180_retention_rate,
    c180.d180_total_can,
    c180.d180_total_sub,
    c180.d180_pay_users::FLOAT / NULLIF(c180.cohort_users, 0) AS d180_pay_rate,
    (c180.d180_total_can + c180.d180_total_sub)::FLOAT / NULLIF(c180.cohort_users, 0) AS d180_arpu

FROM calendar cal
-- 報表骨幹關聯：用同一張已經聚合好的表進行 4 次時間平移 Join
         LEFT JOIN cohort_aggregated c_ltd
                   ON c_ltd.cohort_date = cal.dt
         LEFT JOIN cohort_aggregated c30
                   ON c30.cohort_date = cal.dt - 30
         LEFT JOIN cohort_aggregated c90
                   ON c90.cohort_date = cal.dt - 90
         LEFT JOIN cohort_aggregated c180
                   ON c180.cohort_date = cal.dt - 180
ORDER BY 1 DESC;
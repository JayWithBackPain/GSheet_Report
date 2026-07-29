WITH RECURSIVE calendar(dt) AS (
    SELECT DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE AS dt
    UNION ALL
    SELECT (dt + INTERVAL '1 day')::DATE
    FROM calendar
    WHERE dt < (CURRENT_DATE - INTERVAL '1 day')::DATE
    ),
    retention_agg AS (
SELECT
    (cohort_date + (retention_days * INTERVAL '1 day'))::DATE AS dt,
    CASE
    WHEN account_age_group = 'new' THEN 'new'
    WHEN account_age_group = 'old account' THEN 'old'
    WHEN account_age_group IN ('1 week','1 month','3 days') THEN '1w-1m'
    ELSE '1m-1y'
    END AS age_group,

    SUM(CASE WHEN retention_days = 1 THEN retained_users ELSE 0 END) AS d1_retained,
    SUM(CASE WHEN retention_days = 1 THEN cohort_users ELSE 0 END)   AS d1_cohort,

    SUM(CASE WHEN retention_days = 3 THEN retained_users ELSE 0 END) AS d3_retained,
    SUM(CASE WHEN retention_days = 3 THEN cohort_users ELSE 0 END)   AS d3_cohort,

    SUM(CASE WHEN retention_days = 7 THEN retained_users ELSE 0 END) AS d7_retained,
    SUM(CASE WHEN retention_days = 7 THEN cohort_users ELSE 0 END)   AS d7_cohort,

    SUM(CASE WHEN retention_days = 30 THEN retained_users ELSE 0 END) AS d30_retained,
    SUM(CASE WHEN retention_days = 30 THEN cohort_users ELSE 0 END)   AS d30_cohort
FROM datamart.retention_source
WHERE cohort_date >= DATEADD(month, -3, DATE_TRUNC('month', CURRENT_DATE))::DATE
  AND cohort_date < CURRENT_DATE - 1
  AND retention_days IN (1, 3, 7, 30)
GROUP BY 1, 2
    ),
    pivoted_retention AS (
SELECT
    dt,
    -- D1
    SUM(CASE WHEN age_group = 'new' THEN d1_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'new' THEN d1_cohort ELSE 0 END), 0) AS d1_new_users,
    SUM(CASE WHEN age_group = '1w-1m' THEN d1_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1w-1m' THEN d1_cohort ELSE 0 END), 0) AS d1_1m_users,
    SUM(CASE WHEN age_group = '1m-1y' THEN d1_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1m-1y' THEN d1_cohort ELSE 0 END), 0) AS d1_1y_users,
    SUM(CASE WHEN age_group = 'old' THEN d1_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'old' THEN d1_cohort ELSE 0 END), 0) AS d1_old_users,

    -- D3
    SUM(CASE WHEN age_group = 'new' THEN d3_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'new' THEN d3_cohort ELSE 0 END), 0) AS d3_new_users,
    SUM(CASE WHEN age_group = '1w-1m' THEN d3_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1w-1m' THEN d3_cohort ELSE 0 END), 0) AS d3_1m_users,
    SUM(CASE WHEN age_group = '1m-1y' THEN d3_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1m-1y' THEN d3_cohort ELSE 0 END), 0) AS d3_1y_users,
    SUM(CASE WHEN age_group = 'old' THEN d3_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'old' THEN d3_cohort ELSE 0 END), 0) AS d3_old_users,

    -- D7
    SUM(CASE WHEN age_group = 'new' THEN d7_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'new' THEN d7_cohort ELSE 0 END), 0) AS d7_new_users,
    SUM(CASE WHEN age_group = '1w-1m' THEN d7_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1w-1m' THEN d7_cohort ELSE 0 END), 0) AS d7_1m_users,
    SUM(CASE WHEN age_group = '1m-1y' THEN d7_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1m-1y' THEN d7_cohort ELSE 0 END), 0) AS d7_1y_users,
    SUM(CASE WHEN age_group = 'old' THEN d7_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'old' THEN d7_cohort ELSE 0 END), 0) AS d7_old_users,

    -- D30
    SUM(CASE WHEN age_group = 'new' THEN d30_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'new' THEN d30_cohort ELSE 0 END), 0) AS d30_new_users,
    SUM(CASE WHEN age_group = '1w-1m' THEN d30_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1w-1m' THEN d30_cohort ELSE 0 END), 0) AS d30_1m_users,
    SUM(CASE WHEN age_group = '1m-1y' THEN d30_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = '1m-1y' THEN d30_cohort ELSE 0 END), 0) AS d30_1y_users,
    SUM(CASE WHEN age_group = 'old' THEN d30_retained ELSE 0 END)::FLOAT / NULLIF(SUM(CASE WHEN age_group = 'old' THEN d30_cohort ELSE 0 END), 0) AS d30_old_users
FROM retention_agg
GROUP BY 1
    )

SELECT
    c.dt,'global' as region,
    p.d1_new_users, p.d1_1m_users, p.d1_1y_users, p.d1_old_users,
    p.d3_new_users, p.d3_1m_users, p.d3_1y_users, p.d3_old_users,
    p.d7_new_users, p.d7_1m_users, p.d7_1y_users, p.d7_old_users,
    p.d30_new_users, p.d30_1m_users, p.d30_1y_users, p.d30_old_users
FROM calendar c
         LEFT JOIN pivoted_retention p ON c.dt = p.dt
ORDER BY c.dt DESC;
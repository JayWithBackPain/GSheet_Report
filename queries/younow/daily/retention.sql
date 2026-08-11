DROP TABLE IF EXISTS daily_new_users_temp;
CREATE TEMP TABLE daily_new_users_temp AS
SELECT
    datE_trunc('day',da.day) as dt,
    case when ud.locale in ('en','es','me') then ud.locale else 'Others' end as locale,
    case when ud.country in ('US','CA') then true else false end as is_na,
    da.userid,
    case when da.userdays = 0 then true else false end as is_new,
    case when ios_logins > 0 then true else false end as ios_login,
    case when android_logins > 0 then true else false end as aos_login,
    case when web_logins > 0 then true else false end as web_login
FROM dailyactives da
         LEFT JOIN users_data ud ON da.userid = ud.userid
WHERE da.day >= current_date-10 - INTERVAL '30 days';

WITH
-- Step 2: 地區擴展 (Global + 各國家)
regional_base AS (
    SELECT dt,'global' AS region,userid,is_new,ios_login,aos_login,web_login FROM daily_new_users_temp
    UNION ALL
    SELECT dt,'na' AS region,userid,is_new,ios_login,aos_login,web_login FROM daily_new_users_temp where is_na
    union all
    SELECT dt,locale AS region,userid,is_new,ios_login,aos_login,web_login FROM daily_new_users_temp
),

-- Step 3: 計算每個 Cohort 在 D7 與 D30 的留存人數
cohort_metrics AS (
    SELECT
        c.dt AS dt,
        c.region,
        -- 分母
        COUNT(DISTINCT c.userid) AS total_users,
        COUNT(DISTINCT CASE WHEN c.ios_login THEN c.userid END) AS ios_users,
        COUNT(DISTINCT CASE WHEN c.aos_login THEN c.userid END) AS aos_users,
        COUNT(DISTINCT CASE WHEN c.web_login THEN c.userid END) AS web_users,
        -- D1 分子 (與第 1 天活躍紀錄 join)
        count(distinct case when r1.userid is not null then c.userid end) as ret_cnt_d1,
        count(distinct case when r1.userid is not null and c.ios_login then c.userid end) as ret_ios_d1,
        count(distinct case when r1.userid is not null and c.aos_login then c.userid end) as ret_aos_d1,
        count(distinct case when r1.userid is not null and c.web_login then c.userid end) as ret_web_d1,

        -- D7 分子 (與第 7 天活躍紀錄 join)
        count(distinct case when r7.userid is not null then c.userid end) as ret_cnt_d7,
        count(distinct case when r7.userid is not null and c.ios_login then c.userid end) as ret_ios_d7,
        count(distinct case when r7.userid is not null and c.aos_login then c.userid end) as ret_aos_d7,
        count(distinct case when r7.userid is not null and c.web_login then c.userid end) as ret_web_d7
    FROM regional_base c
             -- 關聯 D1 活躍
             LEFT JOIN regional_base r1
                       ON c.userid = r1.userid AND r1.dt = c.dt + INTERVAL '1 days'
-- 關聯 D7 活躍
    LEFT JOIN regional_base r7
ON c.userid = r7.userid AND r7.dt = c.dt + INTERVAL '7 days'
where c.is_new
GROUP BY 1, 2
    ),

    daily_rates AS (
SELECT
    dt,
    region,
-- D1 Rates
    ret_cnt_d1::FLOAT / NULLIF(total_users, 0) AS rate_all_d1,
    ret_ios_d1::FLOAT / NULLIF(ios_users, 0) AS rate_ios_d1,
    ret_aos_d1::FLOAT / NULLIF(aos_users, 0) AS rate_aos_d1,
    ret_web_d1::FLOAT / NULLIF(web_users, 0) AS rate_web_d1,
-- D7 Rates
    ret_cnt_d7::FLOAT / NULLIF(total_users, 0) AS rate_all_d7,
    ret_ios_d7::FLOAT / NULLIF(ios_users, 0) AS rate_ios_d7,
    ret_aos_d7::FLOAT / NULLIF(aos_users, 0) AS rate_aos_d7,
    ret_web_d7::FLOAT / NULLIF(web_users, 0) AS rate_web_d7
FROM cohort_metrics
    )

-- Step 5: 向右對齊 (核心邏輯：D7 取 7天前, D30 取 30天前)
SELECT
    d.dt AS dt, -- 這裡的 base_date 是作為主軸的「報表日期」
    d.region,
    -- 取 1 天前的 Cohort 所產生的 D7 留存
    LAG(d.rate_all_d1, 1) OVER (PARTITION BY d.region ORDER BY d.dt) AS all_d1,
    LAG(d.rate_ios_d1, 1) OVER (PARTITION BY d.region ORDER BY d.dt) AS ios_d1,
    LAG(d.rate_aos_d1, 1) OVER (PARTITION BY d.region ORDER BY d.dt) AS aos_d1,
    LAG(d.rate_web_d1, 1) OVER (PARTITION BY d.region ORDER BY d.dt) AS web_d1,

	-- 取 7 天前的 Cohort 所產生的 D7 留存
    LAG(d.rate_all_d7, 7) OVER (PARTITION BY d.region ORDER BY d.dt) AS all_d7,
    LAG(d.rate_ios_d7, 7) OVER (PARTITION BY d.region ORDER BY d.dt) AS ios_d7,
    LAG(d.rate_aos_d7, 7) OVER (PARTITION BY d.region ORDER BY d.dt) AS aos_d7,
    LAG(d.rate_web_d7, 7) OVER (PARTITION BY d.region ORDER BY d.dt) AS web_d7
FROM daily_rates d
WITH base_data AS (
    -- 第一步：過濾日期並處理維度，先做一次 group by 減少資料量
    -- 這裡建議往回多抓 30 天，確保 '2025-03-01' 那天也有準確的 MAU
    SELECT
        date_trunc('day', da.day) AS dt,
        da.userid,
        CASE WHEN ud.locale IN ('en','es','me') THEN ud.locale ELSE 'Others' END AS locale,
        CASE WHEN ud.country in ('US','CA') THEN 1 ELSE 0 END AS is_na
    FROM dailyactives da
             LEFT JOIN users_data ud ON da.userid = ud.userid
    WHERE da.day >= dateadd(day, -30, current_date-10) -- 預熱 30 天資料
      AND da.day < current_date
    GROUP BY 1, 2, 3, 4
),
     daily_flags AS (
         -- 第二步：將維度拆解為旗標，方便後續用 SUM(...) 算出每個維度的不重複貢獻
         SELECT
             dt,
             userid,
             locale,
             is_na
         FROM base_data
     ),
     rolling_active AS (
         -- 第三步：使用 Window Function 取得每個用戶在過去 30 天是否活躍
         -- 為了效率，我們這裡使用 CROSS JOIN 一個日期表或使用更進階的自關聯
         -- 但在 Redshift 中，最快計算精確 MAU 的方式通常是將資料擴張 30 倍後聚合
         SELECT
             d.generated_date AS target_dt,
             b.userid,
             b.locale,
             b.is_na
         FROM (SELECT DISTINCT dt AS generated_date FROM base_data WHERE dt >= DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE))) d
                  JOIN base_data b ON b.dt <= d.generated_date
             AND b.dt > dateadd(day, -30, d.generated_date)
         GROUP BY 1, 2, 3, 4
     ),
     global_agg as (
         select
             target_dt as dt,
             'global' as region,
             count(distinct userid) as rmau
         from rolling_active
         group by 1,2
     ),
     regional_agg as (
         select
             target_dt as dt,
             locale as region,
             count(distinct userid) as rmau
         from rolling_active
         group by 1,2
     ),
     na_agg as (
         select
             target_dt as dt,
             'na' as region,
             count(distinct userid) as rmau
         from rolling_active
         where is_na
         group by 1,2
     )
select * from global_agg
union all
select * from regional_agg
union all
select * from na_agg
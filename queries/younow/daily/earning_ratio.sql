with recursive date_series(dt) as (
    select current_date- 10-'30 days'::interval
    union all
    select dateadd(day, 1, dt)
    from date_series
    where dt < current_date
),

               external AS (
                   SELECT
                       date_trunc('day', st.datecreated) AS dt,
                       SUM(amountdollars) AS rev
                   FROM store_transaction st
                            left join users_data ud on st.userid = ud.userid
                   WHERE st.datecreated < current_date
                     AND status IN ('AUTHORIZED', 'COMPLETED')
                     AND amountdollars > 0
                     and terminated = 0
                   GROUP BY 1
               ),
               earning AS (
                   SELECT
                       date_trunc('day', datecreated) AS dt,
                       SUM(CASE WHEN type = 'BROADCAST_EARNINGS' THEN totaldiamonds ELSE 0 END)::DECIMAL(38,2)/10000 AS broadcast_earnings,
                       SUM(CASE WHEN type = 'SUBSCRIPTION_EARNINGS' THEN totaldiamonds ELSE 0 END)::DECIMAL(38,2)/10000 AS subscription_earnings,
                       SUM(CASE WHEN type = 'GUEST_EARNINGS' THEN totaldiamonds ELSE 0 END)::DECIMAL(38,2)/10000 AS guest_earnings,
                       -1*SUM(CASE WHEN type = 'EXCHANGE_TO_BARS' THEN totaldiamonds ELSE 0 END)::DECIMAL(38,2)/10000 AS exchange_to_bars,
                       -1*sum(case when type = 'BUY_GIFT_SUBSCRIPTION' then totaldiamonds else 0 end)::decimal(38,2)/10000 as diamond_buy
                   FROM diamond_transactions_est
                   WHERE datecreated < current_date
                     AND status = 'COMPLETED'
                     and userid not in (58823343,60080959)
                     AND type IN ('BROADCAST_EARNINGS', 'SUBSCRIPTION_EARNINGS', 'GUEST_EARNINGS','EXCHANGE_TO_BARS','BUY_GIFT_SUBSCRIPTION')
                   GROUP BY 1
               ),
-- 彙整為每日 earnings/revenue
               daily AS (
                   SELECT
                       d.dt,
                       COALESCE(e.broadcast_earnings, 0) + COALESCE(e.subscription_earnings, 0) + COALESCE(e.guest_earnings, 0) AS total_earning,
                       coalesce(e.exchange_to_bars,0) as total_exchange,
                       coalesce(e.diamond_buy,0) as total_diamond_buy,
                       COALESCE(ex.rev, 0) AS total_rev
                   FROM date_series d
                            LEFT JOIN earning e ON d.dt = e.dt
                            LEFT JOIN external ex ON d.dt = ex.dt
               ),
-- 對每一天做 MTD 累積
               mtd_result AS (
                   SELECT
                       d1.dt,
                       SUM(d2.total_earning) AS cumulative_earning,
                       sum(d2.total_exchange) as cumulative_exchange,
                       sum(d2.total_diamond_buy) as cumulative_diamond_buy,
                       SUM(d2.total_rev) AS cumulative_rev
                   FROM daily d1
                            JOIN daily d2
                                 ON date_trunc('month', d2.dt) = date_trunc('month', d1.dt)
                                     AND d2.dt <= d1.dt
                   GROUP BY d1.dt
               )

SELECT
    dt,
    'global' as region,
    CASE
        WHEN cumulative_rev > 0 THEN (cumulative_earning-cumulative_exchange-cumulative_diamond_buy) / cumulative_rev
        ELSE NULL
        END AS earning_to_rev_ratio_mtd,
    CASE
        WHEN cumulative_rev > 0 THEN (cumulative_earning) / cumulative_rev
        ELSE NULL
        END AS raw_earning_to_rev_ratio_mtd
FROM mtd_result
ORDER BY dt desc;

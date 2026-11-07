CREATE DATABASE data_analysis;
USE data_analysis;
SELECT * FROM sales_data;
-- SECTION 1. DATA QUALITY AND VALIDATION
-- 1A. Row count, unique IDs, date range, basic domain counts.
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT `S.No`) AS unique_s_no,
       MIN(`Date`) AS first_date, MAX(`Date`) AS last_date,
       COUNT(DISTINCT `CompanyName`) AS unique_companies,
       COUNT(DISTINCT `Product`) AS unique_products,
       COUNT(DISTINCT `Category`) AS unique_categories,
       COUNT(DISTINCT `Area`) AS unique_areas
FROM sales_data;
-- 1B. NULL/blank checks. Columns are NOT NULL; blank strings are checked separately.
SELECT
 SUM(`S.No` IS NULL) AS null_s_no,
 SUM(`Year` IS NULL OR TRIM(`Year`)='') AS null_or_blank_year,
 SUM(`Date` IS NULL) AS null_date,
 SUM(`CompanyName` IS NULL OR TRIM(`CompanyName`)='') AS null_or_blank_company,
 SUM(`Area` IS NULL OR TRIM(`Area`)='') AS null_or_blank_area,
 SUM(`Product` IS NULL OR TRIM(`Product`)='') AS null_or_blank_product,
 SUM(`Category` IS NULL OR TRIM(`Category`)='') AS null_or_blank_category,
 SUM(`Quantity` IS NULL) AS null_quantity,
 SUM(`Price per unit` IS NULL) AS null_unit_price,
 SUM(`Cost` IS NULL) AS null_cost,
 SUM(`Selling Price` IS NULL) AS null_selling_price,
 SUM(`GST @ 18%` IS NULL) AS null_gst,
 SUM(`Invoice Value` IS NULL) AS null_invoice_value,
 SUM(`Profit` IS NULL) AS null_profit,
 SUM(`Margin %` IS NULL) AS null_margin
FROM sales_data;
-- SECTION 2. OVERALL BUSINESS HEALTH
CREATE OR REPLACE VIEW vw_overall_kpis AS
SELECT COUNT(*) AS transactions,
       COUNT(DISTINCT `CompanyName`) AS unique_companies,
       SUM(`Selling Price`) AS total_revenue_ex_gst,
       SUM(`Cost`) AS total_cost,
       SUM(`Profit`) AS total_profit,
       SUM(`GST @ 18%`) AS total_gst,
       SUM(`Invoice Value`) AS total_invoice_value,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS overall_margin_pct,
       AVG(`Invoice Value`) AS average_order_value_including_gst,
       AVG(`Selling Price`) AS average_sales_value_excluding_gst
FROM sales_data;
SELECT * FROM vw_overall_kpis;
-- Fiscal-year performance and YoY growth using LAG.
WITH annual AS (
 SELECT `Year` AS fiscal_year, COUNT(*) AS transactions,
        SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
        SUM(`Cost`) AS cost, SUM(`GST @ 18%`) AS gst,
        SUM(`Invoice Value`) AS invoice_value,
        SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
 FROM sales_data GROUP BY `Year`
), compare_years AS (
 SELECT annual.*,
        LAG(revenue) OVER (ORDER BY fiscal_year) AS prior_revenue,
        LAG(profit) OVER (ORDER BY fiscal_year) AS prior_profit
 FROM annual
)
SELECT *, ROUND((revenue-prior_revenue)/NULLIF(prior_revenue,0)*100,2) AS revenue_yoy_pct,
          ROUND((profit-prior_profit)/NULLIF(prior_profit,0)*100,2) AS profit_yoy_pct
FROM compare_years ORDER BY fiscal_year;

-- SECTION 3. MONTHLY / QUARTERLY TRENDS
-- ============================================================

CREATE OR REPLACE VIEW vw_monthly_performance AS
WITH monthly AS (
 SELECT DATE_FORMAT(`Date`,'%Y-%m-01') AS month_start,
        SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
        COUNT(*) AS transactions
 FROM sales_data GROUP BY DATE_FORMAT(`Date`,'%Y-%m-01')
)
SELECT month_start, revenue, profit, transactions,
       LAG(revenue) OVER (ORDER BY month_start) AS prior_month_revenue,
       ROUND((revenue-LAG(revenue) OVER (ORDER BY month_start)) /
             NULLIF(LAG(revenue) OVER (ORDER BY month_start),0)*100,2) AS revenue_mom_pct,
       SUM(revenue) OVER (ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue,
       AVG(revenue) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS revenue_3m_moving_avg,
       AVG(profit) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS profit_3m_moving_avg
FROM monthly;

SELECT * FROM vw_monthly_performance ORDER BY month_start;

-- Highest/lowest months and largest monthly declines.
SELECT * FROM vw_monthly_performance ORDER BY revenue DESC LIMIT 5;
SELECT * FROM vw_monthly_performance ORDER BY revenue ASC LIMIT 5;
SELECT * FROM vw_monthly_performance WHERE revenue_mom_pct <= -15 ORDER BY revenue_mom_pct;

-- SECTION 4. PRODUCT / CATEGORY PERFORMANCE
-- ============================================================

-- Top 10 products by revenue and profit (RANK/DENSE_RANK).
WITH p AS (
 SELECT `Product`, `Category`, SUM(`Selling Price`) AS revenue,
        SUM(`Profit`) AS profit, SUM(`Quantity`) AS quantity,
        COUNT(*) AS transactions,
        SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
 FROM sales_data GROUP BY `Product`, `Category`
), ranked AS (
 SELECT p.*,
        DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
        DENSE_RANK() OVER (ORDER BY profit DESC) AS profit_rank
 FROM p
)
SELECT * FROM ranked WHERE revenue_rank <= 10 OR profit_rank <= 10
ORDER BY revenue_rank, profit_rank;

SELECT `Category`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct,
       COUNT(*) AS transactions
FROM sales_data GROUP BY `Category`
ORDER BY revenue DESC;

-- High-volume products with below-average / thin margin (<15% default threshold).
WITH p AS (SELECT`Product`,`Category`,
        SUM(`Selling Price`) AS revenue,
        SUM(`Profit`) AS profit,
        SUM(`Quantity`) AS quantity,
        SUM(`Profit`) / NULLIF(SUM(`Selling Price`), 0) * 100 AS margin_pct
    FROM sales_data
    GROUP BY `Product`, `Category`
),
q AS (SELECT quantity,CUME_DIST() OVER (ORDER BY quantity) AS cd FROM p),

threshold AS (
    SELECT MIN(quantity) AS quantity_q3
    FROM q
    WHERE cd >= 0.75
)

SELECT p.*
FROM p
CROSS JOIN threshold
WHERE p.quantity >= threshold.quantity_q3
  AND p.margin_pct < 15
ORDER BY p.revenue DESC;

-- Loss-making or below 5% margin products/categories.
WITH p AS (
 SELECT `Product`, `Category`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
        SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
 FROM sales_data GROUP BY `Product`, `Category`
)
SELECT * FROM p WHERE profit < 0 OR margin_pct < 5 ORDER BY profit ASC, revenue DESC;

SELECT `Category`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
FROM sales_data GROUP BY `Category`
HAVING SUM(`Profit`) < 0 OR SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 < 5;

-- SECTION 5. CUSTOMER / COMPANY ANALYSIS
WITH c AS (
 SELECT `CompanyName`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
        COUNT(*) AS transactions,
        SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
 FROM sales_data GROUP BY `CompanyName`
), r AS (
 SELECT c.*, DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
        DENSE_RANK() OVER (ORDER BY profit DESC) AS profit_rank,
        NTILE(3) OVER (ORDER BY revenue DESC) AS value_tier_ntile
 FROM c
)
SELECT *, CASE value_tier_ntile
             WHEN 1 THEN 'High'
             WHEN 2 THEN 'Medium'
             ELSE 'Low'
          END AS customer_tier
FROM r WHERE revenue_rank <= 10 OR profit_rank <= 10
ORDER BY revenue_rank, profit_rank;

-- Revenue concentration in top 10 companies.
WITH c AS (
 SELECT `CompanyName`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit
 FROM sales_data GROUP BY `CompanyName`
), ranked AS (
 SELECT c.*, DENSE_RANK() OVER (ORDER BY revenue DESC) AS rnk FROM c
)
SELECT SUM(CASE WHEN rnk <= 10 THEN revenue ELSE 0 END) AS top10_revenue,
       SUM(revenue) AS total_revenue,
       SUM(CASE WHEN rnk <= 10 THEN revenue ELSE 0 END)/SUM(revenue)*100 AS top10_revenue_share_pct
FROM ranked;

-- Churn risk: company active in a prior fiscal year but absent in the latest fiscal year.
WITH company_year AS (
 SELECT `CompanyName`, `Year`, SUM(`Selling Price`) AS revenue
 FROM sales_data GROUP BY `CompanyName`, `Year`
), latest_year AS (SELECT MAX(`Year`) AS latest_fy FROM sales_data)
SELECT cy.`CompanyName`, SUM(cy.revenue) AS prior_revenue,
       MAX(cy.`Year`) AS most_recent_active_fy
FROM company_year cy CROSS JOIN latest_year ly
WHERE cy.`Year` < ly.latest_fy
  AND NOT EXISTS (SELECT 1 FROM company_year recent
                  WHERE recent.`CompanyName`=cy.`CompanyName` AND recent.`Year`=ly.latest_fy)
GROUP BY cy.`CompanyName` ORDER BY prior_revenue DESC;

-- SECTION 6. REGIONAL ANALYSIS AND PRODUCT-AREA MATRIX
SELECT `Area`, SUM(`Selling Price`) AS revenue, SUM(`Profit`) AS profit,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct,
       COUNT(*) AS transactions, COUNT(DISTINCT `CompanyName`) AS companies
FROM sales_data GROUP BY `Area` ORDER BY revenue DESC;

-- Product/category winners within each area.
WITH pa AS (
 SELECT `Area`, `Category`, `Product`, SUM(`Selling Price`) AS revenue,
        SUM(`Profit`) AS profit,
        ROW_NUMBER() OVER (PARTITION BY `Area` ORDER BY SUM(`Selling Price`) DESC) AS area_product_rank
 FROM sales_data GROUP BY `Area`, `Category`, `Product`
)
SELECT * FROM pa WHERE area_product_rank <= 5 ORDER BY `Area`, area_product_rank;

-- SECTION 8. REUSABLE VIEW / DASHBOARD EXPORT QUERIES
-- ============================================================

CREATE OR REPLACE VIEW vw_category_kpis AS
SELECT `Category`, COUNT(*) AS transactions,
       SUM(`Selling Price`) AS revenue, SUM(`Cost`) AS cost,
       SUM(`Profit`) AS profit, SUM(`GST @ 18%`) AS gst,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
FROM sales_data GROUP BY `Category`;

CREATE OR REPLACE VIEW vw_area_kpis AS
SELECT `Area`, COUNT(*) AS transactions,
       SUM(`Selling Price`) AS revenue, SUM(`Cost`) AS cost,
       SUM(`Profit`) AS profit,
       SUM(`Profit`)/NULLIF(SUM(`Selling Price`),0)*100 AS margin_pct
FROM sales_data GROUP BY `Area`;


SELECT * FROM vw_overall_kpis;
SELECT * FROM vw_monthly_performance ORDER BY month_start;
SELECT * FROM vw_category_kpis ORDER BY revenue DESC;
SELECT * FROM vw_area_kpis ORDER BY revenue DESC;
SELECT * FROM vw_company_kpis ORDER BY revenue DESC;
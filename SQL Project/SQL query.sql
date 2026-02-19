DROP TABLE IF EXISTS ecommerce_cleaned_raw;
CREATE TABLE ecommerce_cleaned_raw (
  order_id        text,
  customer_id     text,
  customer_name   text,
  product_name    text,
  category        text,
  order_date      date,
  quantity        int,
  unit_price      numeric(10,2),
  discount        numeric(5,2),
  total_amount    numeric(12,4),
  profit          numeric(12,2),
  payment_method  text,
  country         text,
  city            text,
  postal_code     text,         
  ship_mode       text,
  ship_date       date,
  review_rating   int,
  correct_total   numeric(12,4)
);

select * from ecommerce_cleaned_raw;


DROP TABLE IF EXISTS customers CASCADE;

---customers--

CREATE TABLE customers (
  customer_id    text PRIMARY KEY,
  customer_name  text,
  country        text,
  city           text,
  postal_code    text
);



INSERT INTO customers (customer_id, customer_name, country, city, postal_code)
SELECT DISTINCT ON (customer_id)
  customer_id,
  customer_name,
  country,
  city,
  postal_code
FROM ecommerce_cleaned_raw;

select * from customers;

---products--

DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE products (
  product_id    serial PRIMARY KEY,
  product_name  text NOT NULL,
  category      text,
  unit_price    numeric(10,2),
  UNIQUE(product_name, category, unit_price)
);

INSERT INTO products (product_name, category, unit_price)
SELECT DISTINCT
  product_name,
  category,
  unit_price
FROM ecommerce_cleaned_raw
WHERE product_name IS NOT NULL;

select * from products;

--shipping---

DROP TABLE IF EXISTS shipping CASCADE;

CREATE TABLE shipping (
  shipping_id  serial PRIMARY KEY,
  ship_mode    text,
  ship_date    date,
  UNIQUE(ship_mode, ship_date)
);

INSERT INTO shipping (ship_mode, ship_date)
SELECT DISTINCT
  ship_mode,
  ship_date
FROM ecommerce_cleaned_raw
WHERE ship_date IS NOT NULL;

select * from shipping;


---orders---

DROP TABLE IF EXISTS orders CASCADE;

CREATE TABLE orders (
  order_id        text PRIMARY KEY,
  order_date      date,
  customer_id     text REFERENCES customers(customer_id),
  payment_method  text,
  shipping_id     int REFERENCES shipping(shipping_id)
);

INSERT INTO orders (order_id, order_date, customer_id, payment_method, shipping_id)
SELECT DISTINCT
  r.order_id,
  r.order_date,
  r.customer_id,
  r.payment_method,
  s.shipping_id
FROM ecommerce_cleaned_raw r
LEFT JOIN shipping s
  ON s.ship_mode = r.ship_mode
 AND s.ship_date = r.ship_date;

 select * from orders;

----sales_fact---

DROP TABLE IF EXISTS sales_fact;

CREATE TABLE sales_fact (
  sales_id       bigserial PRIMARY KEY,
  order_id       text NOT NULL REFERENCES orders(order_id),
  product_id     int  NOT NULL REFERENCES products(product_id),
  quantity       int,
  discount       numeric(5,2),
  total_amount   numeric(12,4),
  profit         numeric(12,2),
  review_rating  int,
  UNIQUE(order_id, product_id)  
);

INSERT INTO sales_fact (order_id, product_id, quantity, discount, total_amount, profit, review_rating)
SELECT
  r.order_id,
  p.product_id,
  r.quantity,
  r.discount,
  r.total_amount,
  r.profit,
  r.review_rating
FROM ecommerce_cleaned_raw r
JOIN products p
  ON p.product_name = r.product_name
 AND p.category     = r.category
 AND p.unit_price   = r.unit_price;

 select * from sales_fact;



 SELECT
  o.order_id,
  o.order_date,
  c.customer_name,
  p.product_name,
  s.ship_mode,
  f.quantity,
  f.total_amount
FROM sales_fact f
JOIN orders o     ON o.order_id = f.order_id
JOIN customers c  ON c.customer_id = o.customer_id
JOIN products p   ON p.product_id = f.product_id
LEFT JOIN shipping s 
       ON s.shipping_id = o.shipping_id;

-- 1. How much overall revenue and profit has the business generated?

SELECT
  ROUND(SUM(f.total_amount), 2) AS total_revenue,
  ROUND(SUM(f.profit), 2)       AS total_profit
FROM sales_fact f;

	   
-- 2. Calculate the total revenue generated each month

SELECT
  DATE_TRUNC('month', o.order_date) AS month,
  ROUND(SUM(f.total_amount), 2)     AS revenue
FROM sales_fact f
JOIN orders o ON o.order_id = f.order_id
GROUP BY 1
ORDER BY 1;


-- 3. What are the top 10 profit-generating products?


SELECT
  p.product_name,
  p.category,
  ROUND(SUM(f.profit), 2) AS total_profit
FROM sales_fact f
JOIN products p ON p.product_id = f.product_id
GROUP BY 1,2
ORDER BY total_profit DESC
LIMIT 10;


-- 4. Which categories contribute most to total profit?


SELECT
  p.product_name,
  p.category,
  ROUND(AVG(f.review_rating)::numeric, 2) AS avg_rating,
  COUNT(*) AS ratings_count
FROM sales_fact f
JOIN products p ON p.product_id = f.product_id
WHERE f.review_rating IS NOT NULL
GROUP BY 1,2
HAVING AVG(f.review_rating) < 3
ORDER BY avg_rating;



-- -5. What are the top 10 revenue-generating products?


SELECT
  c.country,
  c.city,
  ROUND(SUM(f.total_amount), 2) AS revenue
FROM sales_fact f
JOIN orders o    ON o.order_id = f.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY 1,2
ORDER BY revenue DESC
LIMIT 10;



-- 6. Who are the repeat customers based on multiple orders?


SELECT
  c.customer_id,
  c.customer_name,
  COUNT(DISTINCT o.order_id) AS orders_count
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY 1,2
HAVING COUNT(DISTINCT o.order_id) > 1
ORDER BY orders_count DESC;

-- -7. Who are the highest value customers based on total spending?

SELECT
  p.category,
  ROUND(SUM(f.profit), 2) AS profit
FROM sales_fact f
JOIN products p ON p.product_id = f.product_id
GROUP BY 1z
ORDER BY profit DESC
LIMIT 5;


-- 8. Which products are receiving poor customer ratings?

SELECT
p.product_name,
p.category,
ROUND (AVG(f.review_rating):: numeric, 2) AS avg_rating,
COUNT(*) AS ratings_count
FROM sales_fact f
JOIN products p ON p.product_id = f.product_id
WHERE f.review_rating IS NOT NULL
GROUP BY 1,2
HAVING AVG(f.review_rating) < 3
ORDER BY avg_rating;



-- 9. Which cities drive the most sales revenue?


SELECT
c.country,
c.city,
ROUND (SUM(f.total_amount), 2) AS revenue
FROM sales_fact f
JOIN orders o ON o.order_id = f.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY 1,2
ORDER BY revenue DESC
LIMIT 10;



-- 10. How do different discount ranges impact total revenue and profit?


SELECT
CASE
WHEN f.discount = 0 THEN '0%'
WHEN f.discount <= 0.10 THEN '1-10%'
WHEN f.discount <= 0.20 THEN '11-20%'
ELSE '21%+'
END AS discount_bucket,
ROUND (SUM (f.total_amount), 2) AS revenue,
ROUND (SUM(f.profit), 2)
FROM sales_fact f
GROUP BY 1
ORDER BY 1;
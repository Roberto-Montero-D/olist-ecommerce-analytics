SET search_path TO olist;

\echo 'Loading customers...'
\copy customers FROM '/tmp/olist_raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading orders...'
\copy orders FROM '/tmp/olist_raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading products...'
\copy products FROM '/tmp/olist_raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading sellers...'
\copy sellers FROM '/tmp/olist_raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order items...'
\copy order_items FROM '/tmp/olist_raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order payments...'
\copy order_payments FROM '/tmp/olist_raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading order reviews...'
\copy order_reviews FROM '/tmp/olist_raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading category translations...'
\copy category_translation FROM '/tmp/olist_raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading geolocation...'
\copy geolocation FROM '/tmp/olist_raw/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true);

\echo 'Raw data load complete.'
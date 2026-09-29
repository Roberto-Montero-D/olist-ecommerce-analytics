-- Synthetic deterministic fixture for GitHub Actions CI.
-- This is intentionally small and is not a replacement for the Olist dataset.

SET search_path TO olist;

INSERT INTO customers (
    customer_id, customer_unique_id, customer_zip_code_prefix,
    customer_city, customer_state
) VALUES
    ('c001', 'u001', '01001', 'São Paulo', 'SP'),
    ('c002', 'u001', '02002', 'Sao Paulo', 'SP'),
    ('c003', 'u002', '99999', 'Fallback City', 'RJ');

INSERT INTO products (
    product_id, product_category_name, product_name_lenght,
    product_description_lenght, product_photos_qty,
    product_weight_g, product_length_cm, product_height_cm, product_width_cm
) VALUES
    ('p001', 'beleza_saude', 20, 100, 2, 500, 20, 10, 15),
    ('p002', 'categoria_sem_traducao', 15, 80, 1, 300, 15, 8, 12);

INSERT INTO sellers (
    seller_id, seller_zip_code_prefix, seller_city, seller_state
) VALUES
    ('s001', '01001', 'São Paulo', 'SP'),
    ('s002', '03003', 'Campinas', 'SP');

INSERT INTO category_translation (
    product_category_name, product_category_name_english
) VALUES
    ('beleza_saude', 'health_beauty');

INSERT INTO orders (
    order_id, customer_id, order_status, order_purchase_timestamp,
    order_approved_at, order_delivered_carrier_date,
    order_delivered_customer_date, order_estimated_delivery_date
) VALUES
    (
        'o001', 'c001', 'delivered',
        '2018-01-10 10:00:00', '2018-01-10 12:00:00',
        '2018-01-11 08:00:00', '2018-01-15 10:00:00',
        '2018-01-17 10:00:00'
    ),
    (
        'o002', 'c002', 'delivered',
        '2018-02-01 09:00:00', '2018-02-01 11:00:00',
        '2018-02-03 08:00:00', '2018-02-12 09:00:00',
        '2018-02-10 09:00:00'
    ),
    (
        'o003', 'c003', 'canceled',
        '2018-03-05 14:00:00', NULL, NULL, NULL,
        '2018-03-20 00:00:00'
    );

INSERT INTO order_items (
    order_id, order_item_id, product_id, seller_id,
    shipping_limit_date, price, freight_value
) VALUES
    ('o001', 1, 'p001', 's001', '2018-01-12 10:00:00', 100.00, 10.00),
    ('o001', 2, 'p002', 's002', '2018-01-12 10:00:00', 50.00, 5.00),
    ('o002', 1, 'p001', 's001', '2018-02-04 09:00:00', 80.00, 8.00);

INSERT INTO order_payments (
    order_id, payment_sequential, payment_type,
    payment_installments, payment_value
) VALUES
    ('o001', 1, 'credit_card', 2, 120.00),
    ('o001', 2, 'voucher', 1, 45.00),
    ('o002', 1, 'credit_card', 1, 88.00);

INSERT INTO order_reviews (
    review_id, order_id, review_score, review_comment_title,
    review_comment_message, review_creation_date, review_answer_timestamp
) VALUES
    (
        'r001', 'o001', 5, 'Great', 'Arrived early',
        '2018-01-16 00:00:00', '2018-01-16 12:00:00'
    ),
    (
        'r002', 'o002', 2, NULL, 'Late delivery',
        '2018-02-13 00:00:00', '2018-02-14 10:00:00'
    ),
    (
        'r003', 'o002', 3, 'Update', NULL,
        '2018-02-15 00:00:00', '2018-02-15 08:00:00'
    );

-- 01001 deliberately has multiple normalized city/state candidates.
-- "São Paulo" has modal support and must win deterministically.
INSERT INTO geolocation (
    geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
    geolocation_city, geolocation_state
) VALUES
    ('01001', -23.5505, -46.6333, 'São Paulo', 'SP'),
    ('01001', -23.5506, -46.6334, 'Sao Paulo', 'SP'),
    ('01001', -23.5507, -46.6335, 'São Paulo', 'SP'),
    ('01001', -23.5600, -46.6400, 'Outra Cidade', 'SP'),
    ('02002', -23.5000, -46.6000, 'Sao Paulo', 'SP'),
    ('03003', -22.9000, -47.0600, 'Campinas', 'SP');

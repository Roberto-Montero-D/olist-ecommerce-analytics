/*
===============================================================================
Olist E-Commerce Analytics
File: sql/warehouse/01_create_warehouse_schema.sql
Phase: B2.2 — Dimensional Modeling & Data Warehouse

Purpose
-------
Create the empty dimensional warehouse schema from the frozen B2 design.

This script creates structure only. It does not load warehouse data.
===============================================================================
*/

BEGIN;

CREATE SCHEMA IF NOT EXISTS dw;

-- Rebuild only warehouse objects; source schema `olist` is untouched.
DROP TABLE IF EXISTS dw.fact_reviews CASCADE;
DROP TABLE IF EXISTS dw.fact_payments CASCADE;
DROP TABLE IF EXISTS dw.fact_order_items CASCADE;
DROP TABLE IF EXISTS dw.fact_orders CASCADE;
DROP TABLE IF EXISTS dw.dim_order_status CASCADE;
DROP TABLE IF EXISTS dw.dim_seller CASCADE;
DROP TABLE IF EXISTS dw.dim_product CASCADE;
DROP TABLE IF EXISTS dw.dim_location CASCADE;
DROP TABLE IF EXISTS dw.dim_customer CASCADE;
DROP TABLE IF EXISTS dw.dim_date CASCADE;


-- ============================================================================
-- DIMENSIONS
-- ============================================================================

CREATE TABLE dw.dim_date (
    date_key        INTEGER PRIMARY KEY,
    full_date       DATE NOT NULL UNIQUE,
    year            SMALLINT NOT NULL,
    quarter         SMALLINT NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month           SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
    month_name      VARCHAR(20) NOT NULL,
    year_month      CHAR(7) NOT NULL,
    day             SMALLINT NOT NULL CHECK (day BETWEEN 1 AND 31),
    day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    day_name        VARCHAR(20) NOT NULL,
    is_weekend      BOOLEAN NOT NULL,
    CHECK (date_key = (TO_CHAR(full_date, 'YYYYMMDD'))::INTEGER)
);

CREATE TABLE dw.dim_customer (
    customer_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_unique_id  VARCHAR(32) NOT NULL UNIQUE
);

CREATE TABLE dw.dim_location (
    location_key                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zip_code_prefix              CHAR(5) NOT NULL UNIQUE,
    city                         TEXT,
    city_normalized              TEXT,
    state                        CHAR(2),
    latitude                     NUMERIC(10,7),
    longitude                    NUMERIC(10,7),
    geolocation_observation_count INTEGER NOT NULL DEFAULT 0
        CHECK (geolocation_observation_count >= 0),
    candidate_location_count     INTEGER NOT NULL DEFAULT 0
        CHECK (candidate_location_count >= 0),
    canonical_observation_count  INTEGER NOT NULL DEFAULT 0
        CHECK (canonical_observation_count >= 0),
    is_ambiguous                 BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (zip_code_prefix ~ '^[0-9]{5}$'),
    CHECK (state IS NULL OR state ~ '^[A-Z]{2}$'),
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE TABLE dw.dim_product (
    product_key                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id                     VARCHAR(32) NOT NULL UNIQUE,
    product_category_name          TEXT,
    product_category_name_english  TEXT,
    product_name_length            INTEGER,
    product_description_length     INTEGER,
    product_photos_qty             INTEGER,
    product_weight_g               NUMERIC(12,2),
    product_length_cm              NUMERIC(10,2),
    product_height_cm              NUMERIC(10,2),
    product_width_cm               NUMERIC(10,2),
    CHECK (product_name_length IS NULL OR product_name_length >= 0),
    CHECK (product_description_length IS NULL OR product_description_length >= 0),
    CHECK (product_photos_qty IS NULL OR product_photos_qty >= 0),
    CHECK (product_weight_g IS NULL OR product_weight_g >= 0),
    CHECK (product_length_cm IS NULL OR product_length_cm >= 0),
    CHECK (product_height_cm IS NULL OR product_height_cm >= 0),
    CHECK (product_width_cm IS NULL OR product_width_cm >= 0)
);

CREATE TABLE dw.dim_seller (
    seller_key  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   VARCHAR(32) NOT NULL UNIQUE
);

CREATE TABLE dw.dim_order_status (
    order_status_key  SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_status      VARCHAR(30) NOT NULL UNIQUE
);


-- ============================================================================
-- FACTS
-- ============================================================================

CREATE TABLE dw.fact_orders (
    order_key                         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                          VARCHAR(32) NOT NULL UNIQUE,

    customer_key                      BIGINT NOT NULL
        REFERENCES dw.dim_customer(customer_key),
    customer_location_key             BIGINT
        REFERENCES dw.dim_location(location_key),
    order_status_key                  SMALLINT NOT NULL
        REFERENCES dw.dim_order_status(order_status_key),

    purchase_date_key                 INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),
    approved_date_key                 INTEGER
        REFERENCES dw.dim_date(date_key),
    carrier_date_key                  INTEGER
        REFERENCES dw.dim_date(date_key),
    delivered_customer_date_key       INTEGER
        REFERENCES dw.dim_date(date_key),
    estimated_delivery_date_key       INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),

    customer_id                       VARCHAR(32) NOT NULL,

    order_purchase_timestamp          TIMESTAMP NOT NULL,
    order_approved_at                 TIMESTAMP,
    order_delivered_carrier_date      TIMESTAMP,
    order_delivered_customer_date     TIMESTAMP,
    order_estimated_delivery_date     TIMESTAMP NOT NULL,

    delivery_days                     NUMERIC(10,2),
    delivery_delay_days               NUMERIC(10,2),
    is_late_delivery                  BOOLEAN
);

CREATE TABLE dw.fact_order_items (
    order_item_key            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                  VARCHAR(32) NOT NULL,
    order_item_id             INTEGER NOT NULL,

    product_key               BIGINT NOT NULL
        REFERENCES dw.dim_product(product_key),
    seller_key                BIGINT NOT NULL
        REFERENCES dw.dim_seller(seller_key),
    customer_key              BIGINT NOT NULL
        REFERENCES dw.dim_customer(customer_key),
    customer_location_key     BIGINT
        REFERENCES dw.dim_location(location_key),
    seller_location_key       BIGINT
        REFERENCES dw.dim_location(location_key),
    order_status_key          SMALLINT NOT NULL
        REFERENCES dw.dim_order_status(order_status_key),

    purchase_date_key         INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),
    shipping_limit_date_key   INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),

    shipping_limit_date       TIMESTAMP NOT NULL,
    price                     NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    freight_value             NUMERIC(12,2) NOT NULL CHECK (freight_value >= 0),

    CONSTRAINT uq_fact_order_items
        UNIQUE (order_id, order_item_id)
);

CREATE TABLE dw.fact_payments (
    payment_key               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                  VARCHAR(32) NOT NULL,
    payment_sequential        INTEGER NOT NULL,

    customer_key              BIGINT NOT NULL
        REFERENCES dw.dim_customer(customer_key),
    customer_location_key     BIGINT
        REFERENCES dw.dim_location(location_key),
    order_status_key          SMALLINT NOT NULL
        REFERENCES dw.dim_order_status(order_status_key),
    purchase_date_key         INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),

    payment_type              VARCHAR(30) NOT NULL,
    payment_installments      INTEGER NOT NULL CHECK (payment_installments >= 0),
    payment_value             NUMERIC(12,2) NOT NULL CHECK (payment_value >= 0),

    CONSTRAINT uq_fact_payments
        UNIQUE (order_id, payment_sequential)
);

CREATE TABLE dw.fact_reviews (
    review_key                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    review_id                 VARCHAR(32) NOT NULL,
    order_id                  VARCHAR(32) NOT NULL,

    customer_key              BIGINT NOT NULL
        REFERENCES dw.dim_customer(customer_key),
    customer_location_key     BIGINT
        REFERENCES dw.dim_location(location_key),
    order_status_key          SMALLINT NOT NULL
        REFERENCES dw.dim_order_status(order_status_key),

    purchase_date_key         INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),
    review_creation_date_key  INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),
    review_answer_date_key    INTEGER NOT NULL
        REFERENCES dw.dim_date(date_key),

    review_score              SMALLINT NOT NULL
        CHECK (review_score BETWEEN 1 AND 5),
    review_creation_date      TIMESTAMP NOT NULL,
    review_answer_timestamp   TIMESTAMP NOT NULL,
    review_comment_title      TEXT,
    review_comment_message    TEXT,
    has_title                 BOOLEAN NOT NULL,
    has_message               BOOLEAN NOT NULL,

    CONSTRAINT uq_fact_reviews
        UNIQUE (review_id, order_id)
);


-- ============================================================================
-- INDEXES FOR COMMON FACT/DIMENSION FILTERS AND JOINS
-- ============================================================================

CREATE INDEX idx_fact_orders_customer
    ON dw.fact_orders(customer_key);
CREATE INDEX idx_fact_orders_customer_location
    ON dw.fact_orders(customer_location_key);
CREATE INDEX idx_fact_orders_purchase_date
    ON dw.fact_orders(purchase_date_key);
CREATE INDEX idx_fact_orders_status
    ON dw.fact_orders(order_status_key);

CREATE INDEX idx_fact_order_items_order
    ON dw.fact_order_items(order_id);
CREATE INDEX idx_fact_order_items_product
    ON dw.fact_order_items(product_key);
CREATE INDEX idx_fact_order_items_seller
    ON dw.fact_order_items(seller_key);
CREATE INDEX idx_fact_order_items_customer
    ON dw.fact_order_items(customer_key);
CREATE INDEX idx_fact_order_items_customer_location
    ON dw.fact_order_items(customer_location_key);
CREATE INDEX idx_fact_order_items_seller_location
    ON dw.fact_order_items(seller_location_key);
CREATE INDEX idx_fact_order_items_purchase_date
    ON dw.fact_order_items(purchase_date_key);

CREATE INDEX idx_fact_payments_order
    ON dw.fact_payments(order_id);
CREATE INDEX idx_fact_payments_customer
    ON dw.fact_payments(customer_key);
CREATE INDEX idx_fact_payments_purchase_date
    ON dw.fact_payments(purchase_date_key);

CREATE INDEX idx_fact_reviews_order
    ON dw.fact_reviews(order_id);
CREATE INDEX idx_fact_reviews_customer
    ON dw.fact_reviews(customer_key);
CREATE INDEX idx_fact_reviews_creation_date
    ON dw.fact_reviews(review_creation_date_key);
CREATE INDEX idx_fact_reviews_answer_date
    ON dw.fact_reviews(review_answer_date_key);

COMMIT;

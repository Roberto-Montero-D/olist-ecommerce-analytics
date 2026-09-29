import os
from pathlib import Path

import psycopg2
import pytest

ROOT = Path(__file__).resolve().parents[1]

PIPELINE = [
    ROOT / "sql/schema/01_create_source_schema.sql",
    ROOT / "tests/fixtures/ci_seed.sql",
    ROOT / "sql/warehouse/01_create_warehouse_schema.sql",
    ROOT / "sql/warehouse/02_load_dimensions.sql",
    ROOT / "sql/warehouse/02b_validate_loaded_dimensions.sql",
    ROOT / "sql/warehouse/03_load_facts.sql",
]


def connect():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "olist_test"),
        user=os.getenv("POSTGRES_USER", "olist"),
        password=os.getenv("POSTGRES_PASSWORD", "olist"),
    )


def execute_file(connection, path: Path) -> None:
    sql = path.read_text(encoding="utf-8-sig")
    with connection.cursor() as cursor:
        cursor.execute(sql)
    connection.commit()


@pytest.fixture(scope="module")
def warehouse():
    connection = connect()
    for path in PIPELINE:
        execute_file(connection, path)
    yield connection
    connection.close()


def scalar(connection, query: str):
    with connection.cursor() as cursor:
        cursor.execute(query)
        return cursor.fetchone()[0]


def test_fact_row_counts_reconcile_to_source(warehouse):
    pairs = [
        ("olist.orders", "dw.fact_orders"),
        ("olist.order_items", "dw.fact_order_items"),
        ("olist.order_payments", "dw.fact_payments"),
        ("olist.order_reviews", "dw.fact_reviews"),
    ]
    for source, fact in pairs:
        assert scalar(warehouse, f"SELECT COUNT(*) FROM {source}") == scalar(
            warehouse, f"SELECT COUNT(*) FROM {fact}"
        )


def test_natural_fact_grains_are_unique(warehouse):
    checks = [
        ("dw.fact_orders", "order_id"),
        ("dw.fact_order_items", "order_id, order_item_id"),
        ("dw.fact_payments", "order_id, payment_sequential"),
        ("dw.fact_reviews", "review_id, order_id"),
    ]
    for table, columns in checks:
        query = f"""
            SELECT COUNT(*)
            FROM (
                SELECT {columns}
                FROM {table}
                GROUP BY {columns}
                HAVING COUNT(*) > 1
            ) q
        """
        assert scalar(warehouse, query) == 0


def test_conformed_dimension_counts(warehouse):
    assert scalar(warehouse, "SELECT COUNT(*) FROM dw.dim_customer") == 2
    assert scalar(warehouse, "SELECT COUNT(*) FROM dw.dim_product") == 2
    assert scalar(warehouse, "SELECT COUNT(*) FROM dw.dim_seller") == 2
    assert scalar(warehouse, "SELECT COUNT(*) FROM dw.dim_order_status") == 2


def test_location_canonicalization_and_fallback(warehouse):
    assert scalar(
        warehouse,
        """
        SELECT candidate_location_count
        FROM dw.dim_location
        WHERE zip_code_prefix = '01001'
        """,
    ) == 2

    assert scalar(
        warehouse,
        """
        SELECT is_ambiguous
        FROM dw.dim_location
        WHERE zip_code_prefix = '01001'
        """,
    ) is True

    assert scalar(
        warehouse,
        """
        SELECT geolocation_observation_count
        FROM dw.dim_location
        WHERE zip_code_prefix = '99999'
        """,
    ) == 0

    assert scalar(
        warehouse,
        """
        SELECT latitude IS NULL AND longitude IS NULL
        FROM dw.dim_location
        WHERE zip_code_prefix = '99999'
        """,
    ) is True


def test_untranslated_product_category_is_preserved(warehouse):
    assert scalar(
        warehouse,
        """
        SELECT COUNT(*)
        FROM dw.dim_product
        WHERE product_category_name = 'categoria_sem_traducao'
          AND product_category_name_english IS NULL
        """,
    ) == 1


def test_multi_review_event_grain_is_preserved(warehouse):
    assert scalar(
        warehouse,
        "SELECT COUNT(*) FROM dw.fact_reviews WHERE order_id = 'o002'",
    ) == 2


def test_delivery_derivations(warehouse):
    with warehouse.cursor() as cursor:
        cursor.execute(
            """
            SELECT delivery_days, delivery_delay_days, is_late_delivery
            FROM dw.fact_orders
            WHERE order_id = 'o002'
            """
        )
        delivery_days, delay_days, is_late = cursor.fetchone()

    assert float(delivery_days) == 11.0
    assert float(delay_days) == 2.0
    assert is_late is True

    with warehouse.cursor() as cursor:
        cursor.execute(
            """
            SELECT delivery_days, delivery_delay_days, is_late_delivery
            FROM dw.fact_orders
            WHERE order_id = 'o003'
            """
        )
        canceled = cursor.fetchone()

    assert canceled == (None, None, None)


def test_financial_reconciliation(warehouse):
    comparisons = [
        ("olist.order_items", "dw.fact_order_items", "price"),
        ("olist.order_items", "dw.fact_order_items", "freight_value"),
        ("olist.order_payments", "dw.fact_payments", "payment_value"),
    ]
    for source, fact, column in comparisons:
        source_total = scalar(warehouse, f"SELECT SUM({column}) FROM {source}")
        fact_total = scalar(warehouse, f"SELECT SUM({column}) FROM {fact}")
        assert source_total == fact_total


def test_review_flags_match_nullable_comments(warehouse):
    invalid = scalar(
        warehouse,
        """
        SELECT COUNT(*)
        FROM dw.fact_reviews
        WHERE has_title IS DISTINCT FROM (review_comment_title IS NOT NULL)
           OR has_message IS DISTINCT FROM (review_comment_message IS NOT NULL)
        """,
    )
    assert invalid == 0

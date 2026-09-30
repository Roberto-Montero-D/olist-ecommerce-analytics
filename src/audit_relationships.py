from pathlib import Path

import pandas as pd

RAW_DATA_DIR = Path("data/raw")


def load_csv(filename: str) -> pd.DataFrame:
    """Load a CSV file from the raw Olist data directory."""
    return pd.read_csv(RAW_DATA_DIR / filename)


def check_unique_key(
    df: pd.DataFrame,
    columns: list[str],
    table_name: str,
) -> None:
    """Report whether the specified columns uniquely identify rows."""
    duplicate_count = df.duplicated(subset=columns).sum()

    print(
        f"{table_name}: {columns} -> "
        f"{'UNIQUE' if duplicate_count == 0 else 'NOT UNIQUE'} "
        f"({duplicate_count:,} duplicates)"
    )


def check_foreign_key(
    child_df: pd.DataFrame,
    child_column: str,
    parent_df: pd.DataFrame,
    parent_column: str,
    relationship_name: str,
) -> None:
    """Report distinct child key values missing from the parent table."""
    child_values = set(child_df[child_column].dropna())
    parent_values = set(parent_df[parent_column].dropna())

    missing_values = child_values - parent_values

    print(
        f"{relationship_name}: "
        f"{len(missing_values):,} orphan key values"
    )


def check_parent_coverage(
    parent_df: pd.DataFrame,
    parent_column: str,
    child_df: pd.DataFrame,
    child_column: str,
    relationship_name: str,
) -> None:
    """Report parent records without a corresponding child record."""
    parent_values = set(parent_df[parent_column].dropna())
    child_values = set(child_df[child_column].dropna())

    without_children = parent_values - child_values

    print(
        f"{relationship_name}: "
        f"{len(without_children):,} parent records without children"
    )


def main() -> None:
    """Run relationship, key, and coverage audits for the raw Olist data."""
    customers = load_csv("olist_customers_dataset.csv")
    orders = load_csv("olist_orders_dataset.csv")
    order_items = load_csv("olist_order_items_dataset.csv")
    payments = load_csv("olist_order_payments_dataset.csv")
    reviews = load_csv("olist_order_reviews_dataset.csv")
    products = load_csv("olist_products_dataset.csv")
    sellers = load_csv("olist_sellers_dataset.csv")
    categories = load_csv("product_category_name_translation.csv")

    print("\nCANDIDATE KEY CHECKS")
    print("-" * 60)

    check_unique_key(customers, ["customer_id"], "customers")
    check_unique_key(orders, ["order_id"], "orders")
    check_unique_key(products, ["product_id"], "products")
    check_unique_key(sellers, ["seller_id"], "sellers")
    check_unique_key(
        categories,
        ["product_category_name"],
        "category_translation",
    )
    check_unique_key(
        order_items,
        ["order_id", "order_item_id"],
        "order_items",
    )
    check_unique_key(
        payments,
        ["order_id", "payment_sequential"],
        "payments",
    )
    check_unique_key(reviews, ["review_id"], "reviews")
    check_unique_key(reviews, ["order_id"], "reviews")
    check_unique_key(
        reviews,
        ["review_id", "order_id"],
        "reviews",
    )

    print("\nFOREIGN KEY CHECKS")
    print("-" * 60)

    check_foreign_key(
        orders,
        "customer_id",
        customers,
        "customer_id",
        "orders.customer_id -> customers.customer_id",
    )
    check_foreign_key(
        order_items,
        "order_id",
        orders,
        "order_id",
        "order_items.order_id -> orders.order_id",
    )
    check_foreign_key(
        order_items,
        "product_id",
        products,
        "product_id",
        "order_items.product_id -> products.product_id",
    )
    check_foreign_key(
        order_items,
        "seller_id",
        sellers,
        "seller_id",
        "order_items.seller_id -> sellers.seller_id",
    )
    check_foreign_key(
        payments,
        "order_id",
        orders,
        "order_id",
        "payments.order_id -> orders.order_id",
    )
    check_foreign_key(
        reviews,
        "order_id",
        orders,
        "order_id",
        "reviews.order_id -> orders.order_id",
    )

    print("\nRELATIONSHIP COVERAGE")
    print("-" * 60)

    check_parent_coverage(
        orders,
        "order_id",
        order_items,
        "order_id",
        "orders without items",
    )
    check_parent_coverage(
        orders,
        "order_id",
        payments,
        "order_id",
        "orders without payments",
    )
    check_parent_coverage(
        orders,
        "order_id",
        reviews,
        "order_id",
        "orders without reviews",
    )

    print("\nCATEGORY TRANSLATION COVERAGE")
    print("-" * 60)

    check_foreign_key(
        products,
        "product_category_name",
        categories,
        "product_category_name",
        "products.category -> category_translation.category",
    )

    orders_without_items = orders[
        ~orders["order_id"].isin(order_items["order_id"])
    ]
    orders_without_payments = orders[
        ~orders["order_id"].isin(payments["order_id"])
    ]
    orders_without_reviews = orders[
        ~orders["order_id"].isin(reviews["order_id"])
    ]

    print("\nORDERS WITHOUT CHILD RECORDS BY STATUS")
    print("-" * 60)

    print("\nWithout items:")
    print(orders_without_items["order_status"].value_counts())

    print("\nWithout payments:")
    print(orders_without_payments["order_status"].value_counts())

    print("\nWithout reviews:")
    print(orders_without_reviews["order_status"].value_counts())


if __name__ == "__main__":
    main()
    
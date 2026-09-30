from pathlib import Path

import pandas as pd

RAW_DATA_DIR = Path("data/raw")

# Postal prefixes are identifiers, not quantities. Reading them explicitly as
# strings preserves leading zeroes such as 01037 exactly as stored in the CSV.
DTYPE_OVERRIDES = {
    "olist_customers_dataset.csv": {
        "customer_zip_code_prefix": "string",
    },
    "olist_sellers_dataset.csv": {
        "seller_zip_code_prefix": "string",
    },
    "olist_geolocation_dataset.csv": {
        "geolocation_zip_code_prefix": "string",
    },
}

ZIP_PREFIX_COLUMNS = {
    "olist_customers_dataset.csv": "customer_zip_code_prefix",
    "olist_sellers_dataset.csv": "seller_zip_code_prefix",
    "olist_geolocation_dataset.csv": "geolocation_zip_code_prefix",
}


def load_csv(file_path: Path) -> pd.DataFrame:
    """Load a raw CSV without changing source values."""
    return pd.read_csv(
        file_path,
        dtype=DTYPE_OVERRIDES.get(file_path.name),
    )


def audit_zip_prefix(df: pd.DataFrame, file_name: str) -> None:
    """Validate the five-character representation of Olist CEP prefixes."""
    column = ZIP_PREFIX_COLUMNS.get(file_name)
    if column is None:
        return

    values = df[column]
    invalid_mask = values.notna() & ~values.str.fullmatch(r"\d{5}")
    leading_zero_count = values.str.startswith("0", na=False).sum()

    print(f"ZIP-prefix validation ({column}):")
    print(f"  Invalid five-digit values: {int(invalid_mask.sum()):,}")
    print(f"  Values with leading zero: {int(leading_zero_count):,}")

    if invalid_mask.any():
        examples = values.loc[invalid_mask].drop_duplicates().head(10)
        print("  Example invalid values:")
        print(examples.to_string(index=False))


def main() -> None:
    csv_files = sorted(RAW_DATA_DIR.glob("*.csv"))

    print(f"Found {len(csv_files)} CSV files.\n")

    summary = []
    schema_summary = []

    for file_path in csv_files:
        df = load_csv(file_path)

        for column in df.columns:
            schema_summary.append(
                {
                    "file": file_path.name,
                    "column": column,
                    "dtype": str(df[column].dtype),
                    "non_null": df[column].notna().sum(),
                    "null_count": df[column].isna().sum(),
                    "unique_values": df[column].nunique(dropna=True),
                }
            )

        rows = len(df)
        columns = len(df.columns)
        duplicates = df.duplicated().sum()
        missing_cells = df.isna().sum().sum()
        memory_mb = df.memory_usage(deep=True).sum() / (1024**2)

        null_counts = df.isna().sum()
        null_counts = null_counts[null_counts > 0]

        if not null_counts.empty:
            print(f"\nMissing values in {file_path.name}:")
            print(null_counts.to_string())

        print(f"Dataset: {file_path.name}")
        print(f"Rows: {rows:,}")
        print(f"Columns: {columns}")
        print(f"Duplicate rows: {duplicates:,}")
        print(f"Missing cells: {missing_cells:,}")
        print(f"Memory: {memory_mb:.2f} MB")
        audit_zip_prefix(df, file_path.name)
        print("-" * 60)

        summary.append(
            {
                "file": file_path.name,
                "rows": rows,
                "columns": columns,
                "duplicate_rows": duplicates,
                "missing_cells": missing_cells,
                "memory_mb": round(memory_mb, 2),
            }
        )

    summary_df = pd.DataFrame(summary)
    print("\nRAW DATA SUMMARY")
    print(summary_df.to_string(index=False))

    schema_df = pd.DataFrame(schema_summary)
    print("\nSCHEMA SUMMARY")
    print(schema_df.to_string(index=False))


if __name__ == "__main__":
    main()

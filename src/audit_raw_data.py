from pathlib import Path

import pandas as pd


RAW_DATA_DIR = Path("data/raw")


csv_files = sorted(RAW_DATA_DIR.glob("*.csv"))

print(f"Found {len(csv_files)} CSV files.\n")
summary = []
schema_summary = []
for file_path in csv_files:
    df = pd.read_csv(file_path)
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
    memory_mb = df.memory_usage(deep=True).sum() / (1024 ** 2)
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
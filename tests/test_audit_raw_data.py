from pathlib import Path

import pandas as pd

from src.audit_raw_data import audit_zip_prefix, load_csv


def test_load_csv_preserves_leading_zero_zip_prefix(tmp_path: Path) -> None:
    csv_path = tmp_path / "olist_customers_dataset.csv"
    csv_path.write_text(
        "customer_id,customer_zip_code_prefix\n"
        "customer-1,01037\n"
        "customer-2,12345\n",
        encoding="utf-8",
    )

    df = load_csv(csv_path)

    assert str(df["customer_zip_code_prefix"].dtype) == "string"
    assert df["customer_zip_code_prefix"].tolist() == ["01037", "12345"]


def test_audit_zip_prefix_reports_invalid_and_leading_zero_counts(capsys) -> None:
    df = pd.DataFrame(
        {
            "customer_zip_code_prefix": pd.Series(
                ["01037", "12345", "1234", "12A45", pd.NA],
                dtype="string",
            )
        }
    )

    audit_zip_prefix(df, "olist_customers_dataset.csv")

    output = capsys.readouterr().out
    assert "Invalid five-digit values: 2" in output
    assert "Values with leading zero: 1" in output
    assert "1234" in output
    assert "12A45" in output


def test_audit_zip_prefix_ignores_files_without_zip_mapping(capsys) -> None:
    df = pd.DataFrame({"order_id": ["order-1"]})

    audit_zip_prefix(df, "olist_orders_dataset.csv")

    assert capsys.readouterr().out == ""


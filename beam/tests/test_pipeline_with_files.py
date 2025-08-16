import os
import csv
from pathlib import Path
import apache_beam as beam
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.testing.test_pipeline import TestPipeline
from beam.transformations import CleanCustomerData, CleanTransactionData

CUSTOMER_FIELDS = ["customer_id","first_name","last_name","email","signup_date","country"]
TRANSACTION_FIELDS = ["transaction_id","customer_id","transaction_date","amount","currency","product"]

def _read_csv_as_dicts(path, fields):
    rows = []
    with open(path, newline="") as f:
        rdr = csv.reader(f)
        next(rdr, None)  # skip header
        for parts in rdr:
            parts = (parts + [""] * len(fields))[: len(fields)]  # pad/truncate
            rows.append(dict(zip(fields, parts)))
    return rows

def _strip_strings(d):
    return {k: (v.strip() if isinstance(v, str) else v) for k, v in d.items()}

def _normalize_expected_customers(rows):
    out = []
    for r in rows:
        r = _strip_strings(r)
        if "email" in r and isinstance(r["email"], str):
            r["email"] = r["email"].lower()
        out.append(r)
    return out

def _normalize_expected_transactions(rows):
    out = []
    for r in rows:
        r = _strip_strings(r)
        amt = r.get("amount")
        if amt in (None, ""):
            r["amount"] = None
        else:
            try:
                r["amount"] = float(amt)
            except Exception:
                r["amount"] = None
        out.append(r)
    return out

def test_pipeline_with_files():
    # repo root = two levels up from this test file
    repo_root = Path(__file__).resolve().parents[2]

    # Input files live here:
    input_dir = repo_root / "local"
    customers_path = input_dir / "customers.csv"
    transactions_path = input_dir / "transactions.csv"

    # Expected files live here:
    expected_dir = repo_root / "expected_dummy_data_demo"
    expected_customers_path = expected_dir / "expected_customers.csv"
    expected_transactions_path = expected_dir / "expected_transactions.csv"

    # Helpful checks before running Beam
    for p in (customers_path, transactions_path, expected_customers_path, expected_transactions_path):
        assert p.exists(), f"File not found: {p}"

    expected_customers = _normalize_expected_customers(
        _read_csv_as_dicts(str(expected_customers_path), CUSTOMER_FIELDS)
    )
    expected_transactions = _normalize_expected_transactions(
        _read_csv_as_dicts(str(expected_transactions_path), TRANSACTION_FIELDS)
    )

    with TestPipeline() as p:
        customers = (
            p
            | "ReadCustomersFile" >> beam.io.ReadFromText(str(customers_path), skip_header_lines=1)
            | "ParseCustomersFile" >> beam.Map(lambda l: dict(zip(CUSTOMER_FIELDS, next(csv.reader([l])))))
            | "CleanCustomersFile" >> CleanCustomerData()
        )

        transactions = (
            p
            | "ReadTransactionsFile" >> beam.io.ReadFromText(str(transactions_path), skip_header_lines=1)
            | "ParseTransactionsFile" >> beam.Map(lambda l: dict(zip(TRANSACTION_FIELDS, next(csv.reader([l])))))
            | "CleanTransactionsFile" >> CleanTransactionData()
        )

        assert_that(customers, equal_to(expected_customers), label="CheckCustomersFile")
        assert_that(transactions, equal_to(expected_transactions), label="CheckTransactionsFile")

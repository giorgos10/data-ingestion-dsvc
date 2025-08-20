import argparse
import csv

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from beam.schemas import CustomerSchema, TransactionSchema
from beam.transformations import CleanCustomerData, CleanTransactionData, AddMetadata


CUSTOMER_FIELDS = CustomerSchema._fields[:-2]  # drop metadata fields
TRANSACTION_FIELDS = TransactionSchema._fields[:-2]


def _parse_csv_line(line: str):
    return next(csv.reader([line]))  # robust CSV parsing


def _to_dict(fields):
    def _mapper(values):
        return dict(zip(fields, values))
    return _mapper


# function to change the write to bigquery method while running locally as only streaming insert is allowed with direct runner
def _runner_method(options: PipelineOptions):
    runner = (options.view_as(StandardOptions).runner or "").lower()
    if runner == "directrunner":
        return beam.io.WriteToBigQuery.Method.STREAMING_INSERTS
    return beam.io.WriteToBigQuery.Method.FILE_LOADS


# required as streaming insert needs separately passed the bq information
def _split_table_str(table_str: str):
    project, dataset_table = table_str.split(":", 1)
    dataset, table = dataset_table.split(".", 1)
    return project, dataset, table


# generic ingest function to avoid duplicated/redundant code
def _ingest_csv(p, path, fields, label, cleaner):
    """
    Build an ingest branch only if 'path' is provided.
    validate=False ensures globs with zero matches yield an empty PCollection instead of failing.
    """
    if not path:
        return None  # no branch

    return (
        p
        | f"Read{label}CSV" >> beam.io.ReadFromText(path, skip_header_lines=1, validate=False)
        | f"Parse{label}CSV" >> beam.Map(_parse_csv_line)
        | f"{label}ToDict" >> beam.Map(_to_dict(fields))
        | f"Clean{label}" >> cleaner
        | f"Add{label}Metadata" >> beam.ParDo(AddMetadata(path))
    )


def _write_to_bq(pcoll, table_str, method, write_mode, label):
    """Write only if the pcoll exists; otherwise do nothing."""
    if pcoll is None:
        return

    if method == beam.io.WriteToBigQuery.Method.STREAMING_INSERTS:
        # Local run (DirectRunner): split into parts
        proj, ds, tbl = _split_table_str(table_str)
        _ = (
            pcoll
            | f"Write{label}Streaming" >> beam.io.WriteToBigQuery(
                table=tbl,
                dataset=ds,
                project=proj,
                create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                method=method,
            )
        )
    else:
        # Dataflow run (GCS → BigQuery load jobs)
        _ = (
            pcoll
            | f"Write{label}Loads" >> beam.io.WriteToBigQuery(
                table=table_str,
                create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                method=method,
            )
        )


def run_pipeline(
    customers_path,
    transactions_path,
    customer_bq_table,
    transaction_bq_table,
    write_mode="WRITE_APPEND",
    pipeline_args=None,
):
    options = PipelineOptions(pipeline_args, save_main_session=True)
    method = _runner_method(options)

    with beam.Pipeline(options=options) as p:
        customers = _ingest_csv(
            p=p,
            path=customers_path,
            fields=CUSTOMER_FIELDS,
            label="Customers",
            cleaner=CleanCustomerData(),
        )

        transactions = _ingest_csv(
            p=p,
            path=transactions_path,
            fields=TRANSACTION_FIELDS,
            label="Transactions",
            cleaner=CleanTransactionData(),
        )

        _write_to_bq(customers, customer_bq_table, method, write_mode, "Customers")
        _write_to_bq(transactions, transaction_bq_table, method, write_mode, "Transactions")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--customers_path", required=False, help="Path to customers.csv (local or gs://)")
    parser.add_argument("--transactions_path", required=False, help="Path to transactions.csv (local or gs://)")
    parser.add_argument("--customer_bq_table", required=True, help="PROJECT:LANDING_DATASET.customers")
    parser.add_argument("--transaction_bq_table", required=True, help="PROJECT:LANDING_DATASET.transactions")
    parser.add_argument("--write_mode", default="WRITE_APPEND", choices=["WRITE_APPEND"])
    args, pipeline_args = parser.parse_known_args()

    run_pipeline(
        customers_path=args.customers_path,
        transactions_path=args.transactions_path,
        customer_bq_table=args.customer_bq_table,
        transaction_bq_table=args.transaction_bq_table,
        write_mode=args.write_mode,
        pipeline_args=pipeline_args,
    )

import argparse
import csv

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from beam.transformations import CleanCustomerData, CleanTransactionData, AddMetadata


CUSTOMER_FIELDS = ["customer_id", "first_name", "last_name", "email", "signup_date", "country"]
TRANSACTION_FIELDS = ["transaction_id", "customer_id", "transaction_date", "amount", "currency", "product"]


def _parse_csv_line(line: str):
    return next(csv.reader([line]))  # robust CSV parsing


def _to_dict(fields):
    def _mapper(values):
        return dict(zip(fields, values))
    return _mapper


# function to change the write to bigquery method while running locally as only streaming insert is allowed woth direct runner
def _runner_method(options: PipelineOptions):
    runner = (options.view_as(StandardOptions).runner or "").lower()
    if runner == "directrunner":
        return beam.io.WriteToBigQuery.Method.STREAMING_INSERTS
    return beam.io.WriteToBigQuery.Method.FILE_LOADS


def _split_table_str(table_str: str):
    project, dataset_table = table_str.split(":", 1)
    dataset, table = dataset_table.split(".", 1)
    return project, dataset, table


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

        customers = (
            p
            | "ReadCustomersCSV" >> beam.io.ReadFromText(customers_path, skip_header_lines=1)
            | "ParseCustomersCSV" >> beam.Map(_parse_csv_line)
            | "CustomersToDict" >> beam.Map(_to_dict(CUSTOMER_FIELDS))
            | "CleanCustomers" >> CleanCustomerData()
            | "AddCustomerMetadata" >> beam.ParDo(AddMetadata(customers_path))
        )

        transactions = (
            p
            | "ReadTransactionsCSV" >> beam.io.ReadFromText(transactions_path, skip_header_lines=1)
            | "ParseTransactionsCSV" >> beam.Map(_parse_csv_line)
            | "TransactionsToDict" >> beam.Map(_to_dict(TRANSACTION_FIELDS))
            | "CleanTransactions" >> CleanTransactionData()
            | "AddTransactionMetadata" >> beam.ParDo(AddMetadata(transactions_path))
        )

        if method == beam.io.WriteToBigQuery.Method.STREAMING_INSERTS:
            # Local run (DirectRunner)
            proj_c, ds_c, tbl_c = _split_table_str(customer_bq_table)
            proj_t, ds_t, tbl_t = _split_table_str(transaction_bq_table)

            _ = (
                customers
                | "WriteCustomersStreaming" >> beam.io.WriteToBigQuery(
                    table=tbl_c,
                    dataset=ds_c,
                    project=proj_c,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                    method=method,
                )
            )

            _ = (
                transactions
                | "WriteTransactionsStreaming" >> beam.io.WriteToBigQuery(
                    table=tbl_t,
                    dataset=ds_t,
                    project=proj_t,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                    method=method,
                )
            )

        else:
            # Dataflow run (GCS → BigQuery load jobs)
            _ = (
                customers
                | "WriteCustomersLoads" >> beam.io.WriteToBigQuery(
                    table=customer_bq_table,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                    method=method,
                )
            )

            _ = (
                transactions
                | "WriteTransactionsLoads" >> beam.io.WriteToBigQuery(
                    table=transaction_bq_table,
                    create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
                    write_disposition=getattr(beam.io.BigQueryDisposition, write_mode),
                    method=method,
                )
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--customers_path", required=True, help="Path to customers.csv (local or gs://)")
    parser.add_argument("--transactions_path", required=True, help="Path to transactions.csv (local or gs://)")
    parser.add_argument("--customer_bq_table", required=True, help="PROJECT:DATASET.customers")
    parser.add_argument("--transaction_bq_table", required=True, help="PROJECT:DATASET.transactions")
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

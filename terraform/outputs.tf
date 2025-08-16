output "dataflow_service_account" {
  value = google_service_account.dataflow_sa.email
}

output "bucket_url" {
  value = "gs://${google_storage_bucket.raw_data_landing_bucket.name}"
}

# Landing dataset
output "landing_dataset_id" {
  value = google_bigquery_dataset.file_ingestion_landing.dataset_id
}

# Curated dataset
output "curated_dataset_id" {
  value = google_bigquery_dataset.cust_txn_insight.dataset_id
}

# Landing tables
output "customers_table" {
  value = "${var.project_id}.${google_bigquery_dataset.file_ingestion_landing.dataset_id}.${google_bigquery_table.customers.table_id}"
}

output "transactions_table" {
  value = "${var.project_id}.${google_bigquery_dataset.file_ingestion_landing.dataset_id}.${google_bigquery_table.transactions.table_id}"
}

# Dataflow staging bucket
output "dataflow_bucket" {
  value = "gs://${google_storage_bucket.dataflow_bucket.name}"
}

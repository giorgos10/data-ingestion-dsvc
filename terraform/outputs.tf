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
  value = google_bigquery_dataset.cust_txn_insights.dataset_id
}

# Landing tables
output "landing_customers_table" {
  value = "${var.project_id}.${google_bigquery_dataset.file_ingestion_landing.dataset_id}.${google_bigquery_table.landing_customers.table_id}"
}

output "landing_transactions_table" {
  value = "${var.project_id}.${google_bigquery_dataset.file_ingestion_landing.dataset_id}.${google_bigquery_table.landing_transactions.table_id}"
}

# Curated tables
output "curated_customers_table" {
  value = "${var.project_id}.${google_bigquery_dataset.cust_txn_insights.dataset_id}.${google_bigquery_table.curated_customers.table_id}"
}

output "curated_transactions_table" {
  value = "${var.project_id}.${google_bigquery_dataset.cust_txn_insights.dataset_id}.${google_bigquery_table.curated_transactions.table_id}"
}

# Dataflow staging bucket
output "dataflow_bucket" {
  value = "gs://${google_storage_bucket.dataflow_bucket.name}"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------
# GCS Bucket for raw data
# -----------------------
resource "google_storage_bucket" "raw_data_landing_bucket" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }
}

# -----------------------
# BigQuery Datasets
# -----------------------

# Landing dataset (Dataflow writes here)
resource "google_bigquery_dataset" "file_ingestion_landing" {
  dataset_id                 = var.landing_dataset_id
  location                   = var.region
  delete_contents_on_destroy = true
}

# Curated dataset (SQL transformations land here)
resource "google_bigquery_dataset" "cust_txn_insights" {
  dataset_id                 = var.curated_dataset_id
  location                   = var.region
  delete_contents_on_destroy = true

  default_table_expiration_ms = 2592000000 # 30 days
}

# -----------------------
# Dataflow Service Account
# -----------------------
resource "google_service_account" "dataflow_sa" {
  account_id   = "dataflow-job-runner"
  display_name = "Dataflow Job Runner"
}

# IAM bindings for Dataflow SA
resource "google_project_iam_member" "dataflow_worker_role" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "bigquery_access" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "gcs_access" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# -----------------------
# BigQuery Tables in landing dataset
# -----------------------

# Customers Table (landing)
resource "google_bigquery_table" "landing_customers" {
  dataset_id = google_bigquery_dataset.file_ingestion_landing.dataset_id
  table_id   = "customers"
  deletion_protection  = false

  schema = jsonencode([
    { name = "customer_id",   type = "STRING",  mode = "REQUIRED" },
    { name = "first_name",    type = "STRING",  mode = "NULLABLE" },
    { name = "last_name",     type = "STRING",  mode = "NULLABLE" },
    { name = "email",         type = "STRING",  mode = "NULLABLE" },
    { name = "signup_date",   type = "STRING",  mode = "NULLABLE" },
    { name = "country",       type = "STRING",  mode = "NULLABLE" },
    { name = "load_tsp",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "source_file",   type = "STRING",  mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "load_tsp"
  }

  clustering = ["customer_id"]
}

# Transactions Table (landing)
resource "google_bigquery_table" "landing_transactions" {
  dataset_id = google_bigquery_dataset.file_ingestion_landing.dataset_id
  table_id   = "transactions"
  deletion_protection  = false

  schema = jsonencode([
    { name = "transaction_id",   type = "STRING",  mode = "REQUIRED" },
    { name = "customer_id",      type = "STRING",  mode = "NULLABLE" },
    { name = "transaction_date", type = "STRING",  mode = "NULLABLE" },
    { name = "amount",           type = "FLOAT",   mode = "NULLABLE" },
    { name = "currency",         type = "STRING",  mode = "NULLABLE" },
    { name = "product",          type = "STRING",  mode = "NULLABLE" },
    { name = "load_tsp",         type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "source_file",      type = "STRING",  mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "load_tsp"
  }

  clustering = ["transaction_id"]
}

# Curated CUSTOMERS
resource "google_bigquery_table" "curated_customers" {
  dataset_id = google_bigquery_dataset.cust_txn_insights.dataset_id
  table_id   = "customers"

  schema = jsonencode([
    { name = "customer_id",    type = "STRING",    mode = "REQUIRED" },
    { name = "first_name",     type = "STRING",    mode = "NULLABLE" },
    { name = "last_name",      type = "STRING",    mode = "NULLABLE" },
    { name = "email",          type = "STRING",    mode = "NULLABLE" },
    { name = "signup_date",    type = "DATE",      mode = "NULLABLE" },
    { name = "country",        type = "STRING",    mode = "NULLABLE" },
    { name = "load_tsp",       type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "file_name",      type = "STRING",    mode = "NULLABLE" },
    { name = "rows_diff_hash", type = "STRING",    mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "load_tsp"
  }

  clustering = ["customer_id"]

  deletion_protection = false
}

# Curated TRANSACTIONS
resource "google_bigquery_table" "curated_transactions" {
  dataset_id = google_bigquery_dataset.cust_txn_insights.dataset_id
  table_id   = "transactions"

  schema = jsonencode([
    { name = "transaction_id",  type = "STRING",    mode = "REQUIRED" },
    { name = "customer_id",     type = "STRING",    mode = "NULLABLE" },
    { name = "transaction_date",type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "amount",          type = "NUMERIC",   mode = "NULLABLE" },
    { name = "currency",        type = "STRING",    mode = "NULLABLE" },
    { name = "product",         type = "STRING",    mode = "NULLABLE" },
    { name = "load_tsp",        type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "file_name",       type = "STRING",    mode = "NULLABLE" },
    { name = "rows_diff_hash",  type = "STRING",    mode = "REQUIRED" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "transaction_date"
  }

  clustering = ["customer_id"]

  deletion_protection = false
}

# -----------------------
# Dataflow Staging Bucket
# -----------------------
resource "google_storage_bucket" "dataflow_bucket" {
  name                        = var.dataflow_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

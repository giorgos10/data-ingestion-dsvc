variable "project_id" {
  description = "The GCP project ID for the demo"
  type        = string
}

variable "region" {
  description = "Region for resources"
  type        = string
  default     = "europe-west1"
}

variable "bucket_name" {
  description = "Globally unique GCS bucket name"
  type        = string
}

variable "curated_dataset_id" {
  description = "BigQuery dataset ID for the demo curated layer"
  type        = string
  default     = "cust_txn_insights"
}

variable "landing_dataset_id" {
  description = "BigQuery dataset ID for the demo landing layer"
  type        = string
  default     = "file_ingestion_landing"
}

variable "dataflow_bucket_name" {
  type        = string
  description = "GCS bucket for Dataflow temp/staging"
}

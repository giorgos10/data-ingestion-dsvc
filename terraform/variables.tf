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

variable "dataset_id" {
  description = "BigQuery dataset ID for the demo curated layer"
  type        = string
  default     = "cust_txn_insights"
}

variable "dataflow_bucket_name" {
  type        = string
  description = "GCS bucket for Dataflow temp/staging"
}

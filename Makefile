# =========================
# Environment selection
# =========================
ENV ?= dev
ifneq (,$(wildcard env/.env.$(ENV)))
  include env/.env.$(ENV)
  export $(shell sed 's/=.*//' env/.env.$(ENV))
else
  $(error Environment file env/.env.$(ENV) not found)
endif

# =========================
# Python / venv
# =========================
PYTHON := python3.11
VENV   := py3
ACT    := . $(VENV)/bin/activate

# =========================
# Path normalization
#  - If local path -> make absolute
#  - If gs://...   -> leave as-is
# =========================
ifneq ($(findstring gs://,$(CUSTOMERS_FILE)),gs://)
  CUSTOMERS_ARG := $(abspath $(CUSTOMERS_FILE))
else
  CUSTOMERS_ARG := $(CUSTOMERS_FILE)
endif

ifneq ($(findstring gs://,$(TRANSACTIONS_FILE)),gs://)
  TRANSACTIONS_ARG := $(abspath $(TRANSACTIONS_FILE))
else
  TRANSACTIONS_ARG := $(TRANSACTIONS_FILE)
endif

# Local temp dir for DirectRunner
LOCAL_TMP := $(abspath ./tmp_dataflow)

# =========================
# Targets
# =========================
.PHONY: help venv install test print-vars \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        truncate-local run-local run-dataflow \
        curate-customers curate-transactions \
        create-analytics delete-analytics \
        view-monthly view-avg-monthly view-ltv view-top5 \
        clean

help:
	@echo "make install                         # create venv + install deps"
	@echo "make test                            # run pytest"
	@echo "make run-local ENV=dev               # run pipeline locally (DirectRunner)"
	@echo "make run-dataflow ENV=prod           # run on Dataflow (DataflowRunner)"
	@echo "make print-vars ENV=dev              # debug resolved vars and paths"
	@echo "make truncate-local ENV=dev          # truncate tables for local runs"
	@echo "make curate-customers                # move and dedupe customers from landing -> curated"
	@echo "make curate-transactions             # move and dedupe transactions from landing -> curated"
	@echo "make create-analytics                # create analytics dataset (BI views)"
	@echo "make delete-analytics                # delete analytics dataset and its contents"
	@echo "make view-monthly                    # create/replace customer_monthly_spend view"
	@echo "make view-avg-monthly                # create/replace avg_monthly_totals view"
	@echo "make view-ltv                        # create/replace customer_ltv view"
	@echo "make view-top5                       # create/replace top_5pct_customers view"
	@echo "make terraform-init                  # terraform init in ./terraform"
	@echo "make terraform-plan                  # terraform plan with env tfvars"
	@echo "make terraform-apply                 # terraform apply"
	@echo "make terraform-destroy               # terraform destroy"
	@echo "make clean                           # remove venv, tmp_dataflow"

venv:
	@which $(PYTHON) >/dev/null || (echo "$(PYTHON) not found. Install with: brew install python@3.11" && exit 1)
	@test -d $(VENV) || $(PYTHON) -m venv $(VENV)
	@echo "Virtualenv ready at $(VENV)"

install: venv
	@$(ACT); pip install -U pip
	@$(ACT); pip install -r requirements.txt
	@$(ACT); pip install -e .

test:
	@$(ACT); PYTHONPATH=. pytest -vv

print-vars:
	@echo "ENV                = $(ENV)"
	@echo "PROJECT            = $(PROJECT)"
	@echo "REGION             = $(REGION)"
	@echo "LANDING_DATASET    = $(LANDING_DATASET)"
	@echo "CURATED_DATASET    = $(CURATED_DATASET)"
	@echo "CUSTOMERS_LANDING_TABLE    = $(CUSTOMERS_LANDING_TABLE)"
	@echo "TRANSACTIONS_LANDING_TABLE = $(TRANSACTIONS_LANDING_TABLE)"
	@echo "CUSTOMERS_FILE = $(CUSTOMERS_FILE)"
	@echo "TRANSACTIONS_FILE = $(TRANSACTIONS_FILE)"
	@echo "RAW_BUCKET         = $(RAW_BUCKET)"
	@echo "DF_BUCKET          = $(DF_BUCKET)"
	@echo "VENV               = $(VENV)"
	@echo "LOCAL_TMP          = $(LOCAL_TMP)"

# =========================
# Terraform targets
# =========================
terraform-init:
	terraform -chdir=terraform init

terraform-plan:
	terraform -chdir=terraform plan -var-file=../terraform/gcp.tfvars

terraform-apply:
	terraform -chdir=terraform apply -var-file=../terraform/gcp.tfvars

terraform-destroy:
	terraform -chdir=terraform destroy -var-file=../terraform/gcp.tfvars

# =========================
# Local run (DirectRunner)
# =========================
truncate-local:
	@which bq >/dev/null || (echo "❌ gcloud SDK (bq) not found"; exit 1)
	@echo "Truncating $(CUSTOMERS_LANDING_TABLE) and $(TRANSACTIONS_LANDING_TABLE) in $(PROJECT)..."
	@bq --project_id=$(PROJECT) query --nouse_legacy_sql 'TRUNCATE TABLE `$(CUSTOMERS_LANDING_TABLE)`'
	@bq --project_id=$(PROJECT) query --nouse_legacy_sql 'TRUNCATE TABLE `$(TRANSACTIONS_LANDING_TABLE)`'

run-local:
	@mkdir -p $(LOCAL_TMP)
	@$(ACT); PYTHONPATH=. python -m beam.pipeline \
	  --customers_path "$(CUSTOMERS_ARG)" \
	  --transactions_path "$(TRANSACTIONS_ARG)" \
	  --customer_bq_table "$(CUSTOMERS_LANDING_TABLE)" \
	  --transaction_bq_table "$(TRANSACTIONS_LANDING_TABLE)" \
	  --write_mode WRITE_APPEND \
	  --runner DirectRunner \
	  --project "$(PROJECT)" \
	  --region "$(REGION)" \
	  --temp_location "$(LOCAL_TMP)"

# =========================
# Dataflow run
# =========================
run-dataflow:
	@if [ -z "$(DF_BUCKET)" ]; then echo "❌ DF_BUCKET not set in .env.$(ENV)"; exit 1; fi
	@$(ACT); PYTHONPATH=. python -m beam.pipeline \
	  --customers_path "gs://$(RAW_BUCKET)/$(CUSTOMERS_FILE)" \
	  --transactions_path "gs://$(RAW_BUCKET)/$(TRANSACTIONS_FILE)" \
	  --customer_bq_table "$(CUSTOMERS_LANDING_TABLE)" \
	  --transaction_bq_table "$(TRANSACTIONS_LANDING_TABLE)" \
	  --write_mode WRITE_APPEND \
	  --runner DataflowRunner \
	  --project "$(PROJECT)" \
	  --region "$(REGION)" \
	  --temp_location "gs://$(DF_BUCKET)/temp" \
	  --staging_location "gs://$(DF_BUCKET)/staging" \
	  --setup_file ./setup.py \
	  --job_name load-cust-tx-$(ENV)-$(shell date +%Y%m%d-%H%M%S)

# =========================
# Curate (Landing -> Curated)
# =========================
curate-customers:
	@sed \
	  -e "s/{{LANDING_PROJECT}}/$(PROJECT)/g" \
	  -e "s/{{LANDING_DATASET}}/$(LANDING_DATASET)/g" \
	  -e "s/{{CURATED_PROJECT}}/$(PROJECT)/g" \
	  -e "s/{{CURATED_DATASET}}/$(CURATED_DATASET)/g" \
	  sql/curate_customers.tpl.sql \
	| bq --project_id=$(PROJECT) query --nouse_legacy_sql

curate-transactions:
	@sed \
	  -e "s/{{LANDING_PROJECT}}/$(PROJECT)/g" \
	  -e "s/{{LANDING_DATASET}}/$(LANDING_DATASET)/g" \
	  -e "s/{{CURATED_PROJECT}}/$(PROJECT)/g" \
	  -e "s/{{CURATED_DATASET}}/$(CURATED_DATASET)/g" \
	  sql/curate_transactions.tpl.sql \
	| bq --project_id=$(PROJECT) query --nouse_legacy_sql

# =========================
# Analytics Views
# =========================
create-analytics:
	@bq --project_id=$(PROJECT) mk -d --location=$(REGION) $(ANALYTICS_DATASET) || true

SED_FLAGS = \
  -e 's|{{CURATED_PROJECT}}|$(PROJECT)|g' \
  -e 's|{{CURATED_DATASET}}|$(CURATED_DATASET)|g' \
  -e 's|{{ANALYTICS_DATASET}}|$(ANALYTICS_DATASET)|g'

view-monthly:
	@sed $(SED_FLAGS) sql/analytics/customer_monthly_spend.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

view-avg-monthly:
	@sed $(SED_FLAGS) sql/analytics/avg_monthly_totals.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

view-ltv:
	@sed $(SED_FLAGS) sql/analytics/customer_ltv.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

view-top5:
	@sed $(SED_FLAGS) sql/analytics/top_5pct_customers.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

# =========================
# Clean up
# =========================
delete-analytics:
	@echo "Deleting dataset $(ANALYTICS_DATASET) in project $(PROJECT)..."
	@bq --project_id=$(PROJECT) rm -r -f -d $(ANALYTICS_DATASET) || true

clean:
	rm -rf $(VENV) $(LOCAL_TMP)

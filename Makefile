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
.PHONY: help venv install test print-vars truncate-local run-local run-dataflow clean

help:
	@echo "make install ENV=dev        # create venv + install deps"
	@echo "make test ENV=dev           # run pytest"
	@echo "make run-local ENV=dev      # run pipeline locally (DirectRunner)"
	@echo "make run-dataflow ENV=prod  # run on Dataflow (DataflowRunner)"
	@echo "make print-vars ENV=dev     # debug resolved vars and paths"
	@echo "make truncate-local ENV=dev # truncate tables for local runs"
	@echo "make clean                  # remove venv and tmp_dataflow"

venv:
	@which $(PYTHON) >/dev/null || (echo "$(PYTHON) not found. Install with: brew install python@3.11" && exit 1)
	@test -d $(VENV) || $(PYTHON) -m venv $(VENV)
	@echo "Virtualenv ready at $(VENV)"

install: venv
	@$(ACT); pip install -U pip
	@$(ACT); pip install "apache-beam[gcp]" pytest python-dotenv
	@$(ACT); pip install -e .   # install our local package (beam/)

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
	@echo "CUSTOMERS_FILE(raw)= $(CUSTOMERS_FILE)"
	@echo "TRANSACTIONS_FILE(raw)= $(TRANSACTIONS_FILE)"
	@echo "CUSTOMERS_ARG(resolved)= $(CUSTOMERS_ARG)"
	@echo "TRANSACTIONS_ARG(resolved)= $(TRANSACTIONS_ARG)"
	@echo "RAW_BUCKET         = $(RAW_BUCKET)"
	@echo "DF_BUCKET          = $(DF_BUCKET)"
	@echo "VENV               = $(VENV)"
	@echo "LOCAL_TMP          = $(LOCAL_TMP)"

truncate-local:
	@which bq >/dev/null || (echo "❌ gcloud SDK (bq) not found"; exit 1)
	@echo "Truncating $(CUSTOMERS_LANDING_TABLE) and $(TRANSACTIONS_LANDING_TABLE) in $(PROJECT)..."
	@bq --project_id=$(PROJECT) query --nouse_legacy_sql \
	  'TRUNCATE TABLE `$(CUSTOMERS_LANDING_TABLE)`'
	@bq --project_id=$(PROJECT) query --nouse_legacy_sql \
	  'TRUNCATE TABLE `$(TRANSACTIONS_LANDING_TABLE)`'

# Local run (DirectRunner)
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

# Dataflow run
run-dataflow:
	@if [ -z "$(DF_BUCKET)" ]; then echo "❌ DF_BUCKET not set in .env.$(ENV)"; exit 1; fi
	@$(ACT); PYTHONPATH=. python -m beam.pipeline \
	  --customers_path "gs://$(RAW_BUCKET)/customers.csv" \
	  --transactions_path "gs://$(RAW_BUCKET)/transactions.csv" \
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

# move the data from stg dataset/table to the curated one
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

# Data analysis space for a team i.e. BI
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

view-avg-active-months:
	@sed $(SED_FLAGS) sql/analytics/avg_active_months_spend.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

view-ltv:
	@sed $(SED_FLAGS) sql/analytics/customer_ltv.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

view-top5:
	@sed $(SED_FLAGS) sql/analytics/top_5pct_customers.tpl.sql \
	| bq --project_id="$(PROJECT)" query --use_legacy_sql=false

clean:
	rm -rf $(VENV) $(LOCAL_TMP)

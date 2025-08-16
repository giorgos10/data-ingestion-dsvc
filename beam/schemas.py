from typing import NamedTuple

class CustomerSchema(NamedTuple):
    customer_id: str
    first_name: str
    last_name: str
    email: str
    signup_date: str
    country: str
    # metadata (added by pipeline, not in CSV)
    load_tsp: str
    source_file: str

class TransactionSchema(NamedTuple):
    transaction_id: str
    customer_id: str
    transaction_date: str
    amount: str
    currency: str
    product: str
    # metadata (added by pipeline, not in CSV)
    load_tsp: str
    source_file: str

import apache_beam as beam
import os
from datetime import datetime


class CleanCustomerData(beam.PTransform):
    def expand(self, pcoll):
        return (
            pcoll
            | "StripCustomerFields" >> beam.Map(
                lambda x: {k: v.strip() if isinstance(v, str) else v for k, v in x.items()}
            )
            | "LowercaseEmail" >> beam.Map(
                lambda x: {**x, "email": x.get("email", "").lower()}
            )
        )


class CleanTransactionData(beam.PTransform):
    def expand(self, pcoll):
        def cast_amount(x):
            amt = x.get("amount")
            try:
                amt = float(amt) if amt not in (None, "") else None
            except Exception:
                amt = None
            return {**x, "amount": amt}

        return (
            pcoll
            | "StripTransactionFields" >> beam.Map(
                lambda x: {k: v.strip() if isinstance(v, str) else v for k, v in x.items()}
            )
            | "CastAmountToFloat" >> beam.Map(cast_amount)
        )


class AddMetadata(beam.DoFn):
    """Adds load_tsp (UTC ISO 8601) and source_file (basename) to each element."""
    def __init__(self, source_path: str):
        self.source_path = source_path

    def process(self, element: dict):
        element["load_tsp"] = datetime.utcnow().isoformat(timespec="seconds") + "Z"
        element["source_file"] = os.path.basename(self.source_path.rstrip("/"))
        yield element

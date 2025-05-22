import requests
import pandas as pd
from datetime import datetime, timedelta

def fetch_memory_usage(prom_url, metric, duration="1h", step="15s"):
    end = datetime.utcnow()
    start = end - timedelta(hours=1)
    query_range = {
        "query": metric,
        "start": start.isoformat() + "Z",
        "end": end.isoformat() + "Z",
        "step": step
    }
    response = requests.get(f"{prom_url}/api/v1/query_range", params=query_range)
    results = response.json()["data"]["result"]

    if not results:
        return pd.DataFrame()

    values = results[0]["values"]
    df = pd.DataFrame(values, columns=["timestamp", "value"])
    df["timestamp"] = pd.to_datetime(df["timestamp"], unit='s')
    df["value"] = df["value"].astype(float)
    return df.set_index("timestamp")

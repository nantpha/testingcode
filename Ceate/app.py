from fastapi import FastAPI
from prometheus_client import fetch_memory_usage
from summarize import analyze_memory

app = FastAPI()

@app.get("/train")
def train_model():
    # Call your training logic
    return {"status": "Model trained"}

@app.get("/summary")
def summary():
    df = fetch_memory_usage("http://localhost:9090", "jvm_memory_used_bytes")
    peak, low = analyze_memory(df)
    return {
        "peak": peak.tail(3).to_dict(),
        "low": low.head(3).to_dict()
    }

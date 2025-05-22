def analyze_memory(df):
    peak = df[df['value'] > df['value'].quantile(0.95)]
    low = df[df['value'] < df['value'].quantile(0.05)]
    return peak, low

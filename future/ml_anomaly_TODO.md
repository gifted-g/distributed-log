# ML Anomaly Detection – TODO

- Python service subscribes to new log lines and maintains baseline rates per host/IP/user.
- Use EWMA / STL for seasonality, or scikit-learn IsolationForest for spikes.
- Output anomalies back into the same alerting channel (Slack/email).

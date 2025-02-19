#!/bin/bash

# Start Prometheus metrics exporter
python3 - <<'EOF'
from prometheus_client import start_http_server, Gauge
import time
import subprocess
import json

start_http_server(8000)

latency = Gauge('vegeta_latency_ms', 'Average latency')
rps = Gauge('vegeta_rps', 'Requests per second')
errors = Gauge('vegeta_errors', 'Error count')

while True:
    try:
        result = subprocess.run(
            ["vegeta", "report", "-type=json", "results.bin"],
            capture_output=True,
            text=True
        )
        data = json.loads(result.stdout)
        
        latency.set(data['latencies']['mean'] / 1e6)  # Convert ns to ms
        rps.set(data['rate'])
        errors.set(sum(v for k,v in data['status_codes'].items() if k != "200"))
        
    except Exception as e:
        print(f"Error collecting metrics: {e}")
    
    time.sleep(15)
EOF

# Main load test
vegeta attack \
  -duration=15m \
  -rate=100/300s:600 \
  -targets=vegeta-targets.txt \
  -output results.bin

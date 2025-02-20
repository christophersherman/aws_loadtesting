#!/bin/bash
# Metrics setup with additional system monitoring
python3 - <<'EOF' &
from prometheus_client import start_http_server, Gauge, Histogram
import time, subprocess, json, psutil

start_http_server(8000)

# Application metrics
latency = Gauge('vegeta_latency_ms', 'Average latency', ['percentile'])
rps = Gauge('vegeta_rps', 'Requests per second')
errors = Gauge('vegeta_errors', 'Error count', ['status'])
req_count = Counter('vegeta_requests_total', 'Total requests')
status_codes = Gauge('vegeta_status_codes', 'Status code count', ['code'])

# System metrics
cpu_usage = Gauge('system_cpu_usage', 'CPU usage %')
mem_usage = Gauge('system_mem_usage', 'Memory usage %')

def collect_metrics():
    try:
        result = subprocess.run(
            ["vegeta", "report", "-type=json", "results.bin"],
            capture_output=True, text=True
        )
        data = json.loads(result.stdout)
        
        # Latency percentiles
        for p in ['50', '90', '95', '99']:
            latency.labels(percentile=p).set(data['latencies'][f'{p}th'] / 1e6)
        
        # Status codes
        for code, count in data['status_codes'].items():
            status_codes.labels(code=code).set(count)
            if code != "200":
                errors.labels(status=code).inc(count)

        rps.set(data['rate'])
        req_count.inc(data['requests'])

        # System metrics
        cpu_usage.set(psutil.cpu_percent())
        mem_usage.set(psutil.virtual_memory().percent)

    except Exception as e:
        print(f"Error collecting metrics: {e}")

while True:
    collect_metrics()
    time.sleep(5)  # Higher resolution for presentations
EOF

# System metrics exporter (requires node_exporter)
# Uncomment if node_exporter is not running
# ./node_exporter &

# Phase-based load test (adaptive-rate)
PHASES=(
    # Warm-up (gradual load increase)
    "1m:50-100" 
    # Ramp-up (stress test)
    "3m:100-500"
    # Sustained peak load
    "5m:500" 
    # Soak test (prolonged realistic load)
    "10m:300"
    # Recovery test (sudden drop)
    "2m:50"
)

for phase in "${PHASES[@]}"; do
    duration=$(echo $phase | cut -d':' -f1)
    rate=$(echo $phase | cut -d':' -f2)
    
    echo "🚦 Starting phase: $duration at $rate req/s"
    vegeta attack \
        -duration=$duration \
        -rate="$rate" \
        -targets=vegeta-targets.txt \
        -output results.bin \
        >> vegeta.log 2>&1
    
    vegeta report results.bin > reports/$(date +%s).txt
    echo "🧪 Phase completed. Cooling down for 30s..."
    sleep 30
done

# Generate final report
vegeta report -inputs results.bin -reporter plot > plot.html
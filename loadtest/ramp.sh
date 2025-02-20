#!/bin/bash
# Start Prometheus metrics exporter properly
python3 - <<'EOF' &
from prometheus_client import start_http_server, Gauge, Histogram, Counter
import time, subprocess, json, psutil

start_http_server(8000)

# Metrics setup
latency = Gauge('vegeta_latency_ms', 'Average latency')
rps = Gauge('vegeta_rps', 'Requests per second')
errors = Gauge('vegeta_errors', 'Error count')
status_codes = Gauge('vegeta_status_codes', 'Status code count', ['code'])
req_count = Counter('vegeta_requests_total', 'Total requests')
current_phase = Gauge('vegeta_current_phase', 'Current load test phase', ['phase_name'])
latency_hist = Histogram('vegeta_latency_hist_ms', 'Request latency histogram', buckets=[100, 200, 500, 1000, 2000])
cpu_usage = Gauge('system_cpu_usage', 'CPU usage %')
mem_usage = Gauge('system_mem_usage', 'Memory usage %')

def collect_metrics():
    try:
        report = subprocess.run(
            ["vegeta", "report", "-type=json", "results.bin"],
            capture_output=True, text=True
        )
        data = json.loads(report.stdout)
        
        for latency_value in data.get('latencies', {}).get('values', []):
            latency_hist.observe(latency_value / 1e6)
        
        # Clear previous status codes
        status_codes.clear()
        for code, count in data.get('status_codes', {}).items():
            status_codes.labels(code=code).set(count)

        latency.set(data['latencies']['mean'] / 1e6)
        rps.set(data['rate'])
        errors.set(sum(v for k,v in data['status_codes'].items() if k != "200"))
        req_count.inc(data['requests'])
        
        cpu_usage.set(psutil.cpu_percent())
        mem_usage.set(psutil.virtual_memory().percent)

    except Exception as e:
        print(f"Error collecting metrics: {e}")

while True:
    collect_metrics()
    time.sleep(5)
EOF

# Phase-based load test (fixed shell implementation)
PHASES=(
    "1m:50-100:warmup"
    "3m:100-500:rampup"
    "5m:500:peak"
    "10m:300:soak"
    "2m:50:recovery"
)

for phase in "${PHASES[@]}"; do
    IFS=':' read -r duration rate phase_name <<< "$phase"
    echo "🚦 Starting phase: $phase_name ($duration at $rate req/s)"
    
    # Log phase start to metrics (using simple file marking)
    echo "$phase_name" > current_phase.txt
    
    vegeta attack \
        -duration="$duration" \
        -rate="$rate" \
        -targets=vegeta-targets.txt \
        -output results.bin \
        >> vegeta.log 2>&1
    
    vegeta report results.bin > "reports/$(date +%s).txt"
    echo "🧪 Phase completed. Cooling down for 30s..."
    sleep 30
done

vegeta report -inputs results.bin -reporter plot > plot.html

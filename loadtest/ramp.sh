#!/bin/bash
# CHANGED: Added Counter import and fixed label handling
from prometheus_client import start_http_server, Gauge, Histogram, Counter

# CHANGED: Added buckets for histogram
latency_hist = Histogram('vegeta_latency_hist_ms', 'Request latency histogram', buckets=[100, 200, 500, 1000, 2000])

# CHANGED: Fixed Counter implementation
req_count = Counter('vegeta_requests_total', 'Total requests')

def collect_metrics():
    try:
        # ADDED: Track duration of attack
        result = subprocess.run(
            ["vegeta", "attack", "-duration=1s", "-rate=1", "-targets=vegeta-targets.txt"],
            capture_output=True, text=True
        )
        
        # ADDED: Parse results properly
        report = subprocess.run(
            ["vegeta", "report", "-type=json", "results.bin"],
            capture_output=True, text=True
        )
        data = json.loads(report.stdout)
        
        # CHANGED: Record histogram values
        for latency in data['latencies']['values']:
            latency_hist.observe(latency / 1e6)
        
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

current_phase = Gauge('vegeta_current_phase', 'Current load test phase', ['phase_name'])

for phase in "${PHASES[@]}"; do
    phase_name=$(echo $phase | cut -d':' -f2)
    current_phase.labels(phase_name=phase_name).set(1)
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
    current_phase.labels(phase_name=phase_name).set(0)
    sleep 30
done

# Generate final report
vegeta report -inputs results.bin -reporter plot > plot.html
#!/usr/bin/env bash
# Deception Lab — Threat Intelligence Simulator
# Appends a mock attack log with a known malicious public IP to trigger AbuseIPDB & AlienVault OTX lookups.

# Default to a known active scanner / Tor exit node IP (e.g., 185.220.101.4)
MALICIOUS_IP="${1:-185.220.101.4}"

echo "[*] Simulating attack from public IP: $MALICIOUS_IP"

# Generate mock OpenCanary log entry
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S.000000")
MOCK_LOG="{\"dst_host\": \"192.168.100.20\", \"dst_port\": 21, \"local_time\": \"$TIMESTAMP\", \"logtype\": 1001, \"nodeid\": \"corp-fileserver\", \"src_host\": \"$MALICIOUS_IP\", \"src_port\": 43210}"

# Append to OpenCanary log file
echo "$MOCK_LOG" | sudo tee -a /var/log/opencanary.log > /dev/null

echo "[+] Log appended to /var/log/opencanary.log"
echo "[*] Filebeat will now ship this log to Logstash."
echo "[*] Check Kibana in a few seconds to see the IP mapped and threat intelligence scores loaded!"

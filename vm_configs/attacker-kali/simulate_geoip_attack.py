#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
#  Deception Lab — GeoIP Attack Simulator Script
#  Path: vm_configs/attacker-kali/simulate_geoip_attack.py
#  Run on Kali Linux VM with sudo: sudo python3 simulate_geoip_attack.py
# ─────────────────────────────────────────────────────────────────────────────

import time
import random
from scapy.all import IP, TCP, send

# Target: Deception Hub Mesh IP
TARGET_IP = "192.168.100.20"

# Target Ports corresponding to honeypots (FTP: 21, HTTP: 80, MSSQL: 1433)
TARGET_PORTS = [21, 80, 1433]

# A dictionary of well-known public IPs from different countries
GEO_IPS = {
    "8.8.8.8": "United States (Google)",
    "1.1.1.1": "Australia (Cloudflare)",
    "77.88.8.8": "Russia (Yandex)",
    "114.114.114.114": "China (114DNS)",
    "195.201.201.201": "Germany (DNS.WATCH)",
    "103.20.124.1": "India (Tata Communications)",
    "200.221.2.45": "Brazil (UOL)",
    "196.25.1.1": "South Africa (Telkom)",
}

print("========================================================")
print(" Starting GeoIP Attack Simulation (TCP SYN Scan) ")
print("========================================================")
print(f"Targeting Deception Hub at {TARGET_IP}...")
print("Sending packets with spoofed public source IPs to populate Kibana map...\n")

for ip, country in GEO_IPS.items():
    # Pick a random port from our list
    port = random.choice(TARGET_PORTS)
    
    # Generate TCP SYN packet
    # Scapy builds it layer by layer: IP layer (spoofed src) / TCP layer (SYN flag "S")
    packet = IP(src=ip, dst=TARGET_IP) / TCP(sport=random.randint(1024, 65535), dport=port, flags="S")
    
    # Send packet
    send(packet, verbose=False)
    print(f"[+] Spoofed attack sent from {ip:<16} ({country:<30}) -> Target Port {port}")
    time.sleep(0.5)

print("\n========================================================")
print(" Simulation complete. Check your Kibana 'Attack Overview' dashboard!")
print("========================================================")

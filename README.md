# Deception Lab — Honeypot & SOC Integration Lab

A self-contained, enterprise-grade cybersecurity deception lab simulated on a private VirtualBox network, with centralized log ingestion, processing, threat intelligence enrichment, and MITRE ATT&CK mapping via an ELK Stack (Elasticsearch, Logstash, Kibana).

---

## 🏗️ Architecture Overview

The lab is composed of three VirtualBox Virtual Machines (VMs) and a centralized log management/SOC monitoring backend running in Docker:

```mermaid
graph TD
    subgraph Windows Host (Docker)
        ELK[ELK Stack <br> port 5055/5601/9200]
    end

    subgraph Mesh Subnet (192.168.100.0/24)
        Kali[Attacker VM <br> 192.168.100.40]
        Hub[Deception Hub <br> 192.168.100.20]
        Sac[Sacrificial VM <br> 192.168.100.30]
    end

    Kali -->|Attacks| Hub
    Kali -->|Attacks| Sac
    Hub -->|Filebeat Logs| ELK
    Sac -->|Filebeat Logs| ELK
```

1. **Host-Only Network Interface (`192.168.56.x`):** Facilitates management traffic and allows the VMs to ship logs to Logstash on the host machine at `192.168.56.1:5055`.
2. **Mesh Internal Network (`192.168.100.x`):** A private network without Internet access where all VM-to-VM attack traffic takes place.
3. **SOC Backend (ELK Stack):** Deployed via Docker Compose on the host machine. Logstash listens on port `5055` to ingest log events, enrich them, and store them in Elasticsearch.

---

## 📂 Directory Structure

```text
├── docker-compose.yml           # Runs Elasticsearch, Kibana, and Logstash
├── .env.example                 # Example environment variables template
├── .gitignore                   # Standard Git exclusions (protects .env and large files)
├── docs/
│   └── lab_setup_plan.md        # Detailed lab design and reference runbook
├── kibana_configs/
│   └── kibana_guide.md          # Guide to configure Index Patterns, Detection Rules, & Dashboards
├── logstash/
│   └── pipeline/
│       ├── logstash.conf        # Ingests Beats events, enriches via Threat Intel, maps MITRE tags
│       └── mitre_map.yml        # Logstash translation map for MITRE ATT&CK tactics & techniques
└── vm_configs/
    ├── attacker-kali/           # Kali VM static IP setup and Scapy spoofed-attack script
    ├── deception-hub/           # Cowrie SSH, OpenCanary (SMB/HTTP/FTP/MSSQL), and Filebeat
    └── sacrificial-vm/          # Auditd rules, Sysmon, CanaryTokens, and Filebeat config
```

---

## 🚀 Quick Start & Setup Runbook

### Step 1: Start the ELK Stack
1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` and fill in your passwords and API keys for **AbuseIPDB**, **VirusTotal**, and **OTX**. (Keys are optional but required for Threat Intel lookups).
3. Start the containers using Docker Compose:
   ```bash
   docker compose up -d
   ```
4. Verify Kibana is up at `http://localhost:5601`.

### Step 2: Configure VirtualBox Network Adapters
Ensure your VMs have two network interfaces enabled:
- **Adapter 1:** Host-Only Adapter (IP range `192.168.56.x` - used for shipping logs to the host).
- **Adapter 2:** Internal Network / Host-Only Adapter (IP range `192.168.100.x` - represents the simulated corporate subnet).

### Step 3: Provision the Virtual Machines
Navigate to each subdirectory under `vm_configs/` and run the corresponding shell setups on your VMs:
- **Deception Hub (`192.168.100.20`):** Run [setup_hub.sh](file:///c:/PROJECTS/Honeypot/vm_configs/deception-hub/setup_hub.sh) to install Cowrie, OpenCanary, and Filebeat.
- **Sacrificial VM (`192.168.100.30`):** Run [setup_sacrificial.sh](file:///c:/PROJECTS/Honeypot/vm_configs/sacrificial-vm/setup_sacrificial.sh) to configure Auditd, Sysmon, Canary tokens, and Filebeat.
- **Attacker VM (`192.168.100.40`):** Run [setup_kali.sh](file:///c:/PROJECTS/Honeypot/vm_configs/attacker-kali/setup_kali.sh) to set up static network routing.

---

## 🔍 Threat Intelligence & MITRE ATT&CK Enrichment

Logstash dynamically parses, extracts, and enriches logs passing through the pipeline:
- **GeoIP Lookup:** Resolves attackers' public IP addresses to physical coordinates.
- **API Enrichments:** Queries AbuseIPDB, VirusTotal, and AlienVault OTX to determine the reputation and historical malicious status of IP addresses.
- **MITRE Mapping:** Uses `mitre_map.yml` translation dictionaries to map honeypot login success/failure events, Auditd logs, and OpenCanary alerts directly to MITRE ATT&CK Tactics and Techniques (e.g., Credential Access, Discovery, Reconnaissance).

---

## 🛡️ Kibana Security Monitoring & Dashboards
Follow [kibana_guide.md](file:///c:/PROJECTS/Honeypot/kibana_configs/kibana_guide.md) to set up:
- **Detection Rules:** Trigger alerts on SSH Brute Force attacks, Canary token file reads, and Data Staging commands (e.g. `tar`, `zip` in `/tmp`).
- **Dashboards:** Visualize Attack Overview (GeoIP heatmaps, VT score gauge), Kill Chain Timelines, and honeypot interaction metrics (password word clouds, command history logs).

---

## ⚠️ Security Notice
Do **NOT** commit `.env` containing your actual API keys or passwords. A `.gitignore` file is configured in the root of the repository to prevent this.

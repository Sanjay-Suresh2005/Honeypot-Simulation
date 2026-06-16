# Implementation Plan — Deception Lab Setup

Build a self-contained cybersecurity home lab on a single Windows physical machine that simulates a corporate network being attacked, with full detection and threat intelligence enrichment flowing into ELK.

## User Review Required

> [!IMPORTANT]
> **Filebeat Output vs. Logstash Input Type:**
> The requirement states that Logstash input should be `tcp { port => 5055, codec => json }`. However, Filebeat's standard `output.logstash` uses the Beats framing protocol, which is incompatible with raw TCP JSON input. We have two options:
> 1. Use `beats { port => 5055, codec => json }` in `logstash.conf` so Filebeat can connect directly using its standard output configuration.
> 2. Use `tcp { port => 5055, codec => json }` in `logstash.conf` and configure Filebeat on the VMs to output to console and pipe to netcat (e.g. `filebeat -e | nc 192.168.56.1 5055`), or use another log forwarder like Vector or Fluent-Bit.
> 
> *Recommendation:* We propose configuring Logstash to use the `tcp` input as requested, but also document the exact `beats` alternative in the file comments so it can be easily toggled.


## Open Questions
- Do you already have API keys for **AbuseIPDB**, **VirusTotal**, and **OTX**? If so, you should update them in the `.env` file (currently named `env` in the folder).
- Is it okay if we rename `env` and `gitignore` to `.env` and `.gitignore` respectively? This is necessary for standard Docker Compose environment file recognition and Git tracking.

---

## Proposed Changes

### [Host Configuration]
We will correct the file names for the environment and gitignore files to ensure Docker Compose and git work correctly. We will then create the Logstash pipeline configuration.

#### [MODIFY] [env](file:///c:/PROJECTS/Honeypot/env) (Rename to `.env`)
Rename `env` to `.env` and configure credentials and API keys.

#### [MODIFY] [gitignore](file:///c:/PROJECTS/Honeypot/gitignore) (Rename to `.gitignore`)
Rename `gitignore` to `.gitignore`.

#### [NEW] [logstash.conf](file:///c:/PROJECTS/Honeypot/logstash/pipeline/logstash.conf)
Create the Logstash configuration file under the volume mount path `./logstash/pipeline/logstash.conf`. It will include:
- A TCP input on port 5055 (or Beats input depending on the user preference, with comments to toggle).
- An IP-aliasing check, honeypot tag validation, and a 5-minute deduplication throttle on source IPs.
- HTTP filter lookups to AbuseIPDB, VirusTotal, and AlienVault OTX, dynamically parsing scores and counts.
- Elasticsearch output to indexing pattern `honeypot-events-YYYY.MM.dd`.

---

### [VM & Service Configurations (Runbook / Guides)]
We will document the precise setups for the VirtualBox VMs so the user can easily install and configure the honeypot components.

#### [GUIDE] Deception Hub Configuration (Ubuntu)
- Set static IPs: `192.168.100.20` (mesh) and `192.168.56.10` (host-only).
- Install **Cowrie** SSH honeypot:
  - Configure Cowrie to listen on port 2222.
  - Setup IP tables redirect from port 22 to 2222 to capture default SSH attempts.
- Install **OpenCanary**:
  - Configure a fake SMB share named `\\fileserver\finance`.

- Configure **Filebeat**:
  - Harvest `/var/log/cowrie/cowrie.json` and `/var/log/opencanary.log`.
  - Ship logs to `192.168.56.1:5055` (Logstash host).

#### [GUIDE] Sacrificial VM Configuration (Ubuntu)
- Set static IPs: `192.168.100.30` (mesh) and `192.168.56.11` (host-only).
- Configure real SSH on port 22 (credentials: `admin:admin123`).
- Install **Auditd** and configure rules to monitor `/tmp` folder archives (`zip`, `tar`) and SSH file access.
- Install **Sysmon for Linux** to monitor process creations and networking.
- Plant **CanaryToken** files:
  - Create file `~/.aws/credentials` containing a canary AWS API key.
  - Place `~/2026_Financial_Forecast.xlsx` containing a document canary.
- Configure **Filebeat**:
  - Harvest `/var/log/audit/audit.log` and Sysmon logs.
  - Ship to `192.168.56.1:5055`.

---

### [Kibana Deliverables]
We will compile the configurations and scripts to auto-generate or guide the creation of the Kibana dashboards and index patterns.

- **Index Pattern:** `honeypot-events-*`
- **Dashboard 1 (Attack Overview):** Map, TI confidence score indicators, threat heatmaps.
- **Dashboard 2 (Kill Chain):** Discover timeline with event categories mapped to MITRE ATT&CK tags (`T1595`, `T1110`, `T1059`, etc.).
- **Dashboard 3 (Honeypot Activity):** Visual logs of Cowrie shells, OpenCanary SMB hits, and canary tokens.
- **Detection Rules:**
  - *SSH Brute Force:* >10 failed attempts within 5 minutes.

  - *Canary File Access:* Alerts on any operations touching `~/.aws/credentials` or `~/2026_Financial_Forecast.xlsx`.
  - *Data Staging:* Processes spawning archiving commands (e.g. `zip`, `tar`, `gzip`) in `/tmp`.

---

## Verification Plan

### Automated Tests
- Syntax validation of the Logstash configuration.
- Checking connection from the Windows host to Logstash container using:
  ```powershell
  Test-NetConnection -ComputerName 127.0.0.1 -Port 5055
  ```
- Sending mock events using `Invoke-RestMethod` or `curl` to test throttle and API enrichments:
  ```powershell
  $body = @{ "tags" = @("honeypot_data"); "source" = @{ "ip" = "8.8.8.8" } } | ConvertTo-Json
  $body | Out-String | telnet 127.0.0.1 5055
  ```

### Manual Verification
- Deploying the docker-compose stack and confirming Kibana is reachable at `http://localhost:5601`.
- Running the Attack Simulation Sequence from VM 1 (Kali) and verifying detection logs.

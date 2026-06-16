# Kibana Configuration Guide — Deception Lab

This guide details the index patterns, detection rules, and dashboard layouts required to complete the ELK/Kibana integration for your Deception Lab.

---

## 1. Create Index Pattern

1. Open Kibana at `http://localhost:5601`.
2. Go to **Management** → **Stack Management** → **Data Views** (or **Index Patterns** depending on version).
3. Click **Create data view**.
4. Configure:
   - **Name:** `Honeypot Events`
   - **Index pattern:** `honeypot-events-*`
   - **Timestamp field:** `@timestamp`
5. Click **Save data view to Kibana**.

---

## 2. Detection Rules Configuration

Navigate to **Security** → **Rules** → **Create rule**. Configure the following four custom detection rules:

### Rule 1: SSH Brute Force Detection (T1110)
Detects excessive SSH login failures targeting the Cowrie honeypot or the Sacrificial VM.
* **Rule Type:** Threshold
* **Index Pattern:** `honeypot-events-*`
* **Custom Query (KQL):**
  ```kql
  (event.dataset: "cowrie" AND event.action: "login" AND status: "fail") OR (event.dataset: "auditd" AND event.action: "ssh_login" AND status: "failed")
  ```
* **Threshold Settings:**
  - **Group by:** `source.ip`
  - **Threshold:** `> 10`
  - **Time window:** `5 minutes`
* **MITRE ATT&CK Mapping:**
  - **Tactic:** Credential Access (TA0006)
  - **Technique:** Brute Force (T1110)
### Rule 2: Canary File Access Alert (T1083)
Fires whenever a user reads or modifies the planted Canary token files on the Sacrificial VM.
* **Rule Type:** Custom query
* **Index Pattern:** `honeypot-events-*`
* **Custom Query (KQL):**
  ```kql
  event.dataset: "auditd" AND (audit.key: "canary_aws_access" OR audit.key: "canary_finance_access")
  ```
* **Time window:** `5 minutes` (Run every 5 minutes)
* **MITRE ATT&CK Mapping:**
  - **Tactic:** Discovery (TA0007)
  - **Technique:** File and Directory Discovery (T1083)

### Rule 3: Data Staging - Large Archive Created in /tmp (T1074)
Detects commands commonly used to pack and stage data before exfiltration.
* **Rule Type:** Custom query
* **Index Pattern:** `honeypot-events-*`
* **Custom Query (KQL):**
  ```kql
  event.dataset: "auditd" AND audit.key: "staging_archive_exec"
  ```
* **Time window:** `5 minutes`
* **MITRE ATT&CK Mapping:**
  - **Tactic:** Collection (TA0009)
  - **Technique:** Data Staging (T1074)

### Rule 4: Manual Decoy IP Scanning (T1595)
Detects when an attacker performs a network discovery scan that hits one of your manually configured silent decoy IPs (Option B).
* **Rule Type:** Custom query
* **Index Pattern:** `honeypot-events-*`
* **Custom Query (KQL):**
  ```kql
  event.dataset: "decoy-scan"
  ```
* **Time window:** `5 minutes`
* **MITRE ATT&CK Mapping:**
  - **Tactic:** Reconnaissance (TA0043)
  - **Technique:** Active Scanning (T1595)

---


## 3. Kibana Dashboards Setup

Navigate to **Analytics** → **Dashboards** → **Create dashboard**.

### Dashboard 1: Attack Overview
This dashboard gives a high-level view of who is hitting the network.
* **Visualizations:**
  1. **Top Attacker IPs (Bar Chart):**
     - X-axis: `source.ip` (Terms aggregation, top 10)
     - Y-axis: Count of records
  2. **Threat Intelligence Country Map (Map):**
     - Layer: Documents containing `source.ip`
     - Uses Kibana’s IP-to-GeoIP processor to plot source locations.
  3. **Average Threat Score (Gauge):**
     - Metric: Average of `threat.abuse_score` (Targeting AbuseIPDB data).
  4. **VirusTotal & OTX Correlation (Data Table):**
     - Columns: `source.ip`, `threat.vt_malicious`, `threat.otx_pulses`
     - Filter: `threat.vt_malicious > 0`

### Dashboard 2: Kill Chain Timeline
Visualize attacker movements through the mesh network using the exact MITRE tags.
* **Visualizations:**
  1. **Kill Chain Progress (Timeline / Line Chart):**
     - X-axis: `@timestamp`
     - Y-axis: Count of events
     - Break down by: `mitre_tag` or `event.dataset`
  2. **Event stream with MITRE Tactics (Data Table):**
     - Columns: `@timestamp`, `source.ip`, `event.dataset`, `message`, `mitre_technique`
     - Sort: `@timestamp` descending

### Dashboard 3: Honeypot Activity
Drill down into Cowrie SSH commands, fake SMB traffic, and Canary interactions.
* **Visualizations:**
  1. **Cowrie Credential Attempts (Word Cloud):**
     - Field: `password` (shows most frequently guessed passwords by brute-forcer).
  2. **Cowrie Commands Executed (Data Table):**
     - Columns: `source.ip`, `input` (raw command executed in fake shell)
  3. **OpenCanary SMB Share Hits (Pie Chart):**
     - Split slices by: `source.ip` where `event.dataset: "opencanary"`
  4. **Canary Token File Triggers (Metric Card):**
     - Metric: Count of events where `audit.key` contains `canary_`

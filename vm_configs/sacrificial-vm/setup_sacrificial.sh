#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Deception Lab — Sacrificial VM Setup Script
#  Path: vm_configs/sacrificial-vm/setup_sacrificial.sh
#  Run on Sacrificial VM (Ubuntu Server) as root.
# ─────────────────────────────────────────────────────────────────────────────

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

echo "========================================================"
echo " Starting Sacrificial VM Installation and Configuration "
echo "========================================================"

# 1. Update and install basic dependencies
echo "[*] Installing dependencies..."
apt-get update -y
apt-get install -y openssh-server auditd audispd-plugins curl wget gnupg2 software-properties-common lsb-release

# 2. Configure weak SSH credentials
echo "[*] Creating vulnerable admin account (admin:admin123)..."
# Create user admin if it doesn't exist
if ! id "admin" &>/dev/null; then
    useradd -m -s /bin/bash admin
fi
# Set password to admin123
echo "admin:admin123" | chpasswd
# Give admin sudo permissions (representing a compromised administrative endpoint)
usermod -aG sudo admin

# Configure SSH to allow password authentication
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "[+] SSH configured on port 22 with user admin:admin123"

# 3. Apply Auditd Configuration
echo "[*] Applying Auditd configurations..."
cp audit.rules /etc/audit/rules.d/audit.rules || {
    echo "[-] audit.rules file not found in current folder. Using fallback configuration..."
    cat <<EOF > /etc/audit/rules.d/audit.rules
-D
-b 8192
-f 1
-w /home/admin/.aws/credentials -p rwa -k canary_aws_access
-w /home/admin/2026_Financial_Forecast.xlsx -p rwa -k canary_finance_access
-w /usr/bin/tar -p x -k staging_archive_exec
-w /usr/bin/zip -p x -k staging_archive_exec
-w /usr/bin/unzip -p x -k staging_archive_exec
-w /usr/bin/gzip -p x -k staging_archive_exec
-w /usr/bin/gunzip -p x -k staging_archive_exec
-w /usr/bin/scp -p x -k exfil_scp
-w /tmp -p x -k tmp_execution
EOF
}

# Restart auditd service (requires service command, systemctl restart auditd can fail on some systems due to security)
service auditd restart || systemctl restart auditd
echo "[+] Auditd rules applied."

# 4. Install Sysmon for Linux
echo "[*] Installing Sysmon for Linux..."
# Register Microsoft package repository
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

apt-get update
apt-get install -y sysmonforlinux

# Apply Sysmon configuration
cp sysmonconfig.xml /etc/sysmonconfig.xml || {
    echo "[-] sysmonconfig.xml not found. Creating a minimal fallback..."
    cat <<EOF > /etc/sysmonconfig.xml
<Sysmon schemaversion="4.81">
  <EventFiltering>
    <RuleGroup groupRelation="or">
      <ProcessCreate onmatch="include">
        <CommandLine condition="contains"> </CommandLine>
      </ProcessCreate>
    </RuleGroup>
    <RuleGroup groupRelation="or">
      <NetworkConnect onmatch="include">
        <DestinationIp condition="is not">127.0.0.1</DestinationIp>
      </NetworkConnect>
    </RuleGroup>
  </EventFiltering>
</Sysmon>
EOF
    cp /etc/sysmonconfig.xml sysmonconfig.xml
}

# Start/install Sysmon configuration
sysmon -i /etc/sysmonconfig.xml
echo "[+] Sysmon for Linux started."

# 5. Plant CanaryToken Placeholders
echo "[*] Planting CanaryToken files..."
# AWS Credentials
mkdir -p /home/admin/.aws
cat <<EOF > /home/admin/.aws/credentials
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Tip: Generate a real AWS CanaryToken at canarytokens.org and paste the values here to receive alert emails!
EOF
chown -R admin:admin /home/admin/.aws

# Excel Spreadsheet
# Creating a dummy file for the user to replace with a real document token
echo "CONFIDENTIAL: 2026 Financial Forecast. Go to canarytokens.org to create a web-bug document token to replace this file for live tracking." > /home/admin/2026_Financial_Forecast.xlsx
chown admin:admin /home/admin/2026_Financial_Forecast.xlsx
echo "[+] Canary file placeholders planted in admin home directory."

# 6. Install Filebeat
echo "[*] Installing Filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.4.1-amd64.deb
    dpkg -i filebeat-9.4.1-amd64.deb
    rm filebeat-9.4.1-amd64.deb
fi

# Apply Filebeat config
cp filebeat.yml /etc/filebeat/filebeat.yml
chmod 600 /etc/filebeat/filebeat.yml

# Start Filebeat service
systemctl daemon-reload
systemctl enable filebeat
systemctl restart filebeat

echo "========================================================"
echo " Sacrificial VM Setup Complete!                         "
echo " Logs are now shipping to Logstash at 192.168.56.1:5055  "
echo "========================================================"

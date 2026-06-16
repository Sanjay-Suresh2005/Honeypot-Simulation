#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Deception Lab — Deception Hub Setup Script
#  Path: vm_configs/deception-hub/setup_hub.sh
#  Run on Deception Hub VM (Ubuntu Server) as root.
# ─────────────────────────────────────────────────────────────────────────────

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

# Change to the directory where the script is located to resolve config paths correctly
cd "$(dirname "$0")"

echo "========================================================"
echo " Starting Deception Hub Installation and Configuration "
echo "========================================================"

# 1. Update and install dependencies
echo "[*] Installing required packages..."
apt-get update -y
apt-get install -y git python3-pip python3-virtualenv python3-venv libssl-dev libffi-dev build-essential samba rsyslog curl


# 3. Configure Cowrie Honeypot
echo "[*] Setting up Cowrie SSH honeypot..."
# Create a dedicated user for cowrie
if ! id "cowrie" &>/dev/null; then
    useradd -r -m -d /home/cowrie -s /bin/bash cowrie
fi

# Clone and build Cowrie
COWRIE_DIR="/home/cowrie/cowrie"
if [ ! -d "$COWRIE_DIR" ]; then
    git clone https://github.com/cowrie/cowrie.git "$COWRIE_DIR"
    chown -R cowrie:cowrie "$COWRIE_DIR"
fi

# Create virtual environment and install dependencies
echo "[*] Setting up Python virtual environment and installing Cowrie dependencies..."
sudo -u cowrie bash -c "cd $COWRIE_DIR && python3 -m venv cowrie-env && source cowrie-env/bin/activate && pip install --upgrade pip && pip install -r requirements.txt && pip install ."

# Apply Cowrie config
cp cowrie.cfg "$COWRIE_DIR/etc/cowrie.cfg" || {
    echo "[-] cowrie.cfg file not found in current folder. Creating a minimal fallback..."
    cat <<EOF > "$COWRIE_DIR/etc/cowrie.cfg"
[syslog]
enabled = false
[output_jsonlog]
enabled = true
logfile = /var/log/cowrie/cowrie.json
[ssh]
enabled = true
listen_port = 2222
listen_addr = 0.0.0.0
hostname = corp-web-prod
EOF
}
chown cowrie:cowrie "$COWRIE_DIR/etc/cowrie.cfg"

# Create log directory and set permissions
mkdir -p /var/log/cowrie
chown -R cowrie:cowrie /var/log/cowrie

# Setup iptables redirection from port 22 to 2222 on enp0s3 (mesh interface)
echo "[*] Creating iptables rules to redirect SSH port 22 -> 2222..."
iptables -t nat -A PREROUTING -i enp0s3 -p tcp --dport 22 -j REDIRECT --to-port 2222
# Save iptables rules so they persist
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4

# Configure real SSH daemon to bind only to the Host-Only IP (192.168.56.10)
echo "[*] Configuring real sshd to only listen on Host-Only interface (192.168.56.10)..."
echo "net.ipv4.ip_nonlocal_bind = 1" > /etc/sysctl.d/99-nonlocal-bind.conf
sysctl -p /etc/sysctl.d/99-nonlocal-bind.conf || true

# Update sshd_config to bind strictly to host-only IP
sed -i '/^#\?ListenAddress/d' /etc/ssh/sshd_config
echo "ListenAddress 192.168.56.10" >> /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

# 4. Configure Samba for Fake SMB Share (OpenCanary integration)
echo "[*] Setting up Samba fake share and full_audit logging..."
mkdir -p /srv/finance
chmod 777 /srv/finance
touch /srv/finance/2026_Merger_Strategy.docx
touch /srv/finance/Q1_Salary_Details.xlsx

# Back up original samba configuration
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Setup Samba full_audit config
cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server string = Corp File Server
   server role = standalone server
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   map to guest = bad user

   # Audit config for OpenCanary detection
   vfs objects = full_audit
   full_audit:prefix = %U|%I|%i|%m|%S|%L|%R|%a|%T|%D
   full_audit:success = connect disconnect open read write rename unlink
   full_audit:failure = connect open
   full_audit:facility = local7
   full_audit:priority = NOTICE

[finance]
   comment = Finance Department Documents
   path = /srv/finance
   browseable = yes
   read only = no
   guest ok = yes
   force user = nobody
EOF

# Direct audit logs from local7 to /var/log/samba-audit.log in traditional format
echo 'local7.notice /var/log/samba-audit.log;RSYSLOG_TraditionalFileFormat' > /etc/rsyslog.d/45-samba-audit.conf
systemctl restart rsyslog
systemctl restart smbd

# 5. Configure OpenCanary
echo "[*] Setting up OpenCanary..."

# 5.1 Pre-flight check: Verify ports 21, 80, and 1433 are not in use
echo "[*] Verifying port availability for OpenCanary (21, 80, 1433)..."
for port in 21 80 1433; do
    if ss -tulpn | grep -q ":$port "; then
        echo "[-] WARNING: Port $port is already in use by another process!"
        ss -tulpn | grep ":$port "
    else
        echo "[+] Port $port is available."
    fi
done

pip3 install opencanary scapy --break-system-packages --ignore-installed

mkdir -p /etc/opencanaryd
cp opencanary.conf /etc/opencanaryd/opencanary.conf || {
    echo "[-] opencanary.conf not found. Creating a minimal fallback..."
    cat <<EOF > /etc/opencanaryd/opencanary.conf
{
  "device.node_id": "corp-fileserver",
  "ip.ignore_addr": [],
  "syslog.device": true,
  "logger": {
    "class": "PyLogger",
    "kwargs": {
      "handlers": {
        "file": {
          "class": "logging.FileHandler",
          "filename": "/var/log/opencanary.log"
        }
      }
    }
  },
  "ftp.enabled": true,
  "ftp.port": 21,
  "ftp.banner": "220 FTP version 1.0 ready",
  "http.enabled": true,
  "http.port": 80,
  "http.skin": "nasLogin",
  "http.banner": "Apache/2.4.41 (Ubuntu)",
  "mssql.enabled": true,
  "mssql.port": 1433,
  "ssh.enabled": false,
  "telnet.enabled": false,
  "smb.enabled": true,
  "smb.auditfile": "/var/log/samba-audit.log"
}
EOF
}

# 6. Install Filebeat
echo "[*] Installing Elastic Filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.4.1-amd64.deb
    dpkg -i filebeat-9.4.1-amd64.deb
    rm filebeat-9.4.1-amd64.deb
fi

# Apply Filebeat config
cp filebeat.yml /etc/filebeat/filebeat.yml
chmod 600 /etc/filebeat/filebeat.yml

# 7. Start Services
echo "[*] Starting all honeypot and logging services..."
# Start Cowrie under its user account
sudo -u cowrie bash -c "cd $COWRIE_DIR && source cowrie-env/bin/activate && cowrie start"

# Start OpenCanary
opencanaryd --start

# Start Filebeat
systemctl daemon-reload
systemctl enable filebeat
systemctl restart filebeat

echo "========================================================"
echo " Deception Hub Setup Complete!                          "
echo " Logs are now shipping to Logstash at 192.168.56.1:5055  "
echo "========================================================"

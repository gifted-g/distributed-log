#!/usr/bin/env bash
set -euo pipefail

echo "[*] Setting up central rsyslog receiver + log scanner"
LOG_ROOT="/var/log/remote"

# Install rsyslog listener
install -m 0644 01-listen.conf /etc/rsyslog.d/01-listen.conf
install -m 0644 rsyslog-server.conf /etc/rsyslog.d/99-server-extra.conf
mkdir -p "${LOG_ROOT}"
chown syslog:adm "${LOG_ROOT}" || true

systemctl restart rsyslog
echo "[+] rsyslog listening on TCP 6514"

# Install config and scanner
install -m 0755 logscan.sh /usr/local/bin/logscan.sh
install -m 0644 config.env /etc/default/logscan.env

# systemd units
install -m 0644 systemd/logscan.service /etc/systemd/system/logscan.service
install -m 0644 systemd/logscan.timer /etc/systemd/system/logscan.timer
systemctl daemon-reload
systemctl enable --now logscan.timer

echo "[+] logscan timer enabled. Edit /etc/default/logscan.env to configure."
echo "[i] Check: systemctl status logscan.timer && journalctl -u logscan.service -n 50 --no-pager"

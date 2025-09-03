# Distributed Log Processing & Alerting System ⚡

An MVP for collecting `/var/log` from multiple Linux servers to a central node, scanning logs
with **bash/awk/sed** for anomalies (e.g., repeated failed SSH logins), and sending alerts to
**Slack or email** when thresholds are exceeded.

> No heavy dependencies. Uses built-in **rsyslog** for transport and a lightweight scanner
> scheduled with **systemd timer**.

---

## 🏗 Architecture (MVP)

**Agents (each Linux server)**
- rsyslog forwards selected logs (e.g., `auth.log`, `syslog`) to the central server over TCP.

**Central Log Server**
- rsyslog receives and stores logs per-host under `/var/log/remote/<HOST>/...`.
- `logscan.sh` runs every minute via `systemd` to scan the last N minutes for anomalies.
- Alerts are sent to **Slack** (via webhook) and optionally **email**.

```
+------------+        TCP/6514        +------------------+
|  Server A  |  ==>  rsyslog forward  |  Central Server  |
|  Server B  |  ==>  rsyslog forward  |  rsyslog receive |
|  Server C  |                        |  logscan + alerts|
+------------+                        +------------------+
```

---

## 📦 Repo Layout

```
distributed-log-mvp/
├── README.md
├── agent/
│   ├── rsyslog-client.conf
│   └── setup_agent.sh
├── server/
│   ├── 01-listen.conf
│   ├── rsyslog-server.conf
│   ├── setup_server.sh
│   ├── config.env
│   ├── logscan.sh
│   └── systemd/
│       ├── logscan.service
│       └── logscan.timer
├── future/
│   ├── dashboard_ncurses_TODO.md
│   ├── elk_TODO.md
│   └── ml_anomaly_TODO.md
└── scripts/
    └── test_samples_generate.sh
```

---

## ✅ What it Detects (default)

- Repeated **failed SSH logins** in the last **5 minutes**:
  - By **IP**: `>= 5` failures triggers an alert.
  - By **username**: `>= 8` failures triggers an alert.

Tweak these in `server/config.env`.

---

## 🔐 Requirements

- Linux hosts with **rsyslog** (most distros ship it by default).
- Central server with `bash`, `awk`, `sed`, `curl`.
- (Optional) `mail` or `mailx` for email alerts.

---

## 🚀 Quick Start

### 1) Central Server Setup

> Run as root (or with sudo)

```bash
cd /opt
git clone <this repo> distributed-log-mvp
cd distributed-log-mvp/server

# Edit alert settings
nano config.env

# Run setup
bash setup_server.sh
```

This will:
- Enable rsyslog TCP listener on port **6514** (changeable).
- Create `/var/log/remote` for per-host storage.
- Install the log scanner, env file, and **systemd timer** (runs every minute).

Check status:
```bash
systemctl status logscan.timer
journalctl -u logscan.service -n 50 --no-pager
```

### 2) Agent Setup (on each source server)

```bash
# Copy agent files to the machine or curl them from your repo
cd /opt/distributed-log-mvp/agent

# Set your central server IP or DNS
export LOG_SERVER=10.0.0.5
sudo bash setup_agent.sh "$LOG_SERVER"
```

This will:
- Install a client rsyslog snippet to forward `auth.log` and `syslog` to the central server.
- Restart rsyslog.

### 3) Send a Test

Trigger a fake failed SSH attempt against an agent (wrong password) and watch
the central server alert (Slack/email).

---

## 🧰 Configuration

Edit `server/config.env`:

```ini
# Where rsyslog stores remote logs (per-host)
LOG_ROOT=/var/log/remote

# Sliding window (minutes) scanned each run
WINDOW_MINUTES=5

# Thresholds
THRESHOLD_IP=5
THRESHOLD_USER=8

# Cooldown to avoid spam (minutes)
ALERT_COOLDOWN_MIN=30

# Slack (set your Incoming Webhook URL)
SLACK_WEBHOOK_URL=

# Optional email (requires 'mail' command configured)
ENABLE_EMAIL=0
MAIL_TO=alerts@example.com
MAIL_SUBJECT_PREFIX=[LogScan]
```

---

## 🧪 Dry Run (no alerts)

You can run the scanner in dry-run mode:

```bash
sudo env DRY_RUN=1 /usr/local/bin/logscan.sh
```

---

## 🧯 Uninstall

```bash
sudo systemctl disable --now logscan.timer
sudo rm -f /usr/local/bin/logscan.sh /etc/default/logscan.env
sudo rm -f /etc/rsyslog.d/01-listen.conf /etc/rsyslog.d/99-remote-storage.conf
sudo systemctl restart rsyslog
```

---

## 🔭 Future Enhancements

- **ncurses dashboard** reading the alert DB under `/var/lib/logscan/alerts.db` (see `future/dashboard_ncurses_TODO.md`).
- **ELK**: Optionally ship `/var/log/remote` into Elasticsearch via Filebeat; visualize in Kibana.
- **ML**: Add a Python service that learns baseline rates per host/IP and detects anomalies.

---

## ⚠️ Notes

- This MVP focuses on **auth.log** (SSH). You can add more patterns easily in `logscan.sh`.
- Ensure firewall allows TCP **6514** from agents to the central server (or change the port).
- For secure transport, consider rsyslog **TLS** (omitted for brevity in MVP; add later).

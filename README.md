# distributed-log
A lightweight distributed log processing &amp; alerting system. Collects /var/log from multiple servers via rsyslog, scans for anomalies (e.g., failed SSH logins) with bash/awk, and sends alerts to Slack/email. Features thresholds, cooldowns, systemd timers, and is extensible with dashboards, ELK, or ML.

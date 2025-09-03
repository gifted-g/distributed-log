# Terminal Dashboard (ncurses) – TODO

- Read `/var/lib/logscan/alerts.db` and show recent alerts.
- Panels:
  - Top active IPs (last 1h)
  - Top targeted users (last 1h)
  - Per-host activity
- Controls: filter by host, export CSV.
- Libraries: `ncurses` via `whiptail` or Python `curses` (optional).

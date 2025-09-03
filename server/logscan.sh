\
#!/usr/bin/env bash
set -euo pipefail

# Load configuration
CONF_FILE="/etc/default/logscan.env"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE" || true

LOG_ROOT="${LOG_ROOT:-/var/log/remote}"
WINDOW_MINUTES="${WINDOW_MINUTES:-5}"
THRESHOLD_IP="${THRESHOLD_IP:-5}"
THRESHOLD_USER="${THRESHOLD_USER:-8}"
ALERT_COOLDOWN_MIN="${ALERT_COOLDOWN_MIN:-30}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
ENABLE_EMAIL="${ENABLE_EMAIL:-0}"
MAIL_TO="${MAIL_TO:-}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[LogScan]}"
STATE_DIR="/var/lib/logscan"
ALERT_DB="${STATE_DIR}/alerts.db"

DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$STATE_DIR"

now_epoch=$(date +%s)
year=$(date +%Y)

# helper: check cooldown; key is like "ip:1.2.3.4" or "user:root"
cooldown_ok() {
  local key="$1"
  local now="$2"
  local cooldown_min="$3"
  local last ts diff
  if [[ -f "$ALERT_DB" ]]; then
    last=$(grep -E "^${key}\|" "$ALERT_DB" | tail -n1 | awk -F'|' '{print $2}')
  else
    last=""
  fi
  if [[ -z "$last" ]]; then
    return 0
  fi
  diff=$(( now - last ))
  if (( diff >= cooldown_min*60 )); then
    return 0
  fi
  return 1
}

record_alert_ts() {
  local key="$1"; local ts="$2"
  # remove previous lines for key then append
  if [[ -f "$ALERT_DB" ]]; then
    grep -v -E "^${key}\|" "$ALERT_DB" > "${ALERT_DB}.tmp" || true
    mv "${ALERT_DB}.tmp" "$ALERT_DB"
  fi
  echo "${key}|${ts}" >> "$ALERT_DB"
}

send_slack() {
  local text="$1"
  [[ -z "$SLACK_WEBHOOK_URL" ]] && return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY] Slack: $text"
    return 0
  fi
  curl -sS -X POST -H 'Content-type: application/json' --data "{\"text\":\"${text//\"/\\\"}\"}" "$SLACK_WEBHOOK_URL" >/dev/null || true
}

send_email() {
  local subject="$1"; local body="$2"
  [[ "${ENABLE_EMAIL}" == "1" && -n "${MAIL_TO}" ]] || return 0
  if command -v mail >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "[DRY] Email to ${MAIL_TO}: ${subject}"
      return 0
    fi
    echo -e "$body" | mail -s "$subject" "$MAIL_TO" || true
  else
    echo "[WARN] 'mail' command not found; skipping email."
  fi
}

# Gather last WINDOW_MINUTES failed SSH attempts from all auth logs
mapfile -t files < <(find "$LOG_ROOT" -type f -name "auth.log" 2>/dev/null || true)

if (( ${#files[@]} == 0 )); then
  echo "[INFO] No auth.log files found under $LOG_ROOT"
  exit 0
fi

# Build AWK that parses syslog timestamps for the current year and filters the window
awk_script='
function mon2num(m){
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec",a," ");
  for(i=1;i<=12;i++){ if(a[i]==m){ return i } }
  return 0
}
BEGIN{
  now=NOW; win=WIN; yr=Y;
}
{
  mon=$1; day=$2; tm=$3;
  # e.g., "Sep 03 21:17:52"
  split(tm,t,":"); h=t[1]; mi=t[2]; s=t[3];
  monn=mon2num(mon);
  if(monn==0) next;
  # Guard against single-digit day
  gsub(/^[[:space:]]+/,"",day);
  epoch = mktime(sprintf("%d %02d %02d %02d %02d %02d", yr, monn, day, h, mi, s));
  delta = now - epoch;
  if(delta < 0 || delta > win*60) next;

  # Only consider Failed password lines
  if(index($0,"Failed password")>0){
    # user
    user=""
    if(match($0, /Failed password .* for ([^ ]+) from /, m)){
      user=m[1];
    }
    # ip (IPv4)
    ip=""
    if(match($0, / from ([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)/, a)){
      ip=a[1];
    }
    if(ip!=""){
      ipcount[ip]++;
    }
    if(user!=""){
      usercount[user]++;
    }
  }
}
END{
  for(i in ipcount){ printf("IP\t%s\t%d\n", i, ipcount[i]); }
  for(u in usercount){ printf("USER\t%s\t%d\n", u, usercount[u]); }
}
'

input_files=()
for f in "${files[@]}"; do
  input_files+=("$f")
done

if (( ${#input_files[@]} == 0 )); then
  exit 0
fi

results=$(awk -v NOW="$now_epoch" -v WIN="$WINDOW_MINUTES" -v Y="$year" "$awk_script" "${input_files[@]}" || true)

[[ -z "$results" ]] && exit 0

alerts_sent=0

while IFS=$'\t' read -r kind key count; do
  [[ -z "$kind" ]] && continue
  if [[ "$kind" == "IP" && "$count" -ge "$THRESHOLD_IP" ]]; then
    alert_key="ip:${key}"
    if cooldown_ok "$alert_key" "$now_epoch" "$ALERT_COOLDOWN_MIN"; then
      msg="🚨 SSH brute-force suspected: ${count} failed logins from IP ${key} in last ${WINDOW_MINUTES}m"
      echo "[ALERT] $msg"
      send_slack "$msg"
      send_email "${MAIL_SUBJECT_PREFIX} SSH brute: IP ${key}" "$msg"
      record_alert_ts "$alert_key" "$now_epoch"
      alerts_sent=$((alerts_sent+1))
    fi
  fi
  if [[ "$kind" == "USER" && "$count" -ge "$THRESHOLD_USER" ]]; then
    alert_key="user:${key}"
    if cooldown_ok "$alert_key" "$now_epoch" "$ALERT_COOLDOWN_MIN"; then
      msg="⚠️ Repeated failed SSH logins for user '${key}': ${count} in last ${WINDOW_MINUTES}m"
      echo "[ALERT] $msg"
      send_slack "$msg"
      send_email "${MAIL_SUBJECT_PREFIX} SSH brute: user ${key}" "$msg"
      record_alert_ts "$alert_key" "$now_epoch"
      alerts_sent=$((alerts_sent+1))
    fi
  fi
done <<< "$results"

echo "[INFO] Scan complete. Alerts sent: ${alerts_sent}"
exit 0

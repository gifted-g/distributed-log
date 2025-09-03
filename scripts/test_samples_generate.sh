\
#!/usr/bin/env bash
# Generate fake auth.log entries into /var/log/remote/<HOST>/auth.log for testing

ROOT="${1:-/var/log/remote}"
HOST="${2:-testhost}"
N="${3:-20}"

dir="${ROOT}/${HOST}"
mkdir -p "$dir"
file="${dir}/auth.log"

echo "[*] Writing ${N} failed SSH attempts into ${file}"
for i in $(seq 1 "$N"); do
  ts=$(date +"%b %e %T")
  ip="192.0.2.$(( i % 5 + 1 ))"
  user="user$(( i % 3 + 1 ))"
  echo "${ts} ${HOST} sshd[12345]: Failed password for ${user} from ${ip} port 54321 ssh2" >> "$file"
  sleep 0.1
done
echo "[+] Done."

#!/usr/bin/env bash
# server-stats.sh — Basic server performance stats
# Works on most Linux systems without extra packages.

set -euo pipefail

# ----- Helpers -----
hr() { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' '-'; }

pct() {
  # percentage: pct numerator denominator
  awk -v n="$1" -v d="$2" 'BEGIN { if (d==0) {print "0.00"} else {printf "%.2f", (n/d)*100} }'
}

bytes_h() {
  # human-readable bytes via awk (no numfmt dependency)
  awk -v b="$1" '
    function fmt(x,u){ printf "%.1f%s", x, u; exit }
    BEGIN{
      if (b<1024){print b "B"; exit}
      kib=b/1024; if (kib<1024){fmt(kib,"K")}
      mib=kib/1024; if (mib<1024){fmt(mib,"M")}
      gib=mib/1024; if (gib<1024){fmt(gib,"G")}
      tib=gib/1024; fmt(tib,"T")
    }'
}

exists() { command -v "$1" >/dev/null 2>&1; }

# ----- OS / Host info (stretch) -----
print_os_info() {
  echo "OS / Host Information"
  hr
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "OS:         ${PRETTY_NAME:-Linux}"
  else
    echo "OS:         Linux"
  fi
  echo "Kernel:     $(uname -r)"
  echo "Hostname:   $(hostname)"
  echo "Uptime:     $(uptime -p 2>/dev/null || true)"
  echo "Boot time:  $(uptime -s 2>/dev/null || true)"
  echo "Load avg:   $(cut -d' ' -f1-3 /proc/loadavg)"
  if exists who; then
    echo "Logged-in users: $(who | wc -l)"
  fi
  echo
}

# ----- CPU usage (overall) -----
cpu_usage() {
  # Read two samples from /proc/stat and compute total CPU usage %
  read -r cpu user nice system idle iowait irq softirq steal guest gnice < /proc/stat
  idle1=$((idle + iowait))
  nonidle1=$((user + nice + system + irq + softirq + steal))
  total1=$((idle1 + nonidle1))
  sleep 1
  read -r cpu user nice system idle iowait irq softirq steal guest gnice < /proc/stat
  idle2=$((idle + iowait))
  nonidle2=$((user + nice + system + irq + softirq + steal))
  total2=$((idle2 + nonidle2))

  totald=$((total2 - total1))
  idled=$((idle2 - idle1))
  awk -v td="$totald" -v id="$idled" 'BEGIN {
    if (td<=0) { print "0.00" } else { printf "%.2f", (td - id) * 100 / td }
  }'
}

print_cpu() {
  echo "CPU"
  hr
  echo "Total CPU usage: $(cpu_usage)%"
  echo
}

# ----- Memory usage -----
print_memory() {
  echo "Memory"
  hr
  # Use MemTotal and MemAvailable for a realistic 'used'
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  mem_used_kb=$((mem_total_kb - mem_avail_kb))

  mem_total_b=$((mem_total_kb * 1024))
  mem_used_b=$((mem_used_kb * 1024))
  mem_avail_b=$((mem_avail_kb * 1024))

  used_pct=$(pct "$mem_used_b" "$mem_total_b")

  echo "Total:  $(bytes_h "$mem_total_b")"
  echo "Used:   $(bytes_h "$mem_used_b") (${used_pct}%)"
  echo "Free:   $(bytes_h "$mem_avail_b")"
  echo
}

# ----- Disk usage (aggregate, excluding tmpfs/devtmpfs) -----
print_disk() {
  echo "Disk"
  hr
  # Sum across real filesystems
  # Use -B1 for bytes to keep math precise.
  read -r total used avail <<<"$(df -B1 -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
    | awk 'NR>1 {t+=$2; u+=$3; a+=$4} END {print t, u, a}')"

  total=${total:-0}; used=${used:-0}; avail=${avail:-0}
  used_pct=$(pct "$used" "$total")

  echo "Total:  $(bytes_h "$total")"
  echo "Used:   $(bytes_h "$used") (${used_pct}%)"
  echo "Free:   $(bytes_h "$avail")"
  echo
}

# ----- Top processes -----
print_top_processes() {
  echo "Top Processes"
  hr
  if exists ps; then
    echo "Top 5 by CPU:"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR==1 || NR<=6 {printf "%-7s %-25s %6s %6s\n", $1, $2, $3, $4}'
    echo
    echo "Top 5 by Memory:"
    ps -eo pid,comm,%cpu,%mem --sort=-%mem | awk 'NR==1 || NR<=6 {printf "%-7s %-25s %6s %6s\n", $1, $2, $3, $4}'
  else
    echo "ps command not found."
  fi
  echo
}

# ----- Security / auth (stretch; optional/privileged) -----
print_auth() {
  echo "Auth (optional)"
  hr
  if exists lastb; then
    # lastb reads /var/log/btmp; may need root to have full info.
    failed=$(lastb -n 100 2>/dev/null | grep -c -E '^[a-zA-Z0-9_.-]+')
    echo "Recent failed login attempts (last 100 entries parsed): ${failed}"
  else
    echo "Failed logins: lastb not available"
  fi
  echo
}

# ----- Main -----
print_os_info
print_cpu
print_memory
print_disk
print_top_processes
print_auth

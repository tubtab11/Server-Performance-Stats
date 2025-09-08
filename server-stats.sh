#!/usr/bin/env bash
# server-stats.sh — Cross-platform (Linux + macOS) server performance stats

set -euo pipefail
OS="$(uname -s)"

# ---------- helpers ----------
exists() { command -v "$1" >/dev/null 2>&1; }
hr() { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' '-'; }
pct() { awk -v n="$1" -v d="$2" 'BEGIN{ if(d==0){print "0.00"} else {printf "%.2f",(n/d)*100} }'; }
bytes_h() {
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

# ---------- OS / host ----------
print_os_info() {
  echo "OS / Host Information"; hr
  if [[ "$OS" == "Linux" ]]; then
    if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "OS:         ${PRETTY_NAME:-Linux}"; else echo "OS:         Linux"; fi
    echo "Kernel:     $(uname -r)"
    echo "Hostname:   $(hostname)"
    echo "Uptime:     $(uptime -p 2>/dev/null || uptime || true)"
    echo "Boot time:  $(uptime -s 2>/dev/null || true)"
    if [[ -r /proc/loadavg ]]; then
      echo "Load avg:   $(cut -d' ' -f1-3 /proc/loadavg)"
    else
      echo "Load avg:   $(uptime | awk -F'load averages?: ' '{print $2}')"
    fi
    [[ $(exists who; echo $?) -eq 0 ]] && echo "Logged-in users: $(who | wc -l)"
  elif [[ "$OS" == "Darwin" ]]; then
    echo "OS:         macOS $(sw_vers -productVersion 2>/dev/null || echo "(unknown)")"
    echo "Kernel:     $(uname -r)"
    echo "Hostname:   $(hostname)"
    # leave your shell's uptime prefix (users + loads) as-is (you liked it)
    echo "Uptime:     $(uptime | sed 's/^ *//')"
    # Boot time
    if exists sysctl; then
      bt_epoch=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,]' '{print $4}' || echo "")
      [[ -n "${bt_epoch:-}" ]] && echo "Boot time:  $(date -r "$bt_epoch" 2>/dev/null || true)"
    fi
    # Load avg (all three)
    echo "Load avg:   $(uptime | awk -F'load averages?: ' '{print $2}' | awk '{print $1, $2, $3}')"
    [[ $(exists who; echo $?) -eq 0 ]] && echo "Logged-in users: $(who | wc -l)"
  else
    echo "OS:         $OS"
    echo "Kernel:     $(uname -r)"
    echo "Hostname:   $(hostname)"
    echo "Uptime:     $(uptime || true)"
  fi
  echo
}

# ---------- CPU ----------
cpu_usage_linux() {
  read -r _ u n s i iw ir si st _g _gn < /proc/stat
  idle1=$((i + iw)); nonidle1=$((u + n + s + ir + si + st)); total1=$((idle1 + nonidle1))
  sleep 1
  read -r _ u n s i iw ir si st _g _gn < /proc/stat
  idle2=$((i + iw)); nonidle2=$((u + n + s + ir + si + st)); total2=$((idle2 + nonidle2))
  td=$((total2 - total1)); id=$((idle2 - idle1))
  awk -v td="$td" -v id="$id" 'BEGIN{ if(td<=0){print "0.00"} else {printf "%.2f",(td-id)*100/td} }'
}

cpu_usage_macos() {
  local usage_line idle_pct
  usage_line="$(top -l 2 -n 0 | grep -E 'CPU usage' | tail -n 1)"
  idle_pct="$(echo "$usage_line" | sed -E 's/.* ([0-9.]+)% idle.*/\1/')"
  awk -v idle="${idle_pct:-0}" 'BEGIN{ printf "%.2f", 100 - idle }'
}

print_cpu() {
  echo "CPU"; hr
  if [[ "$OS" == "Linux" ]]; then
    echo "Total CPU usage: $(cpu_usage_linux)%"
  elif [[ "$OS" == "Darwin" ]]; then
    echo "Total CPU usage: $(cpu_usage_macos)%"
  else
    echo "Total CPU usage: (unsupported OS)"
  fi
  echo
}

# ---------- Memory ----------
print_memory_linux() {
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  mem_used_kb=$((mem_total_kb - mem_avail_kb))
  total_b=$((mem_total_kb * 1024)); used_b=$((mem_used_kb * 1024)); avail_b=$((mem_avail_kb * 1024))
  echo "Total:  $(bytes_h "$total_b")"
  echo "Used:   $(bytes_h "$used_b") ($(pct "$used_b" "$total_b")%)"
  echo "Free:   $(bytes_h "$avail_b")"
}

# Robust vm_stat parsing for macOS (field names vary slightly across releases)
print_memory_macos() {
  local total_b pagesz vm free_p inactive_p speculative_p avail_b used_b
  total_b=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  pagesz=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
  vm="$(vm_stat 2>/dev/null || true)"

  # helper: match by line prefix, take last numeric token, strip punctuation
  get_pages() {
    local key="$1"
    echo "$vm" | awk -v k="$key" '
      index($0,k)==1 {
        gsub(/[^0-9]/,"",$NF);
        print $NF+0
      }'
  }

  free_p=$(get_pages "Pages free")
  inactive_p=$(get_pages "Pages inactive")
  speculative_p=$(get_pages "Pages speculative")

  # If any are empty, treat as 0 to avoid null arithmetic
  free_p=${free_p:-0}
  inactive_p=${inactive_p:-0}
  speculative_p=${speculative_p:-0}

  avail_b=$(( (free_p + inactive_p + speculative_p) * pagesz ))
  # Clamp: available cannot exceed total
  if (( avail_b > total_b )); then avail_b=$total_b; fi
  used_b=$(( total_b - avail_b ))

  echo "Total:  $(bytes_h "$total_b")"
  echo "Used:   $(bytes_h "$used_b") ($(pct "$used_b" "$total_b")%)"
  echo "Free:   $(bytes_h "$avail_b")"
}

print_memory() {
  echo "Memory"; hr
  if [[ "$OS" == "Linux" ]]; then
    print_memory_linux
  elif [[ "$OS" == "Darwin" ]]; then
    print_memory_macos
  else
    echo "Unsupported OS"
  fi
  echo
}

# ---------- Disk ----------
print_disk_linux() {
  read -r total used avail <<<"$(df -B1 -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {t+=$2; u+=$3; a+=$4} END {print t+0, u+0, a+0}')"
  echo "Total:  $(bytes_h "$total")"
  echo "Used:   $(bytes_h "$used") ($(pct "$used" "$total")%)"
  echo "Free:   $(bytes_h "$avail")"
}

print_disk_macos() {
  # Sum 1K blocks across real filesystems (skip devfs, map, autofs)
  read -r total_k used_k avail_k <<<"$(df -k 2>/dev/null \
    | awk 'NR>1 && $1 !~ /^(devfs|map|autofs)$/ {t+=$2; u+=$3; a+=$4} END {print t+0, u+0, a+0}')" || true
  total_b=$(( ${total_k:-0} * 1024 ))
  used_b=$(( ${used_k:-0}  * 1024 ))
  avail_b=$(( ${avail_k:-0} * 1024 ))
  echo "Total:  $(bytes_h "$total_b")"
  echo "Used:   $(bytes_h "$used_b") ($(pct "$used_b" "$total_b")%)"
  echo "Free:   $(bytes_h "$avail_b")"
}

print_disk() {
  echo "Disk"; hr
  if [[ "$OS" == "Linux" ]]; then
    print_disk_linux
  elif [[ "$OS" == "Darwin" ]]; then
    print_disk_macos
  else
    echo "Unsupported OS"
  fi
  echo
}

# ---------- Top processes ----------
print_top_processes_linux() {
  echo "Top 5 by CPU:"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR==1 || NR<=6 {printf "%-7s %-25s %6s %6s\n", $1, $2, $3, $4}'
  echo
  echo "Top 5 by Memory:"
  ps -eo pid,comm,%cpu,%mem --sort=-%mem | awk 'NR==1 || NR<=6 {printf "%-7s %-25s %6s %6s\n", $1, $2, $3, $4}'
}

print_top_processes_macos() {
  echo "Top 5 by CPU:"
  ps -Ao pid,comm,%cpu,%mem -r | awk 'NR==1 || NR<=6 {printf "%-7s %-30s %6s %6s\n", $1, $2, $3, $4}'
  echo
  echo "Top 5 by Memory:"
  ps -Ao pid,comm,%cpu,%mem -m | awk 'NR==1 || NR<=6 {printf "%-7s %-30s %6s %6s\n", $1, $2, $3, $4}'
}

print_top_processes() {
  echo "Top Processes"; hr
  if [[ "$OS" == "Linux" ]]; then
    print_top_processes_linux
  elif [[ "$OS" == "Darwin" ]]; then
    print_top_processes_macos
  else
    echo "Unsupported OS"
  fi
  echo
}

# ---------- Auth (optional) ----------
print_auth() {
  echo "Auth (optional)"; hr
  if [[ "$OS" == "Linux" ]]; then
    if exists lastb; then
      failed=$(lastb -n 200 2>/dev/null | grep -c -E '^[a-zA-Z0-9_.-]'); echo "Recent failed login attempts (last 200 parsed): $failed"
    else
      echo "Failed logins: 'lastb' not available"
    fi
  elif [[ "$OS" == "Darwin" ]]; then
    echo "Failed logins: use 'log show --predicate \"eventMessage CONTAINS[c] \\\"failed\\\"\" --last 1d' (may require sudo)"
  else
    echo "Failed logins: unsupported OS"
  fi
  echo
}

# ---------- main ----------
print_os_info
print_cpu
print_memory
print_disk
print_top_processes
print_auth

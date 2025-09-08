# Server Performance Stats

`server-stats.sh` is a lightweight Bash script to analyze **basic server performance stats**.  
It works on **Linux** and **macOS** using only built-in tools—no extra dependencies.

---

## Features

- **OS / Host Info**
  - OS version, kernel, hostname
  - Uptime & boot time
  - Load averages
  - Logged-in users
- **CPU Usage**
  - Total CPU utilization (sampled over 1 second)
- **Memory Usage**
  - Free vs Used, including percentage
  - Human-readable units (MB/GB)
- **Disk Usage**
  - Aggregated across all real filesystems
  - Free vs Used, including percentage
- **Top Processes**
  - Top 5 by CPU
  - Top 5 by Memory
- **Stretch Goal (Optional)**
  - Failed login attempts (Linux: via `lastb`; macOS: log command hint)

---

## Installation

Clone or copy the script:

```bash
git clone https://github.com/yourusername/Server-Performance-Stats.git
cd Server-Performance-Stats
chmod +x server-stats.sh

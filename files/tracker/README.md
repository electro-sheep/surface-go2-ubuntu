# usage-tracker

Shows what is using the machine's CPU, GPU, RAM and battery. It groups the numbers
by app, then breaks each app down by process and thread, so you can see which part
of an app needs fixing. It is a single Python file with no dependencies.

Installed by `./install.sh tracker` (part of `all`): copies it to `~/.local/bin` and starts
the background recorder.

```
usage-tracker record                  # sample every 5 s until Ctrl-C (or -d 2h)
usage-tracker report                  # last 24 h; also --since 2h / today / 14:30 / all
usage-tracker report --app firefox    # one app, with every process and thread
usage-tracker report --battery        # only time spent unplugged
usage-tracker live                    # top-like view, grouped by app
usage-tracker service install         # record in the background, every 10 s
usage-tracker service uninstall
```

Data goes to `~/.local/share/usage-tracker/usage.db` (SQLite). Data older than 14 days
is deleted (`--keep-days`).

## What it measures

| | Source | Notes |
|---|---|---|
| App | `/proc/PID/cgroup` | GNOME starts every app in its own systemd scope, so all of Firefox's or Claude's helper processes count as one app. Services and kernel threads are grouped too. |
| Process role | cmdline / comm | `Isolated Web Co`, `RDD Process`, `renderer`, `GPU process`, `python3 foo.py` … |
| CPU | `/proc/PID/stat`, `task/*/schedstat` | Per process every sample; per thread every 30 s for busy processes (counters are cumulative, so the totals stay exact). |
| Short-lived children | parent's `cutime` | CPU used by processes that start and exit between samples. top/htop never show this; it is how polling shell scripts hide. |
| Wakeups | `schedstat` timeslices | How often each thread gets scheduled. High values keep cores out of deep sleep. |
| GPU | DRM `fdinfo` (i915, amdgpu) | Engine busy time per process. |
| RAM | `smaps_rollup` PSS, every 2 min | PSS splits shared memory fairly between processes, so app totals add up. Falls back to RSS for other users' processes. |
| Graphics memory | DRM `fdinfo` `drm-resident-*` | On integrated GPUs, graphics buffers are ordinary RAM that PSS misses (GNOME Shell, browsers). Counted once per DRM client; buffers shared with another client (window contents) count half to each, like PSS. |
| Where all RAM goes | `/proc/meminfo`, zram `mm_stat` | Every sample: app memory, graphics/shared memory, compressed swap, kernel, file cache, free. |
| Disk writes | `/proc/PID/io` | Your own processes only (all processes under sudo). |
| Power | battery `current_now × voltage_now` | Only while unplugged. Run with `sudo` to also log RAPL package/platform power while charging. |
| System | `/proc/stat`, cpuidle, backlight | Busy %, time spent in deep C-states (C6+), context switches, brightness, swap. |

## Reading the report

- **Busiest minutes**: the moments the machine worked hardest, and which app
  processes were responsible.
- **Processing**: apps ranked by estimated energy when there is power data,
  otherwise by CPU + GPU time. *Energy* is the power above the idle floor, split
  between apps each interval by their CPU+GPU time, so treat it as an estimate.
  `100% CPU` = one full core.
- **Memory**: apps ranked by average RAM (process memory + graphics buffers), with the
  peak, the change over the window (steady growth suggests a leak) and how much of each app
  is in swap.
- **Where the RAM goes**: the whole machine's RAM split into apps, graphics buffers and
  shared memory, compressed swap, kernel, file cache and free.
- **Per-app breakdown**: processes, busiest threads, threads that wake most often,
  and individual PIDs. Firefox: match PIDs to tabs in `about:processes`.
- **What stands out**: automatic hints, such as software video decoding, polling
  scripts, idle apps holding RAM, swap pressure, wakeups that block deep sleep, and
  brightness.

Overhead: about 0.7% of one core at the 5 s interval, half that at 10 s.

## Comparing before and after a change

```
usage-tracker report --since "2026-10-13 09:00" --until "2026-10-13 12:00"
usage-tracker report --since "2026-10-14 09:00" --until "2026-10-14 12:00"
```

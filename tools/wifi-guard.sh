#!/bin/sh
# uwe5621 wifi guard v2  (OPTIONAL - disabled by default)
# Detects sdiohal RX stall (which later hangs the kernel and lets the hardware
# watchdog reset the box) and heals it with recover-wifi.sh.
# Because it unloads modules, prefer the conservative keepalive timer.
set -u
CONF=/etc/uwe5621.conf
[ -r "$CONF" ] && . "$CONF"
: "${UWE_WLAN_IF:=wlan0}"
: "${UWE_PRIMARY_SSID:=}"
: "${UWE_GATEWAY:=192.168.1.1}"

LOG=/var/log/uwe-wifi-guard.log
OFF=/opt/uwe5621/guard.off
PROFILE="${UWE_PROFILE:-$UWE_PRIMARY_SSID}"
GATEWAY="${UWE_GATEWAY}"
IF="$UWE_WLAN_IF"
INTERVAL=10

[ -n "$PROFILE" ] || { echo "ERROR: set UWE_PRIMARY_SSID in $CONF"; exit 1; }

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }
np_count() { dmesg 2>/dev/null | grep -c 'RX no progress'; }
assoc_bssid() { iw dev "$IF" link 2>/dev/null | sed -n 's/^Connected to \([0-9a-fA-F:]*\).*/\1/p'; }
pending() { dmesg 2>/dev/null | grep 'RX no progress' | tail -1 | sed 's/.*pending=\([0-9]*\).*/\1/'; }
uptime_s() { cut -d. -f1 /proc/uptime; }

log "guard v2 start pid=$$"
sleep 45                      # let uwe5621-wifi.service bring the stack up first

last_np=$(np_count)
last_bssid=""
fails=0
heals=0
heal_window_start=$(date +%s)

while : ; do
    sleep $INTERVAL

    if [ -f "$OFF" ]; then
        fails=0; last_np=$(np_count); continue
    fi
    if [ -f /tmp/uwe-wifi-guard.stop ]; then
        log "stop flag seen, exiting"; rm -f /tmp/uwe-wifi-guard.stop; exit 0
    fi
    # fresh boot: baseline silently
    if [ "$(uptime_s)" -lt 180 ]; then
        last_np=$(np_count); last_bssid=""; continue
    fi

    now_np=$(np_count)
    if [ "$now_np" -lt "$last_np" ]; then
        log "dmesg counter reset ($last_np -> $now_np), re-baseline (reboot?)"
        last_np=$now_np; last_bssid=""; fails=0; continue
    fi

    if [ ! -d "/sys/class/net/$IF" ]; then
        fails=$((fails+1))
        log "$IF absent (fail#=$fails)"
        if [ $fails -ge 3 ]; then
            sh /opt/uwe5621/recover-wifi.sh >> "$LOG" 2>&1
            last_np=$(np_count); fails=0
        fi
        continue
    fi

    bssid=$(assoc_bssid)
    if [ -z "$bssid" ]; then
        fails=$((fails+1))
        if [ $fails -ge 3 ]; then
            log "unassociated x3 -> reconnect"
            nmcli connection up "$PROFILE" >> "$LOG" 2>&1
            fails=0; last_np=$(np_count)
        fi
        continue
    fi
    [ "$bssid" != "$last_bssid" ] && { log "associated bssid=$bssid"; last_bssid=$bssid; }

    if [ "$now_np" != "$last_np" ]; then
        # rate limit: at most 4 heals per hour
        now=$(date +%s)
        if [ $((now - heal_window_start)) -gt 3600 ]; then heal_window_start=$now; heals=0; fi
        heals=$((heals+1))
        if [ "$heals" -gt 4 ]; then
            log "RX stall again but heal budget exhausted ($heals/h) - backing off 10min"
            log "$(dmesg -T | grep -v 'RX no progress' | tail -8)"
            sleep 600; last_np=$(np_count); continue
        fi
        log "RX stall: no-progress $last_np -> $now_np, pending=$(pending), bssid=$bssid (heal#$heals)"
        dmesg -T | grep -v 'RX no progress' | grep -v 'sdiohal_rx_drain_next' | tail -10 >> "$LOG"
        sh /opt/uwe5621/recover-wifi.sh >> "$LOG" 2>&1
        sleep 8
        i=0
        while [ $i -lt 12 ]; do
            i=$((i+1))
            ping -c1 -W1 -I "$IF" "$GATEWAY" >/dev/null 2>&1 && break
            sleep 2
        done
        if ping -c1 -W1 -I "$IF" "$GATEWAY" >/dev/null 2>&1; then
            log "heal ok, bssid=$(assoc_bssid)"
        else
            log "heal done but gateway unreachable, nmcli con up"
            nmcli connection up "$PROFILE" >> "$LOG" 2>&1
        fi
        last_np=$(np_count); last_bssid=""; fails=0
        continue
    fi

    if ping -c1 -W1 -I "$IF" "$GATEWAY" >/dev/null 2>&1; then
        fails=0
    else
        fails=$((fails+1))
        [ $fails -eq 1 ] && log "gateway ping miss (bssid=$bssid)"
        if [ $fails -ge 6 ]; then
            log "gateway unreachable 6x -> reconnect"
            nmcli connection up "$PROFILE" >> "$LOG" 2>&1
            fails=0
        fi
    fi
done

#!/bin/bash
# Raccolta delle configurazioni dell'infrastruttura nel repo git cifrato.
#
# Idempotente: puo' girare quante volte si vuole. Committa e pusha solo se
# qualcosa e' realmente cambiato, per non generare rumore inutile e scritture
# a vuoto sulla eMMC.
#
# NON raccoglie chiavi private: /etc/pve/priv/ e ogni *.key sono esclusi per
# scelta esplicita (rigenerabili in pochi minuti, quindi il valore di backup
# non giustifica il rischio di portarle fuori casa). Vedi decisions.md.

set -uo pipefail

REPO=/root/infra
PVE="$REPO/hosts/pve"
STATE="$PVE/state"

log() { printf '  %s\n' "$*"; }

cd "$REPO" || exit 1

# ---------------------------------------------------------------- host PVE
log "host pve: configurazioni"
rm -rf "$PVE/etc" "$STATE"
mkdir -p "$PVE/etc" "$STATE"

# /etc/pve — cluster filesystem, senza chiavi private ne' stato runtime
rsync -a \
  --exclude 'priv/' \
  --exclude '*.key' \
  --exclude '.*' \
  --exclude 'lrm_status' \
  /etc/pve/ "$PVE/etc/pve/" 2>/dev/null

# file di sistema utili a ricostruire la macchina
for f in /etc/network/interfaces /etc/hosts /etc/hostname /etc/fstab \
         /etc/resolv.conf /etc/apt/sources.list; do
  [ -f "$f" ] && install -D -m 600 "$f" "$PVE$f"
done
for d in /etc/apt/sources.list.d /etc/cron.d /etc/modprobe.d; do
  [ -d "$d" ] && mkdir -p "$PVE$d" && cp -a "$d"/. "$PVE$d/" 2>/dev/null
done

# ------------------------------------------------------- stato strutturale
# Solo informazioni stabili: niente percentuali di riempimento, uptime o
# contatori, altrimenti ogni esecuzione produrrebbe un commit fasullo.
log "host pve: stato strutturale"
pveversion -v                                        > "$STATE/pveversion.txt" 2>/dev/null
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT            > "$STATE/lsblk.txt"      2>/dev/null
lvs -o lv_name,vg_name,lv_size,lv_attr --units g     > "$STATE/lvs.txt"        2>/dev/null
vgs -o vg_name,vg_size,vg_free --units g             > "$STATE/vgs.txt"        2>/dev/null
dpkg --get-selections                                > "$STATE/packages.txt"   2>/dev/null
ip -o addr show | awk '{print $2, $3, $4}'           > "$STATE/ip-addr.txt"    2>/dev/null
ip route                                             > "$STATE/ip-route.txt"   2>/dev/null

# ------------------------------------------------------------------ guest
log "guest: definizioni VM e container"
mkdir -p "$REPO/guests/haos" "$REPO/guests/adguard"
qm config 100  > "$REPO/guests/haos/vm-100.conf"     2>/dev/null
pct config 101 > "$REPO/guests/adguard/ct-101.conf"  2>/dev/null

# AdGuard: il file contiene hash della password admin e upstream DNS.
# Finisce cifrato come tutto il resto.
if pct status 101 2>/dev/null | grep -q running; then
  pct pull 101 /opt/AdGuardHome/AdGuardHome.yaml \
      "$REPO/guests/adguard/AdGuardHome.yaml" 2>/dev/null \
    && log "guest: AdGuardHome.yaml raccolto" \
    || log "guest: AdGuardHome.yaml NON raccolto"
else
  log "guest: container 101 non in esecuzione, AdGuard saltato"
fi

# ---------------------------------------------------------------- routers
# Richiedono la chiave ed25519 autorizzata sul nodo. Finche' non c'e',
# il passo viene saltato senza far fallire la raccolta.
for node in router-master; do
  dest="$REPO/hosts/$node"
  mkdir -p "$dest"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true 2>/dev/null; then
    log "$node: raccolgo /etc/config"
    rm -rf "$dest/etc"; mkdir -p "$dest/etc/config"
    ssh -o BatchMode=yes "$node" 'tar -C /etc -cf - config' 2>/dev/null \
      | tar -C "$dest/etc" -xf - 2>/dev/null
    ssh -o BatchMode=yes "$node" 'cat /etc/dhcp.leases' \
      > "$dest/dhcp.leases" 2>/dev/null
  else
    log "$node: NON raggiungibile via SSH, saltato"
  fi
done

# ------------------------------------------------------------ commit/push
if [ -z "$(git status --porcelain)" ]; then
  log "nessuna modifica, niente commit"
  exit 0
fi

git add -A
git commit -q -m "Raccolta automatica configurazioni $(date +%Y-%m-%d\ %H:%M)"
log "commit creato"

# SKIP_PUSH=1 ferma qui: serve per verificare la cifratura in locale prima di
# mandare qualsiasi cosa fuori casa.
if [ "${SKIP_PUSH:-0}" = "1" ]; then
  log "SKIP_PUSH attivo — commit locale, nessun push"
  exit 0
fi

if git push -q origin main 2>/dev/null; then
  log "pushato su GitHub"
else
  log "PUSH FALLITO — il commit resta locale"
  exit 1
fi

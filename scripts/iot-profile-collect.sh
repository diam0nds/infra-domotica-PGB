#!/bin/bash
# Campiona il traffico in uscita della VLAN IoT verso internet.
#
# GIRA SUL PVE, non sul router: interroga il router in sola lettura via SSH.
# Motivo: nessuna modifica al router, nessuna scrittura sulla sua flash, e il
# cron sta dove abbiamo pieno controllo.
#
# Limite noto: se il PVE e' spento il campionamento si interrompe. Per una
# finestra di 7 giorni e' accettabile.
#
# Scrive una riga per ogni combinazione (dispositivo, destinazione, porta) vista
# in questo istante, deduplicata. Volume stimato: ~1 KB per campionamento.

set -uo pipefail
export LC_ALL=C

DATA=/var/log/iot-profile.tsv
IOT_PREFIX="192.168\.16\."
TS=$(date +%Y-%m-%dT%H:%M)

# intestazione alla prima esecuzione
[ -f "$DATA" ] || echo -e "timestamp\tsrc\tdst\tproto\tdport" > "$DATA"

ssh -o BatchMode=yes -o ConnectTimeout=10 router-master \
    'cat /proc/net/nf_conntrack' 2>/dev/null |
awk -v ts="$TS" -v pre="$IOT_PREFIX" '
  {
    proto=""; src=""; dst=""; dport=""
    for (i=1; i<=NF; i++) {
      if ($i == "tcp" || $i == "udp" || $i == "icmp") { if (proto=="") proto=$i }
      if ($i ~ /^src=/ && src=="")   { split($i,a,"="); src=a[2] }
      if ($i ~ /^dst=/ && dst=="")   { split($i,a,"="); dst=a[2] }
      if ($i ~ /^dport=/ && dport=="") { split($i,a,"="); dport=a[2] }
    }
    # solo sorgenti IoT, solo destinazioni pubbliche
    if (src !~ "^" pre) next
    if (dst ~ /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|224\.|255\.)/) next
    if (dst == "" || dport == "") next
    print ts "\t" src "\t" dst "\t" proto "\t" dport
  }
' | sort -u >> "$DATA"

# nessun output se va tutto bene: il cron non deve generare rumore
exit 0

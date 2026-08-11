#!/bin/bash
# Fotografia dei client WiFi su tutti i nodi, identificati per NOME.
#
# PERCHE' ESISTE
# Confrontare i conteggi di stazioni prima e dopo una modifica non basta: 16
# stazioni prima e 16 dopo possono essere insiemi diversi. Il 2026-08-11 questo
# ha mascherato per un momento la caduta di tre climatizzatori.
#
# Uso:
#   wifi-clients.sh              elenco corrente, ordinato e confrontabile
#   wifi-clients.sh > /tmp/prima
#   ...modifica...
#   diff /tmp/prima <(wifi-clients.sh)

set -uo pipefail
export LC_ALL=C

NODI="router-master router-ap"
MAPPA=/tmp/wifi-clients-nomi.txt

# mappa MAC -> nome, dai lease statici e dinamici del master
ssh -o BatchMode=yes router-master '
  i=0
  while true; do
    n=$(uci get dhcp.@host[$i].name 2>/dev/null) || break
    m=$(uci get dhcp.@host[$i].mac 2>/dev/null)
    echo "$m $n"
    i=$((i+1))
  done
  awk "{print \$2, \$4}" /tmp/dhcp.leases 2>/dev/null
' 2>/dev/null | tr 'A-Z' 'a-z' | sort -u > "$MAPPA" || : > "$MAPPA"

nome() { grep -m1 "^$1 " "$MAPPA" 2>/dev/null | cut -d' ' -f2- || true; }

for N in $NODI; do
  ssh -o BatchMode=yes "$N" '
    for i in $(iw dev 2>/dev/null | awk "/Interface/{print \$2}"); do
      S=$(iw dev $i info 2>/dev/null | awk "/ssid/{print \$2}")
      [ -z "$S" ] && continue
      iw dev $i station dump 2>/dev/null | awk -v s="$S" "
        /^Station/ {mac=\$2}
        /signal:/  {if (mac!=\"\") {print s, mac, \$2; mac=\"\"}}
      "
    done
  ' 2>/dev/null | while read -r ssid mac sig; do
    printf "%-10s %-30s %-18s %s dBm\n" "$ssid" "$(nome "$(echo "$mac" | tr 'A-Z' 'a-z')" || true)" "$mac" "$sig"
  done
done | sed 's/  */ /g' | sort

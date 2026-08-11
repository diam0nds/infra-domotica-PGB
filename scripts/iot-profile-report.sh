#!/bin/bash
# Aggrega i campionamenti di iot-profile-collect.sh in un profilo per dispositivo.
#
# Serve a decidere, con dati alla mano, quali dispositivi possono essere tagliati
# fuori da internet e quali no. Senza questo, passare a default-deny sull'uscita
# e' un tiro al buio: la dipendenza dal cloud si scoprirebbe quando il
# climatizzatore non risponde piu'.

set -uo pipefail
export LC_ALL=C

DATA=/var/log/iot-profile.tsv
NOMI=/tmp/iot-profile-nomi.txt
RDNS=/tmp/iot-profile-rdns.txt

[ -f "$DATA" ] || { echo "Nessun dato: $DATA non esiste. Eseguire prima il collector."; exit 1; }

# mappa IP -> nome dai lease statici del router (una volta per esecuzione)
ssh -o BatchMode=yes router-master '
  i=0
  while true; do
    n=$(uci get dhcp.@host[$i].name 2>/dev/null) || break
    ip=$(uci get dhcp.@host[$i].ip 2>/dev/null)
    echo "$ip $n"
    i=$((i+1))
  done
  awk "{print \$3, \$4}" /tmp/dhcp.leases 2>/dev/null
' 2>/dev/null | sort -u > "$NOMI" || : > "$NOMI"

nome_di() { grep -m1 "^$1 " "$NOMI" 2>/dev/null | cut -d" " -f2- || true; }

# cache dei reverse DNS: evita di ripetere le stesse query a ogni report
[ -f "$RDNS" ] || : > "$RDNS"
rdns_di() {
  local ip="$1" r
  r=$(grep -m1 "^$ip " "$RDNS" 2>/dev/null | cut -d" " -f2-)
  if [ -z "$r" ]; then
    r=$(dig +short +time=2 +tries=1 -x "$ip" @1.1.1.1 2>/dev/null | head -1)
    [ -z "$r" ] && r="-"
    echo "$ip $r" >> "$RDNS"
  fi
  echo "$r"
}

CAMPIONI=$(awk 'NR>1 {print $1}' "$DATA" | sort -u | wc -l)
PRIMO=$(awk 'NR>1 {print $1}' "$DATA" | sort | head -1)
ULTIMO=$(awk 'NR>1 {print $1}' "$DATA" | sort | tail -1)

echo "=== PROFILO TRAFFICO IoT ==="
echo "  campionamenti: $CAMPIONI    dal $PRIMO al $ULTIMO"
echo

# elenco dispositivi ordinato per ultimo ottetto
for src in $(awk 'NR>1 {print $2}' "$DATA" | sort -u -t. -k4 -n); do
  N=$(nome_di "$src")
  CONTATTI=$(awk -v s="$src" 'NR>1 && $2==s {print $3}' "$DATA" | sort -u | wc -l)
  VISTO=$(awk -v s="$src" 'NR>1 && $2==s {print $1}' "$DATA" | sort -u | wc -l)
  PERC=$(( CAMPIONI > 0 ? VISTO * 100 / CAMPIONI : 0 ))

  printf "%-16s %-30s destinazioni:%-4s presente nel %s%% dei campioni\n" \
    "$src" "${N:-<non censito>}" "$CONTATTI" "$PERC"

  awk -v s="$src" 'NR>1 && $2==s {print $3, $4, $5}' "$DATA" | sort | uniq -c | sort -rn | head -6 |
  while read -r n dst proto dport; do
    printf "     %5s volte  %-16s %s/%-6s %s\n" "$n" "$dst" "$proto" "$dport" "$(rdns_di "$dst")"
  done
  echo
done

echo "=== LETTURA ==="
echo "  presente nel ~100% dei campioni  -> connessione permanente al cloud"
echo "  presente in pochi campioni       -> contatti sporadici (aggiornamenti, telemetria)"
echo "  assente da questo elenco         -> nessun traffico verso internet: candidato al blocco"

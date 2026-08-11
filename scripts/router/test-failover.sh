#!/bin/bash
# Test end-to-end del watchdog DNS.
# Il riavvio del container e' garantito da un trap, anche se il test viene
# interrotto a metà.

R=192.168.15.1
AG=192.168.15.3
SSH="ssh -o BatchMode=yes router-master"

ripristina() {
  if ! pct status 101 2>/dev/null | grep -q running; then
    echo
    echo "  [RIPRISTINO] riavvio container 101..."
    pct start 101 2>/dev/null
    for i in $(seq 1 20); do ping -c1 -W1 "$AG" >/dev/null 2>&1 && break; sleep 2; done
    echo "  container 101: $(pct status 101 2>/dev/null | awk '{print $2}')"
  fi
}
trap ripristina EXIT INT TERM

upstream() { $SSH 'tr "\n" " " < /tmp/dnsmasq-upstreams 2>/dev/null' 2>/dev/null; }

risolve() {
  local out ms
  out=$(dig +tries=1 +time=4 @"$R" "chk$RANDOM.wikipedia.org" 2>/dev/null)
  if echo "$out" | grep -qE 'status: (NOERROR|NXDOMAIN)'; then
    ms=$(echo "$out" | grep -oE 'Query time: [0-9]+' | awk '{print $3}')
    echo "SI(${ms}ms)"
  else
    echo "NO"
  fi
}

filtra() {
  dig +short +tries=1 +time=4 @"$R" doubleclick.net 2>/dev/null | grep -q . \
    && echo "no" || echo "SI"
}

echo "=== T0 — BASELINE ==="
echo "  upstream: $(upstream)"
echo "  risolve:  $(risolve)"
echo "  filtra:   $(filtra)"

echo
echo "=== SPENGO ADGUARD (simulo PVE giu) ==="
pct shutdown 101 >/dev/null 2>&1
sleep 5
echo "  container 101: $(pct status 101 2>/dev/null | awk '{print $2}')"

echo
echo "=== ATTESA COMMUTAZIONE (max 4 min) ==="
commutato=0
for i in $(seq 1 12); do
  sleep 20
  u=$(upstream)
  printf "  +%3ds  upstream:%-26s risolve:%s\n" "$((i*20))" "$u" "$(risolve)"
  case "$u" in *1.1.1.1*) commutato=$((i*20)); break ;; esac
done

echo
if [ "$commutato" -gt 0 ]; then
  echo "  >>> COMMUTATO dopo ~${commutato}s"
else
  echo "  >>> NON HA COMMUTATO entro 4 minuti"
fi

echo
echo "=== VERIFICA IN STATO DEGRADATO ==="
ok=0
for i in 1 2 3 4 5; do
  r=$(risolve); case "$r" in SI*) ok=$((ok+1)) ;; esac
  printf "  query %d: %s\n" "$i" "$r"
done
echo "  risolte: $ok/5"
echo "  filtra:  $(filtra)   (atteso: no — filtro sospeso)"

echo
echo "=== RIACCENDO ADGUARD ==="
pct start 101 >/dev/null 2>&1
for i in $(seq 1 25); do ping -c1 -W1 "$AG" >/dev/null 2>&1 && break; sleep 2; done
echo "  container 101: $(pct status 101 2>/dev/null | awk '{print $2}')"

echo
echo "=== ATTESA RIENTRO (max 3 min) ==="
rientrato=0
for i in $(seq 1 9); do
  sleep 20
  u=$(upstream)
  printf "  +%3ds  upstream:%-26s filtra:%s\n" "$((i*20))" "$u" "$(filtra)"
  case "$u" in *192.168.15.3*) rientrato=$((i*20)); break ;; esac
done

echo
[ "$rientrato" -gt 0 ] && echo "  >>> RIENTRATO dopo ~${rientrato}s" \
                       || echo "  >>> NON RIENTRATO entro 3 minuti"

echo
echo "=== STATO FINALE ==="
echo "  upstream: $(upstream)"
echo "  risolve:  $(risolve)"
echo "  filtra:   $(filtra)"

echo
echo "=== LOG DEL WATCHDOG ==="
$SSH 'logread -e dns-watchdog 2>/dev/null | tail -6' 2>/dev/null | sed 's/^/  /'

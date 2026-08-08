#!/bin/sh
# DNS watchdog per il router OpenWrt.
#
# PROBLEMA CHE RISOLVE
# dnsmasq non sa accorgersi che un upstream e' morto: continua a interrogarlo
# e resta in attesa, lasciando la casa senza risoluzione DNS. Misurato il
# 2026-08-08: con AdGuard spento, 0 query su 5 risolte.
#
# COME FUNZIONA
# Ogni minuto verifica se AdGuard risponde.
#   risponde     -> AdGuard e' l'unico upstream. Filtraggio al 100%.
#   non risponde -> viene sostituito dal resolver pubblico. La casa naviga.
#   torna su     -> viene rimesso al suo posto.
#
# La lista degli upstream sta in un file in RAM (/tmp) che dnsmasq rilegge a
# ogni SIGHUP: nessun riavvio del servizio e nessuna scrittura sulla flash,
# che su questi router e' un bene di consumo.
#
# INSTALLAZIONE: vedi scripts/router/README-watchdog.md nel repo.
# La fonte di verita' e' il repo git, non il router: se il router viene
# riflashato, si ridistribuisce da li'.

ADGUARD=192.168.15.3
FALLBACK=1.1.1.1
PROBE=openwrt.org              # dominio usato per la verifica
SERVERSFILE=/tmp/dnsmasq-upstreams
STATEFILE=/tmp/dns-watchdog.state
SOGLIA=2                       # fallimenti consecutivi prima di commutare

# ---------------------------------------------------------------------------

imposta_upstream() {
  # $@ = elenco di server, nell'ordine desiderato
  : > "$SERVERSFILE"
  for s in "$@"; do echo "server=$s" >> "$SERVERSFILE"; done
  kill -HUP "$(pidof dnsmasq)" 2>/dev/null
}

# Stato precedente. Al primo avvio, o dopo un riavvio del router (/tmp e' in
# RAM e viene azzerato), si riparte sempre dal fallback: meglio partire senza
# filtro che partire senza DNS.
if [ -f "$STATEFILE" ]; then
  read -r STATO FALLIMENTI < "$STATEFILE"
else
  STATO=sconosciuto
  FALLIMENTI=0
fi
[ -f "$SERVERSFILE" ] || imposta_upstream "$FALLBACK"

# ---------------------------------------------------------------------------

if timeout 4 nslookup "$PROBE" "$ADGUARD" >/dev/null 2>&1; then
  FALLIMENTI=0
  if [ "$STATO" != "attivo" ]; then
    imposta_upstream "$ADGUARD"
    logger -t dns-watchdog "AdGuard risponde: torna unico upstream, filtraggio riattivato"
    STATO=attivo
  fi
else
  FALLIMENTI=$((FALLIMENTI + 1))
  if [ "$FALLIMENTI" -ge "$SOGLIA" ] && [ "$STATO" != "degradato" ]; then
    imposta_upstream "$FALLBACK"
    logger -t dns-watchdog "AdGuard non risponde da $FALLIMENTI verifiche: ripiego su $FALLBACK, filtraggio SOSPESO"
    STATO=degradato
  fi
fi

echo "$STATO $FALLIMENTI" > "$STATEFILE"

#!/bin/sh
# safe-change.sh — modifiche di configurazione con ripristino automatico.
#
# PERCHE' ESISTE
# Questi router stanno in una casa dove nessuno mette piede per settimane. Una
# regola firewall sbagliata, o un ifdown sull'interfaccia da cui si e'
# collegati, taglia l'accesso e non c'e' modo di rimediare da remoto. Il
# ripristino va quindi armato PRIMA di toccare qualsiasi cosa, e disarmato solo
# dopo aver verificato che si e' ancora dentro.
#
# E' il classico interruttore dell'uomo morto: se chi ha fatto la modifica non
# torna a confermare entro il tempo previsto, la configurazione si ripristina
# da sola.
#
# USO
#   safe-change.sh arm firewall 300     salva /etc/config/firewall e pianifica
#                                       il ripristino fra 300 secondi
#   ...si applica la modifica e si verifica...
#   safe-change.sh confirm firewall     tutto ok: annulla il ripristino
#   safe-change.sh revert firewall      ripristina subito
#   safe-change.sh status               cosa c'e' armato in questo momento
#
# NOTA sul pacchetto 'network': il ripristino rimette il file ma NON riavvia la
# rete, perche' un riavvio globale farebbe cadere la sessione. Va fatto un
# ifdown/ifup mirato sulla singola interfaccia toccata.

set -u

DIR=/tmp/safe-change
mkdir -p "$DIR"

servizio_per_pacchetto() {
  case "$1" in
    firewall)  echo "/etc/init.d/firewall restart" ;;
    dhcp)      echo "/etc/init.d/dnsmasq restart" ;;
    wireless)  echo "wifi reload" ;;
    system)    echo "/etc/init.d/system reload" ;;
    dropbear)  echo "/etc/init.d/dropbear restart" ;;
    uhttpd)    echo "/etc/init.d/uhttpd restart" ;;
    network)   echo "" ;;   # deliberatamente vuoto: vedi nota sopra
    *)         echo "" ;;
  esac
}

case "${1:-}" in

  arm)
    PKG="${2:?serve il nome del pacchetto, es. firewall}"
    SEC="${3:-300}"
    [ -f "/etc/config/$PKG" ] || { echo "ERRORE: /etc/config/$PKG non esiste"; exit 1; }

    if [ -f "$DIR/$PKG.pid" ] && kill -0 "$(cat "$DIR/$PKG.pid")" 2>/dev/null; then
      echo "ERRORE: c'e' gia un ripristino armato per '$PKG'. Prima confirm o revert."
      exit 1
    fi

    cp "/etc/config/$PKG" "$DIR/$PKG.bak"
    SVC=$(servizio_per_pacchetto "$PKG")

    # timer di ripristino in background
    (
      sleep "$SEC"
      cp "$DIR/$PKG.bak" "/etc/config/$PKG"
      [ -n "$SVC" ] && $SVC >/dev/null 2>&1
      logger -t safe-change "RIPRISTINO AUTOMATICO di $PKG: nessuna conferma entro ${SEC}s"
      rm -f "$DIR/$PKG.pid"
    ) &
    echo $! > "$DIR/$PKG.pid"

    echo "armato: $PKG  —  ripristino automatico fra ${SEC}s"
    echo "backup: $DIR/$PKG.bak"
    [ -z "$SVC" ] && echo "ATTENZIONE: per '$PKG' il ripristino non riavvia il servizio, serve ifdown/ifup mirato"
    ;;

  confirm)
    PKG="${2:?serve il nome del pacchetto}"
    if [ -f "$DIR/$PKG.pid" ]; then
      kill "$(cat "$DIR/$PKG.pid")" 2>/dev/null
      rm -f "$DIR/$PKG.pid"
      logger -t safe-change "modifica di $PKG confermata, ripristino annullato"
      echo "confermato: $PKG — ripristino annullato, backup conservato in $DIR/$PKG.bak"
    else
      echo "nessun ripristino armato per '$PKG'"
    fi
    ;;

  revert)
    PKG="${2:?serve il nome del pacchetto}"
    [ -f "$DIR/$PKG.bak" ] || { echo "ERRORE: nessun backup per '$PKG'"; exit 1; }
    [ -f "$DIR/$PKG.pid" ] && { kill "$(cat "$DIR/$PKG.pid")" 2>/dev/null; rm -f "$DIR/$PKG.pid"; }
    cp "$DIR/$PKG.bak" "/etc/config/$PKG"
    SVC=$(servizio_per_pacchetto "$PKG")
    [ -n "$SVC" ] && $SVC >/dev/null 2>&1
    logger -t safe-change "ripristino manuale di $PKG"
    echo "ripristinato: $PKG"
    [ -z "$SVC" ] && echo "ATTENZIONE: servizio non riavviato, serve ifdown/ifup mirato"
    ;;

  status)
    trovato=0
    for p in "$DIR"/*.pid; do
      [ -e "$p" ] || continue
      PKG=$(basename "$p" .pid)
      if kill -0 "$(cat "$p")" 2>/dev/null; then
        echo "  ARMATO: $PKG (ripristino in attesa)"
        trovato=1
      else
        rm -f "$p"
      fi
    done
    [ "$trovato" = 0 ] && echo "  nulla armato"
    ;;

  *)
    echo "uso: $0 {arm <pkg> [sec] | confirm <pkg> | revert <pkg> | status}"
    exit 1
    ;;
esac

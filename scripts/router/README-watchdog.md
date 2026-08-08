# DNS watchdog — installazione e ripristino

La **fonte di verità è questo repo**, non il router. Se il router viene
riflashato o sostituito, si ridistribuisce da qui: nulla va perso.

## Installazione da zero

Dal PVE, con `dns-watchdog.sh` presente nel repo:

```bash
scp /root/infra/scripts/router/dns-watchdog.sh router-master:/usr/bin/dns-watchdog
ssh router-master 'chmod +x /usr/bin/dns-watchdog'
```

Poi sul router, tre cose in sequenza:

```sh
# 1. dnsmasq legge gli upstream dal file in RAM, non piu' da uci
uci -q delete dhcp.@dnsmasq[0].server
uci set dhcp.@dnsmasq[0].serversfile='/tmp/dnsmasq-upstreams'
uci commit dhcp

# 2. il watchdog gira ogni minuto, e anche all'avvio
#    (/tmp e' in RAM: dopo un reboot il file va ricreato subito)
grep -q dns-watchdog /etc/crontabs/root 2>/dev/null || \
  echo '* * * * * /usr/bin/dns-watchdog' >> /etc/crontabs/root
/etc/init.d/cron restart

grep -q dns-watchdog /etc/rc.local 2>/dev/null || \
  sed -i 's|^exit 0|/usr/bin/dns-watchdog\nexit 0|' /etc/rc.local

# 3. sopravvive agli aggiornamenti firmware
grep -q dns-watchdog /etc/sysupgrade.conf 2>/dev/null || \
  echo '/usr/bin/dns-watchdog' >> /etc/sysupgrade.conf

# 4. prima esecuzione
/usr/bin/dns-watchdog && cat /tmp/dnsmasq-upstreams
```

## Verifica

```sh
logread -e dns-watchdog        # cronologia delle commutazioni
cat /tmp/dnsmasq-upstreams     # upstream attivo in questo momento
cat /tmp/dns-watchdog.state    # stato e conteggio fallimenti
```

Prova di failover reale, dal PVE:

```bash
pct shutdown 101 && sleep 90
dig +short @192.168.15.1 github.com     # deve rispondere
pct start 101 && sleep 90
dig @192.168.15.1 doubleclick.net       # deve tornare NXDOMAIN
```

## Perché non basta il backup di `/etc/config`

Questo script sta in `/usr/bin`, il suo cron in `/etc/crontabs/root`, e il
richiamo all'avvio in `/etc/rc.local`. **Nessuno dei tre è in `/etc/config`.**
Per questo `collect-configs.sh` raccoglie esplicitamente anche quei percorsi,
oltre a `authorized_keys`, `sysupgrade.conf` e l'elenco dei pacchetti
installati — tutto ciò che serve per ricostruire un router da un firmware
vergine.

## Comportamento atteso

| Situazione | Upstream | Filtraggio |
|---|---|---|
| AdGuard risponde | `192.168.15.3` | attivo |
| AdGuard muto da 2 verifiche (~2 min) | `1.1.1.1` | **sospeso** |
| AdGuard torna | `192.168.15.3` | riattivato |
| Router appena riavviato | `1.1.1.1` finché il watchdog non gira | sospeso |

L'ultima riga è deliberata: dopo un reboot si parte dal fallback. Meglio
partire senza filtro che partire senza DNS.

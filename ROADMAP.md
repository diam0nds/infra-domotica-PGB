# Roadmap

Lavori concordati con l'utente, in ordine di priorità. Le voci completate
restano qui con la data, così si vede cosa è già stato fatto e quando.

> **Contesto**: questa è la domotica di una **seconda casa**, sito remoto e non
> presidiato per settimane. La destinazione finale è agganciarla alla domotica
> della casa principale, che non è ancora stata analizzata.

---

## ✅ Fatto

### Backup cifrato delle configurazioni su GitHub — 2026-08-08
Repo privato `diam0nds/infra-domotica-PGB`, git-crypt in logica fail-safe,
cron giornaliero alle 04:30, verifica della cifratura come cancello pre-push.
Dettagli in `README.md`, motivazioni in `decisions.md`.

---

### Accesso SSH ai due router — 2026-08-08
`ssh router-master` (192.168.15.1) e `ssh router-ap` (192.168.15.2) dal PVE,
chiave dedicata `id_ed25519_infra`. Backup di entrambi operativo.

### Secondo router individuato — 2026-08-08
Non era un problema di indirizzi: era acceso ma **fuori dalla rete** (mesh a
0 peer, nessun cavo). Ora a `192.168.15.2`, è un **SIM SIMAX1800T** con
OpenWrt 24.10.0 — più recente del master. Dumb AP puro, trasparente per il DNS.

### Rotazione chiavi WireGuard — 2026-08-08
Le due private key del master erano state esposte per un mio errore di
redazione. Entrambe rigenerate, i 3 client road-warrior e OPNsense aggiornati,
tunnel site-to-site verificato funzionante.

### Filtraggio DNS riparato — 2026-08-08
Misurato: AdGuard vedeva solo il **7%** delle query, il resto usciva verso
resolver pubblici senza filtro. Tre cause (`noresolv` mancante, `strictorder`
mancante, un upstream morto). Corretto: ora **100%** delle query passa da
AdGuard. Dettagli e trappole in `README.md`.

### Watchdog DNS — 2026-08-08
Installato `/usr/bin/dns-watchdog` sul master (fonte in
`scripts/router/dns-watchdog.sh`), cron al minuto, in `sysupgrade.conf`.
Riduce la finestra di disservizio da 8-14 giorni a ~2 minuti.

### Backup dei router completato — 2026-08-08
Raccoglieva solo `/etc/config`: si sarebbero persi script custom, cron,
`authorized_keys`, `sysupgrade.conf` e l'elenco pacchetti. Ora tutto incluso.

---

### Il DNS è chiuso — verificato il 2026-08-11
Test di failover completo superato: commutazione dopo ~60 s, 5/5 query risolte
in stato degradato, rientro automatico dopo ~40 s. Dettagli in `README.md`.

Due strascichi minori, non bloccanti:
- finestra di ~60 s senza DNS dopo un guasto (tempo di rilevamento). Riducibile,
  ma con più rischio di falsi positivi: per ora si lascia così.
- `10.9.0.1` rimosso dagli upstream perché non risponde alle query. Andrebbe
  capito su OPNsense se lì doveva esserci un resolver: vedi punto 2.

---

## In coda — priorità concordate con l'utente il 2026-08-11

### VPN risolte — 2026-08-11
Entrambe funzionanti. `wg0` aveva la chiave del server sbagliata nel config del
client; la site-to-site era bloccata dalla porta locale 51821 (cambiata a
51900). Dettagli e trappole in `README.md`.

**Rifiniture rimaste, non urgenti:**
- Aggiornare l'endpoint del nostro peer su OPNsense da `:51821` a `:51900`, così
  anche la casa principale può iniziare il tunnel. Oggi sale solo perché lo
  iniziamo noi.
- Aggiungere `192.168.16.0/24` (IoT) agli allowed IPs del nostro peer su
  OPNsense: senza, dalla casa principale non si raggiunge la domotica di qui.
- Rimuovere la regola `firewall.@redirect[1]` (`WG-s2S`): fa DNAT di UDP 51821
  verso `10.10.10.2`, che è il router stesso. Ora è anche riferita a una porta
  non più in uso. È peso morto che confonde.
- Chiarire l'inoltro su UDP 51821 sul router del provider, che è la causa
  probabile del blocco. Finché non è chiarito, **non riusare quella porta**.

### 1. ~~VPN: nessuna delle due funziona~~ — RISOLTO, vedi sopra
L'utente riferisce che non funzionano né la VPN client né la site-to-site, e le
chiama "OpenVPN". **Verificato: OpenVPN non è installato da nessuna parte** —
né router master, né AP, né PVE, né container. Le VPN configurate sono due,
entrambe **WireGuard**:

| Interfaccia | Porta | Ruolo | Stato osservato |
|---|---|---|---|
| `wg0` | 51820 | road-warrior, 3 peer | **nessun handshake mai** |
| `wg_site_sbt` | 51821 | site-to-site verso l'altra casa | funzionante l'11 ago |

Ipotesi principale per `wg0`: la WAN del router è `192.168.51.2` con gateway
`192.168.51.1`, cioè **doppio NAT** — c'è un router del provider a monte. Un
client esterno non può raggiungere la porta 51820 se quel router non la
inoltra. La site-to-site invece funziona perché è il nostro lato a iniziare la
connessione verso l'endpoint remoto, con `persistent_keepalive`: non ha bisogno
di alcun inoltro in ingresso.

Da verificare: inoltro porte sul router del provider, eventuale DDNS per questo
sito, regole firewall in ingresso su `wg0`, e se ci sia un OpenVPN **sull'altro
capo** (OPNsense o Synology) che l'utente sta confondendo con questo.

### 1-bis. Spostare l'aggiornamento DuckDNS sul router
**Richiesto dall'utente il 2026-08-11, da fare più avanti.**

`diam0nds-pgb.duckdns.org` è l'hostname con cui la casa principale cerca questo
sito. Non esiste alcun aggiornatore DDNS su router master, AP o PVE: secondo
l'utente lo gestisce un **add-on di Home Assistant**, quindi gira nella VM 100.

**Perché è un problema**: HAOS gira sul PVE, che dopo un blackout resta spento
per giorni. Cronologia del 9 agosto:

| Quando | Cosa |
|---|---|
| 9 ago 03:30 | Blackout: PVE e HAOS giù |
| 9 ago ~04:00 | Il router riparte con un **IP pubblico nuovo** |
| 9-11 ago | DuckDNS **non aggiornato**: punta all'IP vecchio |
| 11 ago 10:07 | PVE e HAOS ripartono, il record si aggiorna |

Quindi il servizio che pubblica l'indirizzo di questa casa dipende dalla
macchina che muore. Dopo un blackout il sito diventa **irraggiungibile
dall'esterno per tutta la durata del guasto**, e non si può rimediare da remoto
perché per rimediare bisognerebbe entrare.

**Rimedio**: `ddns-scripts` sul router master (supporta DuckDNS nativamente,
pochi KB), che è sempre acceso e riparte da solo. L'add-on di Home Assistant
può restare come ridondanza.

Da fare insieme agli **inoltri di porta sul router del provider**
(`192.168.51.1`): UDP 51820 per i client, UDP 51821 per la site-to-side. Sono
lo stesso problema visto da due lati — oggi questa casa è raggiungibile
dall'esterno solo se il PVE è accesso *e* se qualcuno ha configurato gli
inoltri.

### 1-ter. Interventi dall'assessment del router master — 2026-08-11
Assessment completo in `assessment-router-master.md` (**cifrato**: è un elenco
di debolezze, è il file il cui trapelare farebbe più danno).

Sintesi: 4 voci di gravità alta, 6 media, 5 bassa, 6 di ottimizzazione, 8 cose
già corrette da non toccare.

**Da fare in quest'ordine:**

| # | Voce | Note |
|---|---|---|
| 1 | Regola `Allow HOME ASSISTANT from IoT VLAN` → cambiare `dest_ip` da `192.168.15.3` a `.4` | **Rompe la domotica adesso** e apre un accesso non voluto ad AdGuard |
| 2 | Rimuovere il port forward `HomeAssistant` (wan:443 → .3) | Inerte, e correggerlo esporrebbe HA su internet |
| 3 | `IoTZone input=REJECT` + permessi espliciti per 53/67 | Oggi i 17 dispositivi IoT raggiungono SSH e LuCI del router |
| 4 | `uhttpd redirect_https='1'` e ascolto solo su interfaccia di gestione | Password di amministrazione in chiaro su HTTP |
| 5 | `dropbear PasswordAuth='off'` e `RootPasswordAuth='off'` | **Solo dopo** aver confermato la chiave da ogni punto |
| 6 | `flow_offloading='1'` (software) | Guadagno maggiore di prestazioni su mt7621 |
| 7 | Log persistenti (`log_size` + collettore) | I log del blackout del 9 ago erano già stati sovrascritti |
| 8 | Hostname espliciti (`pgb-gw`, `pgb-ap`) | Con due case, due nodi `OpenWrt` sono ambigui |
| 9 | **Upgrade OpenWrt 21.02.3 → 24.10** | Il più importante e il più rischioso: EOL, ed è il gateway esposto |

**Scelte da fare consapevolmente, non urgenti:**
- SQM/`cake` per il bufferbloat su FWA — **alternativo** all'offloading hardware
- `s2sVPN -> lan`: oggi manca, quindi la casa principale non raggiunge i nostri
  host. Incompatibile con l'integrazione delle due domotiche
- `isolate='1'` su IoT e Guest — da provare, alcuni dispositivi usano scoperta fra pari
- WPA3 (`sae-mixed`) sulle reti client, lasciando `psk2` su `PGB-IoT`
- `hidden='0'` su `PGB-IoT`: nascondere l'SSID non protegge e crea instabilità

### 2. Secondo AP e stabilità WiFi
L'utente riferisce WiFi instabile in tutta la casa. L'AP (`192.168.15.2`,
SIM SIMAX1800T, OpenWrt 24.10) è raggiungibile ma va verificato il suo ruolo:
il master ha `radio0` in mesh 802.11s con **0 peer**, quindi il mesh non è
funzionante e l'AP presumibilmente lavora via cavo. Da chiarire prima di
toccare i canali.

Elementi già noti che possono contribuire all'instabilità: canale 1 fisso a
2.4 GHz e HT20 sul master, SSID `PGB` presente sia sul master (5 GHz) sia
sull'AP (entrambe le radio) senza che sia stato verificato il roaming.

### 3. AdGuard Home: liste e configurazione
Obiettivo dell'utente: filtri efficaci ma **sistema stabile e non appesantito**,
con liste aggiornate ad agosto 2026. Obiettivo specifico: **filtrare la
pubblicità sulle smart TV**.

Vincoli da rispettare: il container ha 2 GB di RAM e gira su eMMC, quindi liste
enormi sono controproducenti. Le smart TV richiedono attenzione particolare —
molte usano DNS hardcoded (tipicamente 8.8.8.8) e vanno intercettate con una
regola di redirezione sul router, altrimenti aggirano AdGuard del tutto.

### 4. Backup dei dati di VM e container — RIPRESO IN CARICO
`/etc/pve/vzdump.cron` è vuoto: **non esiste alcun backup di VM e container**.
La VM Home Assistant è 32 GB di storico, automazioni e integrazioni, senza
alcuna copia. I ~14 GB liberi nel volume group non bastano per un vzdump in
locale: serve una destinazione esterna (NAS, disco USB, share di rete).

⚠️ Il 9 agosto 2026 la macchina ha subito il quarto stacco di corrente a caldo
documentato. Ogni episodio è una roulette sulla eMMC, che è l'unico disco e non
è sostituibile. **Questo è il rischio più grave fra quelli aperti.**

**Stato**: l'utente ha chiesto di rimandare ("segna il punto, poi ci torniamo").

### 4. Backup dei dati di VM e container
`/etc/pve/vzdump.cron` è vuoto: **non esiste alcun backup di VM e container**.
La VM Home Assistant è 32 GB di storico, automazioni e integrazioni, senza
alcuna copia. I ~14 GB liberi nel volume group non bastano per un vzdump in
locale: serve una destinazione esterna (NAS, disco USB, share di rete).
**Stato**: messo in roadmap dall'utente, da affrontare più avanti.

### 5. Riavvio automatico dopo blackout
BIOS `Restore on AC Power Loss` da `Power Off` a `Power On`. L'utente
interverrà appena avrà una tastiera USB. Vie software già valutate e scartate,
vedi `decisions.md` — non riproporle.

### 6. Ottimizzazione delle configurazioni
Da fare **dopo** che i backup coprono anche i router: così ogni modifica è
visibile in diff e reversibile.

### 7. Gestione centrale, condivisa e coordinata
Obiettivo dichiarato dall'utente. Da chiarire cosa significa "condivisa" —
altre persone che devono poter intervenire, o configurazione uniforme fra i
nodi.

### 8. Aggancio alla domotica della casa principale
Obiettivo finale. Richiede prima di analizzare l'infrastruttura principale,
oggi sconosciuta. La subnet `192.168.15.0/24` non è un default e probabilmente
è già stata scelta per evitare collisioni: un vantaggio in vista del
collegamento fra i due siti.

### 9. Verificare la salute della eMMC
`mmc-utils` non è installato, i contatori di usura non sono mai stati letti.
Rilevante perché la eMMC è l'unico disco, non è sostituibile, e ha già subito
tre stacchi di corrente a caldo.

```bash
apt install -y mmc-utils && mmc extcsd read /dev/mmcblk0 | grep -iE "life time|pre eol"
```

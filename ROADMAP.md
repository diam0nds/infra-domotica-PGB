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
`infra-common/scripts/router/dns-watchdog.sh`), cron al minuto, in `sysupgrade.conf`.
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

Esiste un hostname DuckDNS con cui CASA cerca PGB (il nome sta nel config
cifrato). Non esiste alcun aggiornatore DDNS su router master, AP o PVE: secondo
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
| ~~1~~ | ✅ **FATTO 2026-08-11** — `Allow HOME ASSISTANT from IoT VLAN`: `dest_ip` da `192.168.15.3` a `.4` | Verificato prima: nessun flusso IoT→AdGuard, quindi nessuna rottura. Dopo: 15 flussi IoT→HA attivi, 0 riferimenti a `.3` in iptables, DNS/filtro/tunnel intatti. Applicato con ripristino armato |
| ~~2~~ | ✅ **FATTO 2026-08-11** — rimossi **due** redirect morti: `HomeAssistant` (wan:443 → .3, porta chiusa, 0 flussi attivi) e `WG-s2S` (DNAT verso l'IP del router stesso, già disabilitato) | Verificato prima che fossero inerti. Dopo: 0 redirect, 0 DNAT in iptables, tunnel/DNS/client VPN intatti |
| ~~3~~ | ✅ **FATTO 2026-08-11** — `IoTZone input=REJECT` + regola **nominata** `firewall.iotsvc` che permette `53 67 68 123` | Misurato prima: i dispositivi IoT contattano il router **solo sulla 53**. Aggiunti i permessi *prima* di chiudere. Catena verificata: ACCEPT precedono il REJECT finale. Confermato alle 13:28: **14 pacchetti accettati su :53** (erano 1 subito dopo la modifica) e **0 rifiuti**. I dispositivi IoT usano regolarmente il DNS del router attraverso la nuova regola. Se in futuro qualcosa smette di funzionare, il contatore `zone_IoTZone_src_REJECT` lo rivela |
| ~~4~~ | ✅ **FATTO 2026-08-11** — `uhttpd redirect_https='1'` | Verificato prima che cert e key esistessero, altrimenti LuCI diventava irraggiungibile. Dopo: HTTP risponde `307` → `https://`. **Ascolto sulle interfacce lasciato invariato**: la chiusura della zona IoT ottiene la stessa protezione senza rischio di autoesclusione |
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

### 1-quater. Messa in sicurezza e minimizzazione dati del comparto IoT
**Richiesto dall'utente il 2026-08-11.** Obiettivo: garantire ai dispositivi il
funzionamento, limitando al minimo le informazioni che inviano ai server dei
produttori.

**Principio guida**: non "bloccare il cloud" ma **renderlo inutile** — Home
Assistant come unico hub locale, dispositivi senza uscita verso internet,
accesso remoto dell'utente via WireGuard invece che via app del produttore.
Compromesso da accettare consapevolmente: si perdono le app dei produttori e i
comandi vocali che passano dal loro cloud.

#### Inventario — 22 dispositivi nella VLAN IoT (2026-08-11)

| IP | Dispositivo | Traffico verso internet (snapshot) |
|---|---|---|
| `.10` | SONOFF-Zbridge-PRO | — |
| `.11`–`.14`, `.18`–`.21` | 8× Shelly 2.5 | **nessuno** |
| `.15`, `.22` | 2× Shelly RGBW2 | **nessuno** |
| `.16` | Shelly 1PM | **nessuno** |
| `.17` | Shelly EM | **nessuno** |
| `.23` | BHT-6000 termostato | — (tipicamente Tuya, cloud-dipendente) |
| `.24`, `.25`, `.26` | 3× Midea clima | **AWS Global Accelerator :443** |
| `.148` | Dreame robot (no lease statico) | **Alibaba Cloud :19973**, porta proprietaria |
| `.125` | non identificato, no lease statico | da censire |
| `.139` | **S24-di-Luca** — telefono sulla VLAN IoT | da spostare su `PGB`/`PGB-G` |

⚠️ Lo snapshot è un istante: **non basta per decidere cosa staccare.**

**Confermato subito dalla profilazione**: al primo campionamento successivo è
emerso che `192.168.16.20` (CAMER-SHELLY25-Luci) parla con
`34.38.167.174:6021` — Google Cloud, porta del **Shelly Cloud**. <!-- no-secrets-ok: indirizzo di terzi, non nostro --> Lo snapshot
iniziale l'aveva mancato e mi aveva portato a scrivere che i Shelly non
uscivano su internet. **Almeno uno lo fa.**

È la dimostrazione pratica del perché il punto 5 richiede il punto 1: senza
profilazione avrei tagliato l'uscita ai Shelly convinto che fosse indolore.

#### Lacuna che rende inefficace il filtro

**Non esiste alcuna redirezione DNS per la VLAN IoT.** Un dispositivo con DNS
cablato nel firmware (tipico di TV, robot, climatizzatori) bypassa AdGuard
completamente. Vale già oggi, non solo per le future smart TV.

#### Ordine di lavoro

| # | Intervento | Rischio |
|---|---|---|
| ~~1~~ | ✅ **ATTIVO dal 2026-08-11** — profilazione ogni 15 min. `infra-common/scripts/iot-profile-collect.sh` (cron sul PVE, `/etc/cron.d/iot-profile`), report con `infra-common/scripts/iot-profile-report.sh`, dati in `/var/log/iot-profile.tsv`. **Da rimuovere il 18 agosto**, a finestra conclusa | nullo |
| 2 | **Redirezione DNS obbligatoria** della VLAN IoT verso AdGuard (DNAT su 53), efficace anche sui DNS cablati | molto basso |
| 3 | **Blocco DoT/DoH** (853 + resolver noti): senza, un dispositivo aggira il filtro cifrando le query | basso |
| 4 | **Redirezione NTP locale**: molti dispositivi hanno l'NTP cablato e lo usano per raggiungere l'esterno | basso |
| 5 | **Uscita in default-deny** sulla VLAN IoT con permessi per singolo dispositivo, basati sui dati del punto 1 | **medio** — da fare solo con la profilazione in mano |
| 6 | Censire `.125`, dare lease statico al Dreame, spostare il telefono fuori dalla VLAN IoT | nullo |
| 7 | `isolate='1'` sulla SSID IoT | basso, da verificare sul campo |

Il punto 5 senza il punto 1 è un tiro al buio: la dipendenza dal cloud si
scoprirebbe quando il clima non risponde più.

### ✅ 2. WiFi — Gruppi 1, 2 e 3 applicati il 2026-08-11

Dettagli completi in `assessment-wifi.md` (cifrato). Sintesi:

| Indicatore | Prima | Dopo |
|---|---|---|
| Client su **entrambi** i nodi | 3 | 1 |
| Sovrapposizione canale 2.4 GHz | totale | **nessuna** (ch1 / ch11) |
| Sovrapposizione canale 5 GHz | totale | **nessuna** (5180-5200 / 5220-5240) |
| SSID inutili | `PGB-G` (0 client) | rimossa |
| Mesh inerte | 1 interfaccia | rimossa |
| Dominio regolatorio | `00` | `IT` |
| Domotica collegata | 16-17 | **17/17** |

Fatto anche: BSSID fissati con `macaddr`, `802.11k` su tutte le `PGB`.

**Rimane da fare sul WiFi:**
- Ridurre la potenza a 5 GHz del master (23 dBm): un client tiene ancora una
  doppia associazione a −82 dBm, e la radio 5 GHz dell'AP è a 0 client
- **802.11v**: richiede di sostituire `wpad-basic` con `wpad-full` su entrambi i
  nodi. Senza, l'AP non può suggerire ai client di spostarsi
- **Orologio dell'AP sbagliato** (log datati Feb 2025): NTP non sincronizzato,
  rende i suoi log inutili per correlare eventi
- **`PGB-IoT` sull'AP**: progetto VLAN a sé, vedi sotto

### 2-bis. Progetto VLAN: portare la rete IoT sul cavo
La rete IoT **non esiste sul cavo**: `192.168.16.1` vive direttamente
sull'interfaccia WiFi del master, senza bridge né VLAN. L'AP ha solo `lan`.

Serve: VLAN sullo switch del master (`swconfig`, 21.02), aggancio della rete IoT,
VLAN corrispondente sull'AP (**DSA**, 24.10 — paradigma diverso), interfaccia IoT
sull'AP, BSS `PGB-IoT` con chiave copiata senza leggerla.

Cinque modifiche coordinate su due dispositivi con paradigmi diversi, sulla rete
che porta 17 dispositivi di domotica, su un sito non presidiato. **Prerequisito**
per ridurre la potenza a 2.4 GHz: oggi `corr-shelly25-faretti` è a −78 dBm e non
ha alternative.

### ~~2-ter~~. Secondo AP e stabilità WiFi
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

### ✅ 4. Backup dei dati di VM e container — FATTO 2026-08-11

Job PVE nativo `pgb-daily`: ogni giorno alle **02:30**, storage `local`,
modalità snapshot, zstd, ritenzione `keep-daily=5,keep-weekly=3`.

Numeri misurati al primo backup reale:

| | |
|---|---|
| VM 100 Home Assistant | **1,36 GB** compressi, 5:53 |
| CT 101 AdGuard | **319 MB**, 1:01 |
| Totale per set | ~1,7 GB, ~7 minuti |
| Ritenzione piena (8 set) | ~14 GB su 31 liberi |

**Ripristino verificato**, non solo dichiarato: container ripristinato su VMID
999, `AdGuardHome.yaml` presente con `blocking_mode: nxdomain` — la modifica
fatta lo stesso giorno. Montato in sola lettura e **non avviato** (stesso MAC
dell'originale), poi rimosso.

⚠️ **Correzione a quanto era scritto qui prima**: "i ~14 GB liberi nel volume
group non bastano, serve una destinazione esterna" era **falso**. Confondeva il
thin pool LVM con lo storage `local`, che sta su root con 33 GB liberi ed era
già abilitato ai backup. E i dati reali sono 7,5 GB, non 32: il disco è thin
provisioned. L'errore ha rimandato l'intervento per un ostacolo inesistente.

⚠️ Anche "ogni stacco a caldo è una roulette sulla eMMC" era infondato:
misurato `Life Time Estimation A/B = 0x01` (0-10% consumato) e `Pre EOL = 0x01`
(normale). La eMMC è praticamente nuova. Il rischio reale degli stacchi è la
corruzione nell'istante del taglio, non l'usura.

**Cosa resta**: una destinazione **esterna**. Questo backup sta sullo stesso
disco dei dati, quindi non copre morte della eMMC, furto o incendio. In più il
carico di picco misurato è **13.17** su 4 core, perché la eMMC legge e scrive
insieme: un NAS o un disco USB migliorerebbe anche le prestazioni.

**Limite noto**: un job PVE a orario fisso non recupera le esecuzioni perse. Se
la macchina è spenta alle 02:30 quel backup salta — stesso difetto già visto sul
backup delle configurazioni, là risolto con un `@reboot`. Qui non c'è un
equivalente nativo.

### 4-bis. ✅ Backup della configurazione dei dispositivi Shelly — FATTO 2026-08-12
**Richiesto dall'utente il 2026-08-11, completato il 2026-08-12** (sessione
**presidiata**).

Gli Shelly non avevano alcun backup: se uno si guastava e veniva sostituito,
orari, calibrazione delle tapparelle, nomi dei relè e impostazioni MQTT andavano
ricostruiti a mano uno per uno. Ora sono nel backup cifrato giornaliero.

**Cosa gira**: `infra-common/scripts/collect-shelly.sh`, richiamato da
`collect-configs.sh`. Solo `GET /settings` sull'API Gen1: nessuna scrittura sui
dispositivi, nessun agente installato, 52 KB per l'intero parco. L'elenco dei
dispositivi si legge dai lease statici del router, quindi si adatta da sé quando
se ne aggiungono.

**Coperti: 11 dispositivi** — 8× SHSW-25, 2× SHRGBW2, 1× SHSW-PM.

**Non coperti, e perché** (scritto anche in `guests/shelly/LEGGIMI.txt`, così chi
legge il repo non crede che sia tutto):

| Dispositivo | Motivo |
|---|---|
| `SONOFF-Zbridge-PRO` | 404 su `/settings` e `/rpc`: API propria, da studiare |
| `BHT-6000-Termost` | 404 su entrambe: basato su Tuya, nessuna API locale |
| 3× Midea (clima) | nessun server HTTP, solo client verso il cloud |
| `CORR-SHELLY-EM` (`.17`) | non risponde: è quello **già guasto**, non un limite del metodo |

**Tre trappole trovate e chiuse**, tutte verificate con una misura e non per
ragionamento:

1. **Campi volatili → un commit a vuoto al giorno.** Due letture a 3 secondi di
   distanza differiscono su `unixtime`, `time`, `power`, `temperature`, contatori.
   Vengono rimossi, le chiavi ordinate e indentate per diff leggibili. Verificato:
   due raccolte consecutive producono file **identici**, e la pipeline completa
   chiude con "nessuna modifica e nulla da inviare".
2. **Il JSON contiene credenziali** — chiave WiFi in `wifi_sta`, utente e password
   MQTT, credenziali del web locale in `login`. Controllate **per nome di campo,
   senza mai stamparne il valore**. I file **non** sono nell'allowlist di
   `.gitattributes`: `git-crypt status` conferma 12 file cifrati e 0 in chiaro.
3. **L'avviso "dispositivi in meno" era cieco.** `collect-configs.sh` fa
   `rm -rf guests/` prima della raccolta, quindi confrontare col filesystem dava
   sempre "erano 0" e l'avviso non poteva scattare mai. Il termine di confronto si
   legge da **git** (`git ls-files`), cioè dall'ultima raccolta committata.
   Verificato togliendo un file a mano: l'avviso scatta e **nomina** il
   dispositivo mancante.

⚠️ **Un dispositivo spento risulta assente dalla cartella.** L'assenza non
significa che non esista: significa che non rispondeva al momento della raccolta.
Confrontare con l'inventario in `README.md`.

**I due "senza API" sono stati identificati il 2026-08-12, ed erano entrambi
classificati male.** Nessuno dei due è Tuya o proprietario: montano firmware
liberi con interfaccia locale completa.

| Dispositivo | Cosa monta davvero | Come si salva |
|---|---|---|
| `SONOFF-Zbridge-PRO` `192.168.16.10` | **Tasmota 14.2.0.3** su ESP32-D0WD-V3, template `TCP ZBBridge Pro` <!-- no-secrets-ok: 14.2.0.3 e' la versione di Tasmota, non un indirizzo IP --> | scaricare la configurazione da `/dl` (endpoint di download, sola lettura) |
| `BHT-6000-Termost` `192.168.16.23` | **WThermostat v1.23.beta1-fas** (ESP8266) | interfaccia su `/config`; nessun endpoint di dump: la configurazione va letta dalle pagine |

⚠️ **Il bridge NON contiene gli accoppiamenti Zigbee.** Fa solo da ponte
seriale-su-TCP (porta 8888) verso il chip Zigbee; Home Assistant ci si collega
con **Zigbee2MQTT**. Quindi l'artefatto che evita di riassociare tutto è
**`coordinator_backup.json` + `database.db` di Zigbee2MQTT**, dentro la VM 100 —
non la configurazione del bridge. Oggi finisce nel vzdump come immagine intera,
che non è la stessa cosa di un export ripristinabile su un coordinatore nuovo.
**Questo è il pezzo che vale di più e non è ancora coperto.**

Il termostato è già nello stato che cerchiamo per l'IoT: **nessuna connessione
esterna**, unica uscita MQTT verso `192.168.15.4:1883`. Zero cloud.

### 4-ter. Backup remoto dei dati sul Synology di CASA
**Fattibilita' misurata il 2026-08-11, in attesa di una configurazione su DSM.**

| Verifica | Esito |
|---|---|
| PVE -> Synology attraverso il tunnel | ✅ 16,5 ms |
| Il Synology ci vede come | **192.168.15.5** (nessun masquerade sul tunnel, provato in conntrack) |
| NFS sul Synology | ✅ attivo, due esportazioni esistenti |
| Banda in salita di PGB | **16,8 Mbps / 2,0 MB/s** |
| Tempo stimato per 1,7 GB | **~15 minuti** |
| Cifratura in transito | garantita dal tunnel WireGuard |

**Ostacolo residuo**: nessuna esportazione include `192.168.15.5`.

```
/volume1/video   ->  192.168.10.0/24
/volume1/File    ->  192.168.10.6      (solo il PVE di CASA)
```

⚠️ **Su Synology i permessi NFS si impostano per cartella condivisa, non per
sottocartella.** Creare `File/backup-pgb` non produce alcuna esportazione: il
montaggio resta rifiutato, verificato su entrambi i percorsi. Serve o un permesso
NFS su `File` (che esporrebbe **tutta** la condivisione), o rendere `backup-pgb`
una cartella condivisa a se' stante — preferibile, per privilegio minimo.

**Architettura scelta**: backup locale (gia' attivo) **piu'** copia `rsync`
successiva, non un job PVE puntato direttamente sullo storage remoto. Motivo: a
2 MB/s `vzdump` terrebbe aperto lo snapshot della VM per 15 minuti invece di 6, e
un singhiozzo del tunnel farebbe fallire anche la copia locale che sarebbe
riuscita. Con la copia separata, un tunnel giu' fa saltare solo la replica.

Da fare dopo la configurazione DSM: montare, misurare un trasferimento **reale**,
aggiungere la copia dopo il job, registrare come storage PVE per i ripristini da
interfaccia, e **provare un ripristino dalla copia remota**.

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

### 10. Messa in sicurezza degli accessi al PVE
**Richiesto dall'utente il 2026-08-11**, dopo aver notato che tutto il lavoro
gira nella home di root. Fino a oggi la roadmap non aveva **nessuna** voce sugli
accessi al PVE: l'unica sull'autenticazione era la 5 dell'assessment, che
riguarda i router.

Stato letto dai comandi l'11 agosto 2026:

| Cosa | Stato |
|---|---|
| `PermitRootLogin` in sshd | **`yes`** |
| `PasswordAuthentication` | non impostato → default Debian **`yes`** |
| Utenti locali con shell valida | solo `root` |
| Chiavi autorizzate per root | 2 |
| Utenti PVE | uno solo, `root@pam`, **nessun 2FA** |
| In ascolto | `22` su tutte le interfacce, `8006` (GUI), `3128` (SPICE) |
| Firewall proprio del PVE | **disabilitato** |

Cioè: **sul PVE si entra come root con una password**, e la GUI su 8006 è
protetta dalla stessa password senza secondo fattore. Non è esposto su internet
— gli inoltri verso il PVE sono stati rimossi e la zona IoT non raggiunge la LAN
— quindi la superficie è LAN più VPN. Ma la VPN è il canale con cui CASA verrà
agganciata, e questo è il nodo che ospita Home Assistant.

**Da fare in quest'ordine:**

| # | Voce | Rischio |
|---|---|---|
| ~~1~~ | ✅ **FATTO 2026-08-11** — `700` su `/root/infra`, `/root/infra-common`, `/root/.claude` (erano `755`) | Verificato dopo: git allineato su entrambi i repo, collettore eseguito senza errori. Gira come root, quindi il `700` non gli toglie nulla |
| 2 | 2FA TOTP su `root@pam` per la GUI | basso, ma tenere una via di recupero |
| 3 | `PasswordAuthentication no` + `PermitRootLogin prohibit-password` in `/etc/ssh/sshd_config.d/` | ⚠️ **alto** |
| 4 | Valutare l'ascolto di `8006`/`3128` limitato alla LAN e l'accensione del firewall del PVE | ⚠️ **alto** |

⚠️ I punti 3 e 4 sono le modifiche che, se sbagliate, **chiudono fuori da un
sito vuoto**: vanno fatte **solo in finestra presidiata** e solo dopo aver
confermato la chiave da ogni punto da cui serve entrare — stessa cautela della
voce 5 sui router. Il punto 4 tocca l'interfaccia da cui si amministra.

### Perché i repo restano nella home di root — 2026-08-11

Valutato e **scartato** lo spostamento in `/srv` o `/opt`. Il working tree di git
è **in chiaro**: git-crypt cifra gli oggetti del repo e ciò che va su GitHub, non
i file su disco. `hosts/router-master/etc/config/wireless` è leggibile, con le
password WiFi dentro.

Le directory di lavoro sono `755`: **l'unica cosa che protegge password WiFi,
hash di root e chiavi WireGuard in chiaro è il `700` di `/root`.** `/srv` e
`/opt` nascono `755`, quindi lo spostamento senza rifare i permessi a mano
*peggiora* la sicurezza — e non produce alcun messaggio d'errore.

La ragione FHS per cui i dati di sito andrebbero in `/srv` resta valida in
astratto. Va riaperta insieme alla voce 7 ("gestione centrale, **condivisa**"):
se un'altra persona deve operare, `/root` la esclude per definizione. La risposta
giusta lì non è mettere segreti in chiaro in una directory leggibile da tutti, ma
un secondo account amministrativo e git come canale di condivisione.

Girare come root non è una scelta rinviabile: `qm`, `pct`, la lettura di
`/etc/pve` e la chiave verso i router lo richiedono, e su Proxmox l'identità
amministrativa è `root@pam`. Un utente dedicato che poi usa `sudo` per quasi
tutto lascia la superficie identica e aggiunge un pezzo che si rompe.

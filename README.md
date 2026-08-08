# Inventario infrastruttura domotica

> Ultimo aggiornamento verificato: **2026-08-08**
> Tutto ciò che segue è stato letto dai comandi, non dedotto.
> Le voci marcate ❓ sono da confermare.

## Rete

Subnet `192.168.15.0/24`, gateway `192.168.15.1`.

| IP | MAC | Dispositivo | Stato accesso |
|---|---|---|---|
| 192.168.15.1 | `64:64:4a:3b:ea:84` | Router OpenWrt **master** (gateway) | ❌ nessuna credenziale |
| ❓ | `c6:c2:98:88:b7:77` ❓ | Router OpenWrt **AP/extender WiFi** | ❌ IP non ancora noto |
| 192.168.15.5 | — | **pve** (host Proxmox) | ✅ root locale |
| 192.168.15.3 | `bc:24:11:3e:76:8d` | **AdGuard** (LXC 101) — porte 22, 80 | via host |
| 192.168.15.4 | `02:f5:16:3f:01:a5` | **Home Assistant** (VM 100) — porta 8123, 443 | via host |
| 192.168.15.101 | `38:8d:3d:89:62:80` | ❓ non identificato — risponde ad ARP, nessuna porta aperta | — |
| 192.168.15.164 | `dc:03:98:4a:c7:46` | ❓ non identificato — risponde ad ARP, nessuna porta aperta | — |

## Router AP — SIM SIMAX1800T

OpenWrt **24.10.0** (r28427-6df0e3d02a) — **più recente del master**, che è
fermo a 21.02.3 fuori supporto. Asimmetria da correggere dal lato sbagliato:
l'obsoleto è proprio il nodo esposto su internet con WireGuard.

Accesso: `ssh router-ap` (192.168.15.2, chiave `id_ed25519_infra`).

### È un dumb AP puro

| Parametro | Valore |
|---|---|
| `network.lan.proto` | `static`, `192.168.15.2`, gw `192.168.15.1` |
| `network.lan.dns` | **nessuno** |
| `dhcp.lan.ignore` | `1` — server DHCP **disattivato** |
| dnsmasq | **non in esecuzione** |
| radio0 / radio1 | entrambe `mode=ap`, SSID `PGB`, network `lan` |

Non distribuisce né DHCP né DNS: i suoi client ricevono tutto dal master,
esattamente come qualunque altro dispositivo della LAN. **È trasparente.**

### AP individuato — 2026-08-08 (storico)

L'utente lo ha **cablato su `lan1`** del master (prima quella porta non aveva
link). Ora è in rete e fa da AP: i suoi client WiFi compaiono sulla porta 1 del
bridge del master.

**Non ha alcun IPv4 raggiungibile.** Nessun lease DHCP, e sonde su
`192.168.0/1/2/31.x`, `10.0.0.x`, `172.16.0.x` non danno risposta. Si raggiunge
però via **IPv6 link-local**:

```
fe80::c43b:93ff:fe7d:4dbf   (MAC c6:3b:93:7d:4d:bf)
porte 22, 80, 443 aperte — OpenWrt con LuCI
```

Dal PVE: `ssh root@fe80::c43b:93ff:fe7d:4dbf%vmbr0`

⚠️ La chiave `id_ed25519_infra` **non è ancora autorizzata su questo nodo**:
era stata aggiunta solo al master. Finché non lo è, `collect-configs.sh` non
può raccoglierne la configurazione.

Da fare: assegnargli un IPv4 statico nella LAN (es. `192.168.15.2`) — un nodo
gestibile solo via link-local è fragile e scomodo. Nota anche che, essendo ora
cablato, il backhaul mesh è ridondante: si potrebbe disattivare `radio0` in
modalità mesh e guadagnarne in stabilità.

### Storico: perché prima non si trovava — 2026-08-08

**Risolto**: l'AP è acceso ma **non è connesso alla rete**, per questo non si
trova. Non è un problema di indirizzamento.

Il master ha `radio0` in modalità **mesh 802.11s** (`mesh_id='my-mesh'`,
encryption `sae`, canale 1, HT20, banda 2.4 GHz): è così che il secondo nodo
dovrebbe agganciarsi. Ma `iw dev wlan0 station dump` riporta **0 peer** e
`mpath dump` nessun percorso. Il mesh è vuoto.

`192.168.15.102` (MAC `c6:c2:98:88:b7:77`) ha un lease DHCP e una voce ARP sul
master, ma non risponde al ping **nemmeno dal router stesso**: è residuo di una
sessione precedente, non un dispositivo vivo.

Da verificare lato AP: se sia cablato (e su quale porta) o se debba agganciarsi
via mesh, e in quest'ultimo caso se `mesh_id`, cifratura SAE e canale
corrispondano a quelli del master.

## Router master — Xiaomi Mi Router 4A Gigabit

OpenWrt **21.02.3** (r16554-1d4dea6d4f). ⚠️ Versione **fuori supporto**: la
serie 21.02 non riceve più aggiornamenti di sicurezza. Da pianificare un
upgrade, tenendo conto che è il gateway di un sito remoto — un aggiornamento
andato male non è recuperabile senza presenza fisica.

### Topologia di rete

| Rete | Subnet | Interfaccia | Contenuto |
|---|---|---|---|
| WAN | `192.168.51.2/24` → gw `.51.1` | `wan` | **Doppio NAT**: c'è un router del provider a monte |
| LAN | `192.168.15.0/24` | `br-lan` (lan1, lan2) | PVE, HAOS, AdGuard, PC, telefoni |
| IoT | `192.168.16.0/24` | `wlan0-2` | **Tutta la domotica**: Shelly, Midea, Sonoff, termostato, robot |
| GUEST | `10.10.15.0/24` | — | rete ospiti |
| VPN client | `192.168.9.0/24` | `wg0` | WireGuard road-warrior, 3 peer |
| VPN sito | `10.10.10.2/32` → `192.168.10.0/24` | `wg_site_sbt` | **Tunnel site-to-site già attivo** verso l'altra casa |

**Il collegamento fra le due case esiste già**: un tunnel WireGuard verso un
endpoint DDNS Synology (nel config cifrato) instrada `192.168.10.0/24`. Da
tenere presente quando si progetterà l'integrazione delle due domotiche.

### WiFi

| SSID | Banda | Rete | Note |
|---|---|---|---|
| `PGB` | 5 GHz | lan | |
| `PGB-G` | 2.4 GHz | lan | la variante 5 GHz è disabilitata |
| `PGB-IoT` | 2.4 GHz | IoT | 17 dispositivi collegati |
| — | 2.4 GHz | lan | mesh 802.11s, `mesh_id='my-mesh'`, **0 peer** |

## Host: `pve`

| | |
|---|---|
| Ruolo | Hypervisor Proxmox VE 8.4.0 su Debian 12 (bookworm) |
| Kernel | 6.8.12-9-pve |
| CPU | Intel Pentium J3710 — 4 core, 1.6–2.64 GHz |
| RAM | 7.7 GB (~3.9 GB in uso) + 7.7 GB swap (non usato) |
| Storage | **eMMC 116 GB** (`mmcblk0`) — unico disco, no SATA/NVMe |
| Layout | LVM: root 39 GB (10% usato), thin pool `local-lvm` 52.5 GB (15%), ~14 GB liberi nel VG |
| Rete | `vmbr0` 192.168.15.5/24 su `enp1s0` (Realtek RTL8111/8168, driver r8169) |
| WiFi onboard | `wlp2s0` (RTL8821CE) — DOWN, non usato |
| BIOS | AMI `BSW_0128_0106` (03/2025), Secure Boot **disabilitato**, platform in Setup Mode |
| Boot | UEFI, `\EFI\PROXMOX\SHIMX64.EFI`, ESP su `mmcblk0p2` (1 GB, 2% usato) |

### Guest

| ID | Nome | Tipo | RAM | Disco | onboot |
|---|---|---|---|---|---|
| 100 | `haos` | VM (Home Assistant OS) | 4 GB | 32 GB | ✅ |
| 101 | `adguard` | LXC | 2 GB | 2 GB | ✅ |

### Toolchain presente

Installati: `curl`, `rsync`, `python3`
**Mancanti**: `git`, `ansible`, `jq`, `mmc-utils`, `lm-sensors`, `git-crypt`

## Problema noto: spegnimenti da mancanza corrente

Il sistema subisce **interruzioni di alimentazione** e **non si riaccende da solo**.

Evidenze raccolte:
- I log di più boot terminano di netto senza sequenza di shutdown
- `systemd-fsck` al boot del 2026-08-08: *"Dirty bit is set. Fs was not properly unmounted"*
- Nessun evento termico, nessun errore I/O sulla eMMC, nessun watchdog

Cronologia dei crash e del tempo di inattività:

| Morte improvvisa | Riaccensione manuale | Spento per |
|---|---|---|
| 2025-07-27 19:17 | 2025-08-04 03:30 | 8 giorni |
| 2025-08-23 20:17 | 2025-09-06 14:33 | 14 giorni |
| 2026-07-31 12:50 | 2026-08-08 08:58 | 8 giorni |

**Causa**: BIOS `Restore on AC Power Loss` = `Power Off`.
**Rimedio deciso**: l'utente lo cambierà da BIOS quando avrà una tastiera USB.
Vie software scartate: `/sys/class/firmware-attributes` assente, variabile
UEFI `Setup` non esposta in efivarfs, AMISCE di provenienza incerta.
Wake-on-LAN supportato (`pumbg`) ma disabilitato (`d`) — **l'utente ha scelto
di non abilitarlo**.

⚠️ Ogni stacco a caldo è un rischio per la eMMC. Salute della eMMC **non
ancora verificata** (`mmc-utils` non installato).

## Problema noto: il DNS è un single point of failure

Segnalato dall'utente il 2026-08-08.

**AdGuard (LXC 101, 192.168.15.3) è il DNS della rete, e gira sul PVE.**
Quando il PVE va giù, i client non risolvono più nulla e non navigano —
l'utente lo ha osservato sui dispositivi collegati all'AP WiFi.

Questo si **somma** al problema dell'alimentazione: il PVE resta spento
8-14 giorni dopo un blackout, e in tutto quel periodo la casa è senza DNS.
Non è un disservizio di pochi minuti.

### Com'è configurato davvero — letto il 2026-08-08

Nessuna interfaccia imposta `dhcp_option 6`, quindi **i client ricevono come
DNS il router stesso** (`192.168.15.1`), non AdGuard direttamente. Vale per
lan, IoT e GUEST.

Il dnsmasq del router ha **quattro upstream**:

```
dhcp.@dnsmasq[0].server = '192.168.15.3' '192.168.15.1' '1.1.1.1' '10.9.0.1'
                           AdGuard        sé stesso      Cloudflare  ?
```

Con `strictorder` e `allservers` **entrambi non impostati**.

Tre osservazioni:

1. **Il filtraggio non è garantito.** Senza `strictorder`, dnsmasq non rispetta
   l'ordine dell'elenco: converge sull'upstream che risponde prima. Con
   Cloudflare fra le opzioni, una quota di query aggira AdGuard — quanta,
   dipende dalle latenze del momento. Il filtro c'è, ma non è deterministico.
2. **`192.168.15.1` è sé stesso.** Un upstream autoreferenziale: nel migliore
   dei casi inutile, nel peggiore un anello.
3. **`10.9.0.1` è raggiungibile ma non identificato.** Non appartiene a nessuna
   delle subnet note; da capire cosa sia prima di toccare la configurazione.

### L'AP è stato scagionato — 2026-08-08

Ipotizzavo che i client dell'AP non navigassero perché l'AP annunciava AdGuard
direttamente o aveva un DHCP proprio. **Falso**: l'AP ha DHCP disattivato e
nessun dnsmasq, quindi i suoi client seguono lo stesso identico percorso DNS di
tutti gli altri. Non c'è nulla di specifico dell'AP.

Spiegazione più probabile del sintomo: quando il PVE è spento, `192.168.15.3`
non rifiuta le query — semplicemente non risponde, e nemmeno l'ARP si risolve.
dnsmasq attende il timeout prima di ripiegare sugli altri upstream, quindi la
navigazione non si interrompe ma diventa lentissima. Per chi la usa è
indistinguibile da "non funziona". Il sintomo riguarda **tutta la casa**, non
solo l'AP: è lì che è stato notato, non è lì che nasce.

### Misurazione reale — 2026-08-08

Statistiche estratte da dnsmasq con `kill -USR1`, cioè contatori veri, non stime:

| Upstream | Query inviate | Quota | Fallite |
|---|---:|---:|---:|
| `1.1.1.1` | 16.052 | 36% | 1 |
| `fe80::1%wan` (router ISP, IPv6) | 13.476 | 30% | 471 |
| `8.8.8.8` | 8.880 | 20% | 31 |
| **`192.168.15.3` (AdGuard)** | **3.264** | **7%** | 18 |
| `10.9.0.1` | 2.933 | 7% | 0 |

Totale query inoltrate: 29.496 (più 16.590 servite da cache).

**AdGuard vede meno di una query su dieci.** Il filtraggio che si crede attivo
è in gran parte aggirato: oltre l'85% del traffico DNS esce verso resolver
pubblici o verso il router del provider, senza passare da nessun filtro.

### Le tre cause

1. **`noresolv` non impostato.** dnsmasq usa gli upstream di `uci` **più**
   quelli forniti dalla WAN in `/tmp/resolv.conf.d/resolv.conf.auto`
   (`1.1.1.1`, `8.8.8.8`, `fe80::1%wan`). Da 4 upstream configurati se ne
   ritrovano 6 attivi, tre dei quali nessuno ha scelto deliberatamente.
2. **`strictorder` non impostato.** Senza, dnsmasq converge sul più veloce. Un
   resolver anycast pubblico batte quasi sempre un container su eMMC.
3. **`10.9.0.1` non è un server DNS.** Risponde al ping (14,7 ms via tunnel) ma
   **non risponde mai** alle query — verificato due volte. Sono 2.933 query
   buttate in attese inutili.

Da notare: `192.168.15.1` nella lista è il router stesso, un upstream
autoreferenziale.

Lato client va invece tutto bene: nessun `dhcp_option 6`, quindi i client
ricevono il router come DNS, e anche via IPv6 (`ra=server`, `dhcpv6=server`)
viene annunciato il router. Nessun bypass diretto dai client.

AdGuard risolve per conto proprio via DoH verso `dns10.quad9.net` con bootstrap
Quad9: non dipende dal router, quindi non c'è rischio di dipendenza circolare.

### Correzione proposta (non ancora applicata)

```sh
uci set dhcp.@dnsmasq[0].noresolv='1'       # ignora i DNS imposti dalla WAN
uci set dhcp.@dnsmasq[0].strictorder='1'    # rispetta l'ordine della lista
uci -q delete dhcp.@dnsmasq[0].server       # ripulisce i 4 attuali
uci add_list dhcp.@dnsmasq[0].server='192.168.15.3'   # AdGuard, primo
uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'        # ripiego reale
uci commit dhcp
/etc/init.d/dnsmasq restart
```

⚠️ Con `strictorder`, a PVE spento ogni query attende il timeout di AdGuard
prima di ripiegare: il filtraggio diventa deterministico, ma la lentezza nello
scenario di guasto va **misurata**, non data per risolta. Se pesa troppo, si
abbassa il timeout di dnsmasq o si valuta il pacchetto `adblock` sul router
come secondo livello indipendente dal PVE.

### Applicata la correzione — e sono emersi due difetti — 2026-08-08

`noresolv` e `strictorder` sono stati applicati, la lista ridotta ad AdGuard +
Cloudflare. Il DNS ha continuato a funzionare, ma **il filtro non filtrava
ancora**. Misurando invece di assumere sono emersi due problemi distinti.

#### 1. dnsmasq inverte l'ordine dei server

Il file generato ha l'ordine giusto:

```
server=192.168.15.3      <- AdGuard, primo
server=1.1.1.1
```

ma il log di avvio rivela la lista interna:

```
using nameserver 1.1.1.1#53          <- dnsmasq lo mette per primo
using nameserver 192.168.15.3#53
```

Con `strictorder` interroga sempre il primo della **lista interna**, ottiene
risposta, e ad AdGuard non arriva nulla. Contatori dopo la modifica:

```
server 1.1.1.1#53:      queries sent 113
server 192.168.15.3#53: queries sent 0     <- zero
```

**Rimedio**: invertire l'ordine in uci, così la lista interna risulta corretta.
È un dettaglio implementativo di dnsmasq, quindi **va verificato sui contatori
dopo ogni modifica**, non dato per acquisito.

#### 2. `rebind_protection` scartava i blocchi di AdGuard

```
possible DNS-rebind attack detected: doubleclick.net
DNS rebinding protection is active, will discard upstream RFC1918 responses!
```

AdGuard bloccava restituendo `0.0.0.0`, e dnsmasq lo scambiava per un attacco
di DNS rebinding scartando la risposta. Ecco perché, prima della modifica, il
router restituiva risposte vuote sui domini bloccati.

**Rimedio applicato**: `blocking_mode` di AdGuard portato da `default` a
`nxdomain` (backup in `AdGuardHome.yaml.pre-nxdomain` dentro il container).
NXDOMAIN è una risposta pulita che dnsmasq inoltra senza filtrarla.

Scartata l'alternativa di disattivare `rebind_protection`: è una protezione di
sicurezza reale, e il problema era il formato della risposta, non il controllo.

#### ✅ Esito verificato

Dopo l'inversione dell'ordine in uci, misurato sui contatori reali:

```
using nameserver 192.168.15.3#53      <- AdGuard ora e' il primo
using nameserver 1.1.1.1#53

server 192.168.15.3#53: queries sent 27
server 1.1.1.1#53:      queries sent 0
```

| Dominio | Risposta via router |
|---|---|
| `doubleclick.net` | NXDOMAIN |
| `google-analytics.com` | NXDOMAIN |
| `ads.youtube.com` | NXDOMAIN |
| `github.com` | 140.82.121.4 |
| `openwrt.org` | 64.226.122.113 |

**Da ~7% a 100% del traffico DNS attraverso AdGuard.** Filtraggio deterministico,
risoluzione dei domini legittimi intatta.

### Configurazione DNS finale

```
dhcp.@dnsmasq[0].noresolv    = 1
dhcp.@dnsmasq[0].strictorder = 1
dhcp.@dnsmasq[0].server      = '1.1.1.1' '192.168.15.3'   <- ordine INVERTITO
AdGuard blocking_mode        = nxdomain
```

⚠️ L'ordine in uci è volutamente invertito rispetto alla priorità desiderata,
perché dnsmasq costruisce la lista interna al contrario. **Dopo ogni modifica,
riverificare sui contatori** con `kill -USR1 $(pidof dnsmasq)` e `logread`:
è un dettaglio implementativo, non un comportamento garantito.

### ⏭️ Non ancora verificato: il fallback

Resta da provare lo scenario che ha originato tutto il lavoro: **con AdGuard
spento, dnsmasq ripiega davvero su `1.1.1.1`?** Con `strictorder` dovrebbe, ma
non è stato misurato. Finché non lo è, il comportamento a PVE spento resta
un'ipotesi.

## Backup delle configurazioni — operativo

Remote: `diam0nds/infra-domotica-PGB` (privato), via deploy key ed25519.
Cron: `/etc/cron.d/infra-backup`, ogni giorno alle **04:30**.
Log: `/var/log/infra-backup.log`.

```
infra/
├── README.md                    in chiaro — inventario e architettura
├── decisions.md                 in chiaro — log delle decisioni
├── scripts/
│   ├── collect-configs.sh       raccolta + commit + push
│   └── verify-encryption.sh     controllo cifratura (cancello pre-push)
├── hosts/pve/                   cifrato — /etc/pve, rete, cron, stato
├── hosts/router-master/         cifrato — vuoto, in attesa di accesso SSH
├── hosts/router-ap/             cifrato — vuoto, AP non ancora individuato
└── guests/                      cifrato — def. VM/CT + AdGuardHome.yaml
```

### Cosa NON viene raccolto, per scelta

`/etc/pve/priv/` e ogni file `*.key` (incluso `/etc/pve/pve-www.key`, che sta
fuori da `priv/`). Sono chiavi private rigenerabili in pochi minuti: il valore
di backup è basso, il danno in caso di esposizione è alto.

### Cifratura — logica fail-safe

`.gitattributes` cifra **tutto** per default, con un'allowlist esplicita di
file in chiaro. La logica inversa (elencare cosa cifrare) fallisce in silenzio:
un file nuovo che non corrisponde a nessun pattern finisce su GitHub in chiaro
senza generare alcun errore.

`collect-configs.sh` **non pusha** se `verify-encryption.sh` non passa. La
verifica clona il repo senza chiave e controlla che ogni file fuori allowlist
inizi con l'header `\0GITCRYPT\0`.

⚠️ **Rieseguire `verify-encryption.sh` dopo ogni modifica a `.gitattributes`.**

Verifiche eseguite il 2026-08-08 su clone reale da GitHub: 35 file cifrati,
6 in chiaro (solo documentazione e script), 0 sorprese, 0 hash o credenziali
in tutta la history.

### ⚠️ Chiave git-crypt

`/root/git-crypt-infra.key` — **senza, i backup sono illeggibili**. Deve stare
fuori dalla macchina: se muore la eMMC si perdono insieme macchina e chiave.

## Lacuna aperta: nessun backup delle VM

`/etc/pve/vzdump.cron` è **vuoto**: non esiste alcun backup programmato di VM
e container. Il repo salva le *configurazioni*, non i dati — la VM Home
Assistant (32 GB, con storico, automazioni e integrazioni) non ha nessuna
copia. Se la eMMC cede, si perde tutto.

Da affrontare, tenendo presente che ~14 GB liberi nel volume group non bastano
per un vzdump completo in locale: serve una destinazione esterna.

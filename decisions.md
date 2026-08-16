# Log delle decisioni

---

## 2026-08-11 — ✅ Backup dei dati VM e container: attivo su storage locale

**Decisione**: job PVE nativo `pgb-daily`, ogni giorno alle **02:30**, storage
`local`, modalità **snapshot**, compressione **zstd**, ritenzione
`keep-daily=5,keep-weekly=3`.

**Motivo**: non esisteva **nessun** backup dei dati — confermato da entrambi i
meccanismi (`/etc/pve/jobs.cfg` assente, `vzdump.cron` vuoto). Era l'unica voce
aperta che separava "perdere tutto" da "non perderlo": le configurazioni erano
salvate, i dati no.

### Numeri reali, misurati non stimati

| | |
|---|---|
| VM 100 Home Assistant | 32 GiB scanditi a 93,4 MiB/s → **1,36 GB** compressi, 5:53 |
| CT 101 AdGuard | **319 MB**, 1:01 |
| Totale per set | **~1,7 GB**, ~7 minuti |
| Ritenzione piena (8 set) | ~14 GB su 31 GB liberi |
| Carico di picco | **13.17** su 4 core — la eMMC legge e scrive insieme |

Servizi verificati **durante** il backup: DNS e Home Assistant rispondevano.
Il guest agent risponde, quindi lo snapshot è coerente a livello di filesystem
(`fsfreeze` prima, `resuming VM again` dopo) e la VM non si ferma.

### Ripristino verificato, non solo dichiarato

`vzdump` che scrive "finished successfully" non è una prova. Eseguito un
**ripristino reale** del container su VMID 999:

```
hostname adguard, rootfs 2G
/opt/AdGuardHome/AdGuardHome.yaml   presente, 4069 byte
blocking_mode: nxdomain            <- la modifica fatta lo stesso giorno
```

Il backup contiene lo stato **corrente**. Il container di prova è stato
**montato in sola lettura e non avviato**: ha lo stesso MAC dell'originale
(`BC:24:11:3E:76:8D`) e avviarlo avrebbe creato un conflitto in rete. Rimosso
dopo la verifica.

### ⚠️ Due correzioni a mie affermazioni precedenti

1. **"I ~14 GB liberi non bastano per un vzdump locale, serve una destinazione
   esterna"** — falso. Confondevo lo spazio libero del thin pool LVM con lo
   storage `local`, che sta sul filesystem di root con **33 GB liberi** ed era
   **già** configurato con `content backup`. E i dati reali sono 7,5 GB, non 32:
   il disco della VM è thin provisioned. Questo errore ha rimandato un intervento
   importante per un ostacolo inesistente.
2. **"Ogni stacco a caldo logora la eMMC"** — ripetuto più volte, infondato.
   Misurato con `mmc extcsd read`: `Life Time Estimation A e B = 0x01` (0-10% di
   vita consumata), `Pre EOL = 0x01` (normale). La eMMC è praticamente nuova. Il
   rischio degli stacchi a caldo è la **corruzione nell'istante del taglio**, un
   guasto che quei contatori non misurano — il backup protegge da quello.

### Cosa questo backup NON copre

Protegge da corruzione della VM, aggiornamenti sbagliati, errori di
configurazione, cancellazioni. **Non** protegge da morte della eMMC, furto o
incendio: sta sullo stesso disco dei dati.

Una destinazione esterna resta da fare, e il carico di picco 13.17 è un
argomento in più — con un NAS o un disco USB la eMMC non farebbe lettura e
scrittura contemporanee.

### Limite noto della pianificazione

Un job PVE a orario fisso **non recupera le esecuzioni perse**: se la macchina è
spenta alle 02:30, quel backup salta. È lo stesso difetto già visto sul backup
delle configurazioni, risolto là con un `@reboot`. Qui non c'è un equivalente
nativo: da valutare se aggiungerne uno.

---

## 2026-08-11 — ✅ Upgrade PGB-GW da 21.02.3 a 24.10.8: ESEGUITO

**Decisione**: `sysupgrade` mantenendo la configurazione, in **sessione
presidiata**, senza acquistare un secondo apparato.

**Esito**: riuscito. Kernel da 5.4.188 a 6.6.144, firewall da fw3/iptables a
fw4/nftables (202 regole), 162 pacchetti, 0 aggiornabili. Entrambi i tunnel
WireGuard con handshake, 17/17 dispositivi IoT, DNS con filtraggio attivo, reti
di CASA raggiungibili.

**Alternativa scartata dall'utente**: preparare un secondo apparato al banco e
sostituirlo (~30-40 €), che avrebbe azzerato il rischio sul sito in produzione.
L'utente ha scelto il flash diretto accettando il rischio, con il patto di
ripristinare a mano guidato passo a passo.

### Cronologia della scrittura

```
+  5s   ping su    (sysupgrade gira da ramfs, sta ancora scrivendo)
+ 10s   ping giu   (scrittura flash e riavvio)
+ 78s   ping su    versione 24.10.8, SSH con la chiave preservata
+150s   17/17 dispositivi IoT rientrati, Midea 3/3
```

⚠️ Il ping che risponde a +5s **non significa che l'upgrade sia finito**: durante
`sysupgrade` il sistema gira da ramfs e la rete resta su mentre scrive la flash.
Il segnale valido è la versione, non la raggiungibilità.

### Cosa ha funzionato della preparazione

- **`sysupgrade -T`** (exit 0) e **`compat_version` 1.1 su entrambi i lati**: i
  due controlli autorevoli che hanno dato il via libera al mantenimento della
  config. Il messaggio "device 1.0, cannot migrate swconfig to DSA" nei metadati
  era il testo-modello dell'immagine, non la nostra situazione.
- **L'insieme di 21 pacchetti offline**: installazione senza un solo errore né
  dipendenza mancante. Senza, i due tunnel sarebbero rimasti giù con l'unica via
  di ripristino che passava dal router appena riflashato.
- **L'inventario via `/overlay/upper`**: ha trovato `luci-proto-wireguard` e
  `luci-app-wireguard`, che il mio primo elenco basato su filtri per nome aveva
  perso, e due chiavi WireGuard obsolete in `/root` da cancellare.
- **La regola dei 3 minuti**: a +120 s i Midea erano ancora assenti, a +150 s
  tutti rientrati. Concludere prima avrebbe prodotto un falso allarme.

### Due intoppi, entrambi miei

1. **`nohup` non esiste** nella BusyBox di 21.02: il primo tentativo di lanciare
   il flash distaccato è fallito con `ash: nohup: not found` **senza toccare
   nulla**. Su 24.10 `setsid` esiste, `nohup` ancora no. La forma corretta è
   eseguire `sysupgrade` in modo **sincrono**: `stage2` fa `exec` in una shell su
   ramfs, quindi sopravvive per progetto alla caduta della sessione SSH, e
   tenendo la connessione aperta nessun SIGHUP può interromperlo a metà.
2. Dopo l'installazione dei pacchetti i tunnel non salivano: **netifd carica gli
   handler `proto` solo all'avvio**, e `wireguard.sh` era arrivato dopo.
   `ubus call network reload` non basta, serve `/etc/init.d/network restart` —
   da lanciare distaccato con `setsid`, perché rimbalza `br-lan`.

### ⚠️ I nomi delle interfacce WiFi sono cambiati

```
21.02:  wlan0, wlan0-1, wlan0-2, wlan1
24.10:  phy0-ap0, phy1-ap0
```

Ogni comando che cita `wlan0` **fallisce silenziosamente** su PGB-GW. Gli script
che enumerano con `iw dev` si adattano da soli; quelli con nomi cablati no.

Formato: data, decisione, motivo. Le decisioni **non** vanno riaperte senza
un motivo nuovo — se una scelta è qui, è già stata discussa.

---

## 2026-08-08 — Riavvio dopo blackout: si risolve da BIOS, non via software

**Decisione**: cambiare `Restore on AC Power Loss` da `Power Off` a `Power On`
dal BIOS, appena disponibile una tastiera USB.

**Alternative valutate e scartate**:
- *Wake-on-LAN*: supportato dalla NIC ma disabilitato. Scartato perché dopo un
  taglio AC completo la standby power sparisce e la NIC viene reinizializzata
  dai default del BIOS — inaffidabile proprio nello scenario che conta. In più
  Home Assistant gira sul PVE stesso, quindi non può risvegliarlo.
- *Modifica BIOS da Linux*: impraticabile. `/sys/class/firmware-attributes`
  non esiste su questo AMI, e la variabile UEFI `Setup` non è esposta a
  runtime in efivarfs.
- *AMISCE / `scelnx_64`*: funzionerebbe, ma è distribuito solo agli OEM — il
  binario reperibile online è di provenienza incerta e girerebbe come root
  sull'hypervisor. Scartato per sicurezza.
- *UEFI Shell + `setup_var.efi` via `startup.nsh`*: tecnicamente possibile
  (Secure Boot off, ESP libero), ma richiede IFR extraction per l'offset
  esatto; un offset sbagliato corrompe la NVRAM e servirebbe un clear CMOS
  aprendo il case. Rischio sproporzionato rispetto a una tastiera da 8€.
- *Relè ESP32/Shelly sul power header*: soluzione robusta e adatta al contesto
  domotico, ma richiede comunque di aprire il case. Tenuta come piano B.

**Motivo della scelta**: è l'intervento a rischio più basso e risolve la causa
invece del sintomo.

---

## 2026-08-11 — Site-to-site resta sulla 51821, rimossa la regola DNAT

**Decisione**: `listen_port='51821'` (invariata) e **rimozione** della regola
`WG-s2S`, che faceva DNAT di UDP 51821 verso `10.10.10.2` — l'indirizzo del
router stesso sull'interfaccia del tunnel.

**Motivo**: il tunnel era fermo da giorni. Misurato: 31.703 pacchetti inviati
verso l'endpoint corretto, zero risposte, flusso `[UNREPLIED]`. Disabilitata la
regola DNAT, la 51821 funziona senza alcuna modifica: handshake immediato,
traffico bidirezionale.

Verificati e scartati prima, con misure: chiavi di peer e di istanza da entrambi
i lati, assenza di preshared key, porta di destinazione, DDNS, endpoint,
raggiungibilità del sito remoto.

### ⚠️ Diagnosi intermedia sbagliata, da non ripetere

Per alcune ore la causa è stata attribuita alla **porta 51821**, perché
cambiarla a 51900 faceva salire il tunnel. Conclusione errata: la porta nuova
funzionava solo perché non veniva intercettata dal DNAT. Era stata anche
ipotizzata una mappatura NAT residua sul router del provider — ipotesi
infondata.

Il DNAT era stato individuato *per primo* e poi indebolito con il ragionamento
"il traffico ESTABLISHED non attraversa il DNAT, quindi non può essere lui".
Quel ragionamento è **falso nei fatti**. Il meccanismo esatto resta non
verificato; la misura è inequivocabile.

**Lezione**: quando una misura contraddice un ragionamento teorico, vince la
misura. Il vantaggio di mantenere l'ipotesi scartata sul tavolo è che il test
del cambio porta — pensato per un'altra ragione — l'ha involontariamente
confermata.

Vantaggio pratico di restare sulla 51821: **non serve toccare nulla su
OPNsense**, il cui endpoint punta già a quella porta.

---

## 2026-08-08 — Niente stack di monitoraggio

**Decisione**: nessun Prometheus / Grafana / InfluxDB / Zabbix.

**Motivo**: richiesta esplicita dell'utente ("non mi interessano agenti di
monitoraggio complicati"), e vincolo hardware reale — lo storage è **eMMC** e
i tool di monitoraggio scrivono in continuo. Con 4 GB di RAM liberi e un
J3710 non c'è nemmeno margine di CPU. Se servirà visibilità, si sceglierà
qualcosa di leggero e parco in scrittura.

---

## 2026-08-08 — Backup config su GitHub: solo cifrato

**Stato**: ✅ approvato e implementato.

**Implementazione**: repo GitHub privato `diam0nds/infra-domotica-PGB` +
`git-crypt` sui percorsi elencati in `.gitattributes`.

Accesso via **deploy key** ed25519 dedicata (`/root/.ssh/id_ed25519_github`),
alias SSH `github-infra`. Scelta al posto di un PAT perché è limitata al
singolo repository e non scade, quindi il cron non si rompe alla scadenza.

Chiavi separate per scopo — se una trapela non compromette le altre:

| Chiave | Uso |
|---|---|
| `id_ed25519_github` | solo push su questo repo |
| `id_ed25519_infra` | solo nodi OpenWrt |
| `id_rsa` | preesistente, cluster Proxmox — non riusata |

Host key di github.com installate in `known_hosts` con fingerprint verificati
contro quelli pubblicati da GitHub (ED25519 e RSA, entrambi corrispondenti):
niente TOFU cieco al primo collegamento.

### Verifica della cifratura — eseguita, non assunta

Prima di pushare qualsiasi configurazione reale è stato committato un file
`secrets/canary.txt` con un valore fittizio riconoscibile, poi clonato il repo
da GitHub **senza** la chiave git-crypt. Risultato:

- il valore in chiaro **non** compare nel clone
- il file risulta binario, con header `\0GITCRYPT\0`
- zero occorrenze del valore in tutta la history (`git log --all -p`)
- i file non sensibili (README, decisions) restano leggibili in chiaro

Il canary resta nel repo come artefatto di prova: contiene solo un valore
fittizio. **Ripetere questa verifica dopo ogni modifica a `.gitattributes`** —
git-crypt cifra solo ciò che il pattern intercetta, e un pattern sbagliato
fallisce in silenzio, pushando segreti in chiaro senza alcun errore.

### ⚠️ Chiave git-crypt

Esportata in `/root/git-crypt-infra.key`. **Senza quel file i backup sono
illeggibili.** Deve stare fuori dalla macchina (password manager): se muore la
eMMC si perdono insieme la macchina e la chiave, e il repo diventa inutile.

**Motivo**: le configurazioni contengono password WiFi in chiaro, hash di
root, chiavi private del cluster Proxmox e credenziali AdGuard. Un push su
GitHub li porta su un servizio esterno, dove restano nella cronologia git
anche dopo un'eventuale cancellazione. Il repo privato da solo non basta: un
token compromesso o un cambio di visibilità accidentale esporrebbe tutto.

---

## Tre repo invece di uno — 2026-08-11

Con l'arrivo di CASA il repo unico `infra-domotica-PGB` è stato diviso in
**`infra-common`** (metodo e script, non cifrato), **`infra-pgb`** e
**`infra-casa`** (dati di sito, cifrati con **due chiavi git-crypt distinte**).

**Motivo decisivo, misurato non supposto**: `collect-configs.sh` committa e
pusha senza fare `pull` né `rebase` (zero occorrenze nello script). Con un repo
solo scritto da due macchine, la seconda push della notte viene rifiutata per
non-fast-forward, lo script riprova tre volte, esce con 1 e scrive il fallimento
in `/var/log/infra-backup.log`, che nessuno legge. Il backup si fermerebbe in
silenzio continuando a sembrare attivo: il fail-open che `MODUS-OPERANDI.md` §5
vieta. **Ogni repo cifrato ha un solo scrittore.**

**Alternative valutate e scartate:**

- **Un repo con layer comune** (`common/`, `pgb/`, `casa/`): un posto solo da
  guardare, ma richiede `pull --rebase` nel cron di entrambi i siti, cioè merge
  automatici di file cifrati alle 04:30 su macchine non presidiate. Il rimedio
  è peggio del male.
- **Due repo completamente separati**, con `MODUS-OPERANDI.md` duplicato: più
  semplice da avviare, ma la dottrina divergerebbe. Le sue lezioni arrivano da
  entrambi i siti, e una documentazione divergente è peggio di nessuna (§9).
- **Estrarre la history** di `MODUS-OPERANDI.md` e `scripts/` in `infra-common`:
  `git filter-repo` non è installato e installarlo per un'operazione sola non si
  giustifica. `infra-common` parte da un commit iniziale che cita l'origine.

**Due chiavi git-crypt** è `MODUS-OPERANDI.md` §7 (chiavi separate per scopo)
applicato un livello sopra: se la chiave di PGB finisce nel posto sbagliato,
`assessment-casa.md` — il file il cui trapelare farebbe più danno — resta
illeggibile. La chiave B va generata sul PVE di CASA e messa nel password
manager accanto alla prima.

### Correzioni entrate insieme alla divisione

- **`git add -A` → stage dei soli path prodotti dallo script.** Su questo host
  girano più sessioni sullo stesso working tree: l'11 agosto una raccolta ha
  committato modifiche a `router-ap` fatte da un'altra sessione, attribuendole a
  sé. Aggiunto anche un `flock`, perché due raccolte sovrapposte si rubano
  l'indice git.
- **Id delle VM non più cablati.** `qm config 100` e `pct config 101` diventano
  un'enumerazione di `qm/pct list`, e AdGuard si cerca per nome. Con gli id fissi
  su CASA non si sarebbe raccolto nulla, e qui una VM nuova sarebbe passata
  inosservata.
- **Allowlist della cifratura non più duplicata.** `verify-encryption.sh` la
  ricava dalle righe `!filter` di `.gitattributes`. Due liste da tenere allineate
  a mano erano un fail-open: chi aggiungeva un'eccezione e dimenticava lo script
  otteneva un `ESITO: OK` su un repo che pushava quel file in chiaro.
  Nel farlo è emerso che i pattern vanno iterati **quotati**: `for p in $ALLOW`
  faceva espandere `scripts/*` sui file reali prima del confronto, e i file in
  `scripts/router/` risultavano in chiaro a sorpresa. Ha fallito nella direzione
  giusta — ha bloccato invece di rassicurare.

---

## Il PVE passa dal router per il DNS — 2026-08-11

`/etc/resolv.conf` del PVE aveva **un solo nameserver, `192.168.15.3`** (AdGuard
diretto, nessun fallback). Ora: `192.168.15.1` primario, `192.168.15.3`
secondario, applicato con `pvesh set /nodes/pve/dns`.

**Come è emerso**: un `git push` è fallito con `Could not resolve hostname
github.com`. Misurato subito dopo: **tutti e tre i resolver rispondevano**
(router, AdGuard, Cloudflare) e il container AdGuard non si era mai riavviato
(`up 10:08`). Era una singola risposta persa — e senza un secondo nameserver una
risposta persa è un guasto.

**Perché era grave più di quanto sembri**: l'unico host che violava la regola di
progetto "i client ricevono il router, non AdGuard direttamente" era proprio
quello che ospita AdGuard. Il PVE dipendeva per il DNS da un container che gira
sul PVE, saltando `strictorder`, il watchdog e il fallback pubblico. È lo stesso
schema del DDNS su Home Assistant: un servizio critico appoggiato al nodo che
può cadere.

**Perché nessuno se n'era accorto**: il DHCP non c'entrava — `resolv.conf` è
statico, quindi la verifica "nessuna interfaccia imposta `dhcp_option 6`" era
vera e insufficiente. E `test-failover.sh` interroga `dig @192.168.15.1`: ha
collaudato il percorso dei client, e il PVE non era su quel percorso. Il test era
corretto, il suo **ambito** no.

**Perché via API e non a mano**: PVE legge e scrive `/etc/resolv.conf` dalla
propria API. Modificandolo a mano la vista del nodo resta disallineata e una
modifica futura dalla GUI riporta indietro il file senza dire nulla.

Verificato dopo: risoluzione via glibc, `git fetch` su entrambi i repo, e
`doubleclick.net` ancora bloccato — le query passano davvero dal router e poi da
AdGuard. Il PVE ora eredita il failover già collaudato. Copia del file
precedente in `/root/resolv.conf.pre-2026-08-11`.

**Non misurato**: il passaggio automatico al secondo nameserver quando il router
tace. È comportamento standard di glibc, non l'ho provato. Se il router tace,
però, il problema è più grande del DNS.

## Il fallimento del backup è diventato visibile — 2026-08-11

`collect-configs.sh` usciva con 1 e scriveva in `/var/log/infra-backup.log`, che
nessuno legge: un backup fermo continuava a sembrare attivo. Ora ogni uscita per
errore lascia **due tracce che non vanno cercate**:

- una riga in `journalctl -t infra-backup` con priorità `daemon.err`;
- il file `BACKUP-FALLITO.txt` nella directory del repo, con motivo e comandi di
  diagnosi. **La riuscita lo cancella**, quindi la sua presenza significa
  "l'ultima esecuzione è andata male", non "è andata male una volta". In
  `.gitignore`, e citato in `CLAUDE.md` perché una sessione lo veda subito.

Niente agenti di monitoraggio: l'utente li ha esclusi e la eMMC non li
sopporterebbe. Questo costa una `logger` e un file per esecuzione fallita, zero
scritture quando va bene.

### Difetto trovato provando il guasto, non il funzionamento

Provando il percorso di errore è venuto fuori che il commento *"verranno inviati
alla prossima esecuzione"* era **falso**. Lo script usciva con 0 appena non
trovava modifiche nei path raccolti, **prima** di arrivare al push: un commit
creato da un'esecuzione il cui push era fallito restava locale **per sempre**,
perché la volta dopo non c'era nulla di nuovo da committare. Difetto presente
dall'8 agosto, invisibile finché si provava solo il percorso felice.

Corretto: quando non c'è nulla da committare lo script confronta `origin/main`
con `HEAD` e, se ci sono commit mai inviati, procede al push. Verificato sul
repo di prova: prima esecuzione blocca e segnala, seconda **riprova** e segnala
di nuovo, uscita 1 in entrambi i casi.

## 2026-08-12 — Backup della configurazione degli Shelly (sessione presidiata)

**Decisione**: gli Shelly entrano nel backup cifrato giornaliero via `GET
/settings` (API Gen1), in sola lettura, dalla lista dei lease statici del router.

**Perché la lista dai lease e non un elenco nello script**: quando si aggiunge un
dispositivo lo si registra comunque nei lease statici. Un elenco scritto dentro lo
script sarebbe la seconda copia della stessa informazione, e resterebbe indietro
in silenzio — il dispositivo nuovo semplicemente non verrebbe salvato, senza che
nulla lo segnali.

**Perché non un backup completo del dispositivo**: gli Shelly Gen1 non espongono
un export/import della configurazione. `/settings` è ciò che si può leggere, e
copre quello che costa tempo rifare a mano: calibrazione delle tapparelle
(`maxtime_open`/`maxtime_close`, misurati 31,0 s sulla tapparella cucina), nomi,
pianificazioni, MQTT. Non è un'immagine ripristinabile con un comando: è la
scheda tecnica da cui riconfigurare un sostituto.

### La lezione, che è la stessa di altre sette volte

L'avviso "dispositivi in meno rispetto alla raccolta precedente" **non poteva
scattare**: `collect-configs.sh` fa `rm -rf guests/` prima della raccolta, quindi
il conteggio "prima" era sempre 0. Il codice sembrava corretto e avrebbe stampato
per mesi una riga rassicurante senza controllare niente.

Trovato perché l'output diceva `(erano 0)` quando i file c'erano — un dettaglio
che non tornava, non un test. Corretto leggendo il termine di confronto da `git
ls-files`, cioè dall'ultima raccolta committata, e **verificato togliendo un file
a mano**: l'avviso scatta e nomina il dispositivo.

Ottavo strumento di verifica mio che accusava o assolveva senza guardare. La
regola resta quella: **prima di credere a un allarme — o a un via libera —
provare lo strumento che l'ha prodotto, facendogli vedere il caso che deve
riconoscere.**

## 2026-08-12 — NAS di CASA: copia fuori sito misurata, non stimata

**Sessione presidiata.** Esportazione `/volume1/backup-pgb` su `192.168.10.5`,
autorizzata al solo `192.168.15.5`, creata dalla sessione di CASA.

**Decisione: montaggio temporaneo, mai in `fstab`.** Su un sito normalmente non
presidiato un NFS irraggiungibile con opzioni `hard` blocca i processi che lo
toccano e trascina giu' `pvestatd` e l'interfaccia del PVE. Si monta per la
durata della copia, si smonta subito.

**Numeri misurati** (non stimati: copia reale di un vzdump vero):

| Grandezza | Valore |
|---|---|
| Protocollo | **NFSv3** — il Synology rifiuta `vers=4.1` ("Protocol not supported") |
| Copia | 319 MB in 227 s = **1,41 MB/s = 11,2 Mbit/s** |
| Upload WAN sotto carico | 17 Mbit/s (payload + incapsulamento WireGuard) |
| Latenza | 18,5 ms sotto carico contro 15,7 a riposo, **0% perdita** |
| Integrita' | impronte md5 **identiche** |
| Proiezione set completo 1,7 GB | **circa 20 minuti** |

**Parametri di mount che funzionano**: `soft,timeo=600,retrans=5,noatime,vers=3`.

`timeo` e' in **decimi di secondo**: il primo tentativo con `timeo=100` dava 10
secondi, e la `close()` di un file da 320 MB — che su NFS svuota tutta la cache
in una volta — sforava. Il mount `soft` abortiva un'operazione **lenta**
scambiandola per un guasto. Non era il NAS: era il mio parametro.

### Cosa non va messo in produzione

**La verifica per rilettura.** Ricalcolare l'impronta del file remoto significa
riscaricare tutto attraverso il tunnel: raddoppia la finestra notturna da 20 a
40 minuti. Verifica completa **settimanale**, dimensione e data le altre notti.

**Il `dd` per misurare.** Dandogli 300 MB da svuotare su un link lento si e'
piantato in stato `D` (`folio_wait_bit_common`) oltre il timeout, perche' un
processo in I/O NFS non muore al segnale finche' la RPC non scade. Nessun danno
— i servizi del PVE non si sono mai fermati — ma per misurare si usa `rsync`,
che gestisce gli errori, non `dd`, che accumula e basta.

### Cifratura a riposo: no, e il perche'

La sessione di CASA ha creato la cartella **in chiaro**, motivandolo: una
condivisione cifrata va sbloccata a mano dopo ogni riavvio del NAS e fino ad
allora non e' esportata, quindi su un sito non presidiato i backup si fermano in
silenzio. Concordato. I vzdump restano non cifrati su un NAS in casa
dell'utente; se un giorno servisse, la cifratura si fa lato PGB prima della copia.

Sul NAS resta la copia del container AdGuard (335 MB), integra e verificata:
**e' l'unica copia fuori sito esistente al momento**, quindi non la si cancella.

## 2026-08-12 — Split DNS per Home Assistant: un solo URL, certificato valido

**Sessione presidiata.** Obiettivo: replicare su PGB la configurazione che
funziona su CASA — nell'app un solo URL, campo interno vuoto.

**Fatto**: riscrittura locale in dnsmasq sul router master.

```
uci add_list dhcp.@dnsmasq[0].address='/<nome duckdns>/192.168.15.4'
```

Verificato con validazione piena del certificato: **HTTP 200,
`ssl_verify_result 0`**. Nessun avviso nell'app o nel browser, perche' il
certificato Let's Encrypt del reverse proxy e' emesso proprio per quel nome.

### L'eccezione anti-rebinding NON era necessaria

Avevo previsto di dover aggiungere `rebind_domain` per quel dominio, perche'
`rebind_protection=1` scarta le risposte che mappano un nome pubblico su un
indirizzo privato. **Misurato: non serve.** La protezione filtra le risposte
ricevute **dagli upstream**; una voce `address=` e' una risposta locale
autorevole e non passa da quel filtro.

Una modifica in meno sul sistema piu' delicato dell'impianto. La regola: prima
di aggiungere un'eccezione a una protezione, **provare se serve davvero**.

### Perche' in dnsmasq e non in AdGuard

- Tutti i client — LAN, IoT e ospiti — ricevono **il router** come DNS, quindi
  una riscrittura sul router copre tutti senza toccare altro.
- Non richiede di riavviare AdGuard, che e' il single point of failure del DNS.
- Sopravvive al watchdog: se AdGuard muore e `dns-watchdog` sposta l'upstream su
  `1.1.1.1`, la voce locale continua a rispondere.

### ⚠️ Effetto collaterale da conoscere

Il nome ora risolve a un indirizzo **privato** anche per i client sulla WiFi di
casa. Un client WireGuard che provi ad alzare il tunnel **stando sulla rete di
PGB** risolverebbe l'endpoint a `192.168.15.4:51820`, dove non c'e' WireGuard,
e il tunnel fallirebbe.

Non e' un problema in esercizio — a casa la VPN non serve — ma va saputo: sul
telefono la VPN va configurata per **non** salire sull'SSID di casa.

Verificato che i tunnel dell'infrastruttura **non** sono toccati: il
site-to-site usa `endpoint_host` con il nome di **CASA**, non quello di PGB, e i
peer road-warrior non hanno endpoint (si collegano loro).

### Conseguenza sull'external_url, che annulla un mio consiglio precedente

Avevo proposto di **svuotare** `external_url` perche' puntava a un indirizzo che
non rispondeva da nessuna posizione. Ora quel nome **risponde**: dall'interno via
split DNS e da fuori attraverso il tunnel. Quindi `external_url` e' corretto
com'e' e va lasciato. `internal_url` resta `http://192.168.15.4:8123`
deliberatamente: e' il percorso piu' robusto per i link generati da Home
Assistant, indipendente dal DNS.

### Gap trovato: `safe-change.sh` non e' installato sul router

Lo script del dead-man's switch sta in `infra-common/scripts/router/` ma **non
e' mai stato deployato** su PGB-GW: `safe-change status` non e' richiamabile.
Per questa modifica e' stato usato un involucro auto-ripristinante sincrono
(backup, applica, ricarica, verifica tre cose, ripristina se una fallisce), che
per una modifica al DNS e' anche piu' adatto — non si rischia di perdere la
sessione, e il guasto temuto e' il DNS di casa, verificabile subito.

Resta da installarlo per le modifiche che **possono** tagliare l'accesso
(rete, firewall, wireless). Aggiunto in ROADMAP.

## 2026-08-12 — Esporre Home Assistant di PGB su internet: scelta dell'utente

**Sessione presidiata. Decisione dell'utente**, presa dopo che l'obiezione era
stata messa sul tavolo e discussa. Registrata qui con il contesto perche' fra sei
mesi si sappia **cosa era noto al momento della scelta**.

### Le alternative offerte

1. **VPN automatica** — WireGuard che sale da se' fuori casa. Zero esposizione,
   nessuna modifica a router o modem, solo configurazione del telefono.
2. **Cloudflare Tunnel** — funziona senza VPN e senza aprire porte (e' il server
   che esce), aggira il doppio NAT, si puo' mettere autenticazione davanti.
   Dipende da un servizio esterno e da un add-on in piu'.
3. **Port forward** — scelta dell'utente. Identico a CASA.

### Cosa comporta, detto prima di farlo

Home Assistant diventa raggiungibile da internet 24 ore su 24. HA comanda **cose
fisiche**: serrature, riscaldamento, tapparelle. Una compromissione non e' una
fuga di dati, e' un problema di sicurezza fisica dell'abitazione.

Il fattore aggravante specifico di PGB: **e' una seconda casa, di norma non
presidiata per settimane.** Quando esce una vulnerabilita' di Home Assistant o
del reverse proxy, qui nessuno aggiorna in giornata. Per confronto, WireGuard
non risponde affatto a chi non ha la chiave: uno scanner vede una porta muta.

**L'utente ha scelto consapevolmente il port forward.** Non e' una svista, e non
va "corretto" da una sessione futura senza riparlarne con lui.

### Fatto

Su PGB-GW, regola DNAT `HA-HTTPS-da-internet`: `wan` TCP 443 ->
`192.168.15.4:443`. Applicata con backup e verifica automatica.

Verificato **specificamente** che i due tunnel WireGuard siano sopravvissuti,
perche' e' il punto in cui si e' gia' sbagliato: la regola DNAT `WG-s2S` aveva
rotto il site-to-site l'8 agosto. Entrambi con handshake recente e contatori di
traffico in crescita dopo la modifica.

`fw4` genera da se' le regole di **reflection** per `192.168.9.0/24` e
`192.168.15.0/24`: non servono, perche' dall'interno risolve lo split DNS, ma non
danno fastidio.

Contatore della regola: **0 pacchetti**. La regola e' inerte finche' non si
inoltra anche sul modem: quel passo richiede le credenziali del modem
dell'operatore e lo fa l'utente.

### Mitigazioni non opzionali

Con la porta aperta, queste tre cose non sono consigli ma requisiti:

1. **2FA (TOTP) su tutti gli account** di Home Assistant, non solo il principale.
2. **`ip_ban_enabled: true`** e `login_attempts_threshold` basso in
   `configuration.yaml`. Senza, la pagina di login accetta tentativi illimitati.
3. **Aggiornamenti regolari** di Home Assistant e dell'add-on del proxy. Su un
   sito non presidiato questo e' il punto piu' debole della catena.

Da verificare che siano attive: non sono ispezionabili via API.

### Nota pratica sul modem

Molti modem degli operatori usano la 443 per la **propria** amministrazione
remota e non la lasciano inoltrare. Se accade, si inoltra una porta esterna alta
(es. 8443) verso `192.168.51.2:443` e l'URL nell'app diventa `https://<nome>:8443`
— che e' con ogni probabilita' il motivo per cui **CASA usa proprio la 8443**.

## 2026-08-12 — Prima di aprire la porta: 27 token di accesso attivi

Emerso perche' l'utente ha ricordato che il reverse proxy e' l'add-on NGINX
dentro Home Assistant. Quel dettaglio ha due conseguenze, entrambe rilevanti
adesso che la 443 sta per essere esposta.

### 1. Con un proxy davanti, `ip_ban` puo' chiudere fuori tutti

Home Assistant vede come indirizzo del client quello del **proxy**, non quello
vero, a meno che nel `configuration.yaml` ci sia:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.30.33.0/24     # rete interna degli add-on
```

Se manca e si attiva `ip_ban_enabled` con una soglia, ogni tentativo falliti da
internet appare provenire dal proxy: dopo N tentativi Home Assistant **banna il
proxy**, e nessuno entra piu' da quella strada. Su un sito non presidiato e'
un'autoesclusione. Si recupererebbe da `http://192.168.15.4:8123` in VPN,
modificando `ip_bans.yaml`.

**Evidenza raccolta, forte ma non conclusiva**: in 4301 righe di log e nei 27
token attivi **non compare nessun indirizzo `172.30.x`**, e non c'e' alcun avviso
"untrusted proxy" nonostante il traffico attraverso il proxy sia certamente
avvenuto. Indica che la configurazione c'e'. Non e' una prova: HA non registra
`last_used_ip` per i token a lunga durata, quindi il test diretto non conclude.
**Verificare leggendo `configuration.yaml` prima di attivare `ip_ban`.**

### 2. 27 refresh token attivi, e un solo account umano

| Account | Ruolo |
|---|---|
| `Luca` | **admin, umano** — l'unico non di sistema |
| `Supervisor` | di sistema, admin |
| `Home Assistant Content` | di sistema, sola lettura |
| `mqtt user` | non admin, gruppo `system-users` — privilegio minimo, corretto |

I 27 token si distribuiscono su **10 indirizzi client diversi**, fra cui 8 da
`192.168.49.169` (intervallo Wi-Fi Direct / hotspot Android), 3 da
`192.168.10.115` (**rete di CASA**) e uno mai usato.

**Un refresh token scavalca password e 2FA.** Attivare la 2FA lasciando vivi 26
token vecchi non protegge da chi ne possiede uno: vecchi telefoni, browser su
macchine dismesse, dispositivi passati ad altri. Con la porta aperta su internet
questa e' la superficie d'attacco piu' grande, e ripulirla non costa nulla.

**Ordine corretto delle operazioni**, che non e' indifferente:

1. **Revocare i token** non riconosciuti (profilo di Home Assistant)
2. **Attivare la 2FA** su `Luca` — dopo il punto 1, altrimenti e' aggirabile
3. **Verificare `trusted_proxies`**, poi attivare `ip_ban`
4. **Solo allora** l'inoltro sul modem

Nota a margine dal log: errori ricorrenti `DeviceConnectionError` su
"Tapparella bagno" (`components.shelly`) l'11 agosto. Da guardare a parte.

## 2026-08-12 — Revocati 24 dei 27 token, e la porta era gia' aperta

**Scoperta durante la preparazione**: il contatore della regola DNAT, che alla
creazione era a 0, e' passato a **5 pacchetti**. Il modem dell'operatore
**inoltrava gia'** la 443 verso `192.168.51.2`: prima della regola quei pacchetti
arrivavano a PGB-GW e venivano scartati dalla zona `wan` (`input REJECT`), ed e'
per questo che da remoto non funzionava.

Conseguenza: aggiungendo la regola, PGB e' diventata **immediatamente esposta**,
prima delle mitigazioni. Non era l'ordine approvato dall'utente, che metteva
l'inoltro al punto 4. **Regola disattivata** (`enabled=0`, non cancellata) in
attesa che i punti 1-3 siano completi. Verificato che sia uscita dal ruleset
nftables e che i due tunnel siano integri.

### Punto 1 fatto: 24 sessioni revocate su 27

Criterio dettato dai dati, non scelto a mano: si tiene cio' che e' stato usato
negli ultimi due giorni, piu' il token di servizio della raccolta notturna.

| Ultimo uso | Sessioni revocate |
|---|---|
| 2022 | **21** |
| 2024 | 2 |
| 2026 (3 luglio) | 1 |

Ventuno credenziali vive e inutilizzate **da quattro anni**. Un refresh token
scavalca password e 2FA, quindi erano 21 modi di entrare che nessuna mitigazione
sul login avrebbe fermato.

Rimasti 3: la sessione del browser in uso, l'app mobile, e il token di servizio.
Verificato subito dopo che l'accesso REST e WebSocket funzioni ancora e che il
bridge Zigbee sia visibile: la raccolta notturna non e' stata rotta.

Nota storica emersa dalle date: i token del 2022 puntano a
`http://192.168.10.176:8123` e `http://192.168.15.3:8123`. Questa istanza di Home
Assistant ha quindi vissuto **prima sulla rete di CASA**, poi su un altro
indirizzo di PGB, prima dell'attuale `192.168.15.4`. Utile sapere che l'impianto
e' stato migrato, quando si guarderanno configurazioni vecchie.

## 2026-08-14 — La rete IoT giu' per due giorni: causa, catena e due difetti miei

**Sessione presidiata.** Trovato riprendendo il lavoro: **zero Shelly
raggiungibili, 17 voci ARP `FAILED`, Zigbee2MQTT in stato `error`**.

### La catena, dall'inizio

1. **Il router si riavvia.** Causa poi chiarita dall'utente: stava facendo prove
   e ha **staccato il cavo un paio di volte** quella mattina. Nessun guasto.
2. Al boot **dnsmasq parte prima che salgano le radio WiFi**. La rete IoT vive
   direttamente su `phy0-ap0`, che in quel momento non esiste: il suo
   `dhcp-range` **non viene generato**, e nessuno lo ritenta dopo.
3. I dispositivi si associano correttamente — 16 su 16 autorizzate, handshake WPA
   completo — ma **nessuno ottiene un indirizzo**. Senza indirizzo non c'e' ARP,
   quindi nemmeno il router li raggiunge.
4. **Zigbee2MQTT perde il socket** verso il coordinatore `192.168.16.10:8888`,
   crasha su un errore secondario del suo logger (`write after end` in winston) e
   resta in `error`. La rete Zigbee non e' gestita da nessuno.

E' la fragilita' prevista dal progetto VLAN: **la rete IoT sull'interfaccia
wireless invece che su un bridge**. Un bridge esiste al boot indipendentemente
dal WiFi; un'interfaccia AP no.

### Ripristino

`/etc/init.d/dnsmasq restart` (rigenera il range ora che l'interfaccia esiste),
deautenticazione delle stazioni per forzare il DHCP, `ha addons restart` di
Zigbee2MQTT. Esito: **17 lease, 12 Shelly su 12, bridge Zigbee risponde, 4
dispositivi Zigbee di nuovo online**.

⚠️ **`bridge_connection_state` in Home Assistant diceva `on` mentre Z2M era
morto**: era un messaggio MQTT **retained**, l'ultimo pubblicato prima di
crashare. Il segnale che smaschera la bugia sono le entita' `linkquality`: zero
significa nessun dispositivo Zigbee esposto. **Non fidarsi di uno stato retained
per giudicare se un servizio e' vivo.**

### Difetto mio numero 1: una guardia che vede i cambiamenti non vede gli stati

La raccolta notturna **aveva rilevato** il guasto e scriveva `shelly: 0
dispositivi raccolti (nella raccolta precedente: 0)`. Nessun avviso, perche' la
guardia confrontava solo la **transizione** (`-lt`): dopo il primo giro a zero ha
taciuto per sempre. Il guasto e' diventato invisibile proprio quando era totale.

Corretto: due controlli distinti, uno sullo **stato** (zero e' sempre anomalia) e
uno sulla **transizione** (un calo parziale indica dispositivi singoli). Nuova
funzione `anomalia()`, che scrive nel journal con tag `infra-backup` — canale che
`CLAUDE.md` prescrive di leggere a inizio sessione — e **non** scrive
`BACKUP-FALLITO.txt`, che significa un'altra cosa: quello dice "la copia fuori
casa e' vecchia", qui la copia era aggiornata ed era il contenuto a mancare.

Ha funzionato al primo giro su un guasto vero: ha intercettato l'export Zigbee
scaduto.

### Difetto mio numero 2: un backup che cancella da solo

`rm -rf "$REPO/guests"` prima della raccolta e' giusto per VM e container, ma per
i dispositivi e' una trappola. **La perdita si e' materializzata**: il commit
`0e06c8f` delle 09:22 ha cancellato `coordinator_backup.json` da HEAD, e l'ultima
copia buona e' rimasta solo nella storia — da cercare con `git log` proprio quando
si e' di fretta. Idem per tutti gli 11 Shelly.

Corretto con `conserva_precedenti()`: cio' che git conosce e la raccolta non
riproduce viene ripristinato dall'indice, con anomalia che avverte che quella
copia e' **vecchia** (per lo Zigbee, con avviso esplicito sul `frame_counter` non
aggiornato). **La cancellazione e' una decisione, non l'effetto collaterale di un
guasto di rete**: un dispositivo dismesso si toglie a mano.

### Ipotesi nuova sull'"instabilita' degli Shelly"

L'utente riferisce da tempo che gli Shelly sono instabili e che l'EM perde spesso
la connessione. **Oggi `CORR-SHELLY-EM` e' stato raccolto per la prima volta**: da
guasto e' passato a raggiungibile appena il DHCP e' tornato.

Ipotesi forte, non ancora dimostrata: **una parte di quella "instabilita'" e'
questo difetto.** Ogni riavvio del router azzera silenziosamente la rete IoT
finche' qualcuno non riavvia dnsmasq, e dall'esterno si vede come dispositivi che
"cadono". Prima di cercare cause nei dispositivi, va installata la contromisura e
riosservato il comportamento.

### CORREZIONE del 2026-08-14, poche ore dopo

Avevo scritto che i riavvii del router erano di **causa ignota** e che serviva il
log persistente per diagnosticarli. **Falso, e l'utente lo ha chiarito**: stava
facendo prove e ha **staccato il cavo di alimentazione un paio di volte** quella
mattina, al router Xiaomi e al dumb AP. `PGB-AP` era semplicemente **scollegato**,
ed e' tornato da se': ping 0,5 ms, SSH, uptime 0 minuti, OpenWrt 24.10.0.

Nessun guasto hardware, nessun riavvio spontaneo. Non cercare un difetto che non
c'e'.

### Ma il difetto vero non cambia — peggiora di priorita'

Se i riavvii erano deliberati, **il guasto della rete IoT non era un caso
sfortunato: era la conseguenza certa di un evento normale.** E gli eventi che
riavviano questo router non sono solo le prove dell'utente:

- **i blackout**, che qui sono documentati e ricorrenti (vedi la questione del
  BIOS `Restore on AC Power Loss`)
- ogni aggiornamento del firmware
- ogni intervento fisico

Quindi la contromisura passa da "mitigazione di un guasto ignoto" a **"copertura
di un evento che accadra' di nuovo con certezza"**. Su un sito normalmente non
presidiato, un blackout notturno lascerebbe la rete IoT morta per settimane,
senza che nulla lo dica — se non l'anomalia nel journal, che ora c'e'.

**Contromisure, in attesa di approvazione:**

1. **Hotplug su `ifup` della rete IoT** che riavvii `dnsmasq`. Chiude il difetto.
   **E' questa la priorita'**, non il log.
2. **Log persistente verso il PVE via syslog** (`log_ip`). Resta utile, ma non
   serve piu' a inseguire un guasto: serve a non essere ciechi la prossima volta.

Il bridge `br-iot` resta la soluzione strutturale (progetto VLAN): un bridge
esiste al boot indipendentemente dal WiFi, quindi il problema non si porrebbe.

### Conseguenza sulla mia obiezione all'esposizione

Avevo detto di non riaprire la porta verso internet **perche' il router si
riavviava da solo**. Quella premessa era sbagliata, e va ritirata: l'instabilita'
non esisteva. Restano in piedi solo le ragioni originarie — casa non presidiata,
2FA da attivare — non l'affidabilita' dell'apparato.

## 2026-08-14 — Rotazione dei segreti che ho esposto: rinviata, non annullata

**Decisione dell'utente**: tenere le rotazioni in **bassa priorita'**, si torna
piu' avanti. Registrata qui perche' un segreto esposto e *dimenticato* e' peggio
di uno esposto e tracciato: senza questa voce, la prossima sessione non saprebbe
che esistono e ripartirebbe da zero.

### Cosa e' stato esposto, e come

Tre episodi, tutti in trascrizioni di sessione sotto `/root/.claude` (modo `700`,
**non** replicate su GitHub: `collect-configs.sh` copia solo `memory/`).

| Quando | Cosa | Come |
|---|---|---|
| 12 ago | **2 chiavi private WireGuard** (`wg0`, `wg_site_sbt`) | `uci show network` stampato senza redazione |
| 12 ago | hostname DDNS di CASA e porta del tunnel | stessa lettura |
| 14 ago | IP pubblico di PGB | `journalctl` di postfix, letto per diagnosi |
| 14 ago | **chiave di rete Zigbee, link key dei 4 dispositivi, `tclk_seed`, credenziali MQTT** | `tail` del log di Zigbee2MQTT |

### Perche' rinviare e' difendibile

Il perimetro e' ristretto e misurato: nessuno dei segreti e' finito nel repo su
GitHub, e le trascrizioni stanno in una directory `700` su un host che non e'
esposto (gli inoltri verso il PVE sono stati rimossi, la zona IoT non raggiunge
la LAN). La superficie e' LAN piu' VPN.

Il costo della rotazione non e' invece trascurabile, ed e' il motivo per cui
merita una finestra dedicata invece di essere infilata in coda a un'altra sessione:

- `wg0`: rigenerare piu' aggiornare **3 client** road-warrior
- `wg_site_sbt`: richiede di cambiare la pubkey del peer **su OPNsense**, cioe'
  in una sessione su CASA, coordinata — sbagliando l'ordine si taglia il tunnel
  verso la casa vuota
- chiave di rete Zigbee: **riaccoppiare i 4 dispositivi** (poco, ma va fatto sul
  posto)
- credenziali MQTT: toccano Z2M e il termostato, da fare nella stessa finestra

### Quando smette di essere difendibile

Da rivedere **subito**, senza aspettare la coda, se si verifica una di queste:

1. Si apre un accesso dall'esterno verso il PVE o verso HA (la 443 e' stata
   aperta il 12 agosto: se si aggiungono altri inoltri, il perimetro cambia)
2. Una persona in piu' ottiene accesso a questo host
3. Le trascrizioni vengono copiate fuori dalla macchina, per qualunque motivo
4. Si sospetta un accesso non autorizzato al tunnel o alla rete Zigbee

### Il difetto di metodo, che invece e' stato corretto subito

Il punto non e' il campo dimenticato, e' il **metodo**: tre volte su tre ho
filtrato per lista di cio' che volevo nascondere, e tre volte era incompleta.
La regola sta in `infra-common/GESTIONE-SEGRETI.md`, che e' stato aggiornato con
le due lezioni nuove — il base64 che vanifica la redazione per nome di campo, e
i log di Zigbee2MQTT che contengono l'intero backup del coordinatore.

## 2026-08-16 — Bonifica smart TV: prima si chiude la via di fuga, poi si filtra

**Sessione presidiata. Richiesto dall'utente**: bloccare la telemetria delle TV
**a livello di rete**, senza toccare le impostazioni dei televisori.

### La scoperta che ha ribaltato l'ordine di lavoro

Misurando il traffico con le TV accese:

```
udp  src=192.168.15.164  dst=8.8.8.8  dport=53
```

**La TV LG interrogava il DNS di Google in parallelo a quello locale.** Un
controllo precedente non l'aveva vista perche' la TV era inattiva: il
comportamento si manifesta quando lavora.

Conseguenza: **finche' un dispositivo puo' scegliere il proprio resolver, ogni
regola di filtraggio e' facoltativa dal suo punto di vista.** Perfezionare le
liste prima di chiudere quella via sarebbe stato inutile.

### 1. Dirottamento DNS (la chiave di volta)

Due `redirect` DNAT su PGB-GW: tutta la porta 53 in uscita da `lan` e `IoTZone`
finisce sul resolver locale. Il dispositivo crede di parlare con Google e riceve
le risposte di AdGuard.

⚠️ **AdGuard e' escluso** (`src_ip='!192.168.15.3'`): usa DoH su 443, ma per
risolvere il nome del server DoH fa una query **bootstrap sulla 53**. Senza
esclusione: AdGuard -> dnsmasq -> AdGuard, anello.

Verificato in modo funzionale, non guardando le regole:

| Prova | Esito |
|---|---|
| `nslookup prov-lg.alphonso.tv 8.8.8.8` | **NXDOMAIN** — risponde AdGuard |
| 5 resolver esterni diversi | tutti la stessa risposta locale |
| contatore regola `lan` | 9 -> 19 pacchetti durante la prova |
| contatore regola `IoT` | **gia' a 5 prima della prova**: anche la seconda TV ci provava |

### 2. DoT e DoH dei resolver noti

`REJECT` (non `DROP`) sulla 853: il client fallisce subito e ripiega sulla 53,
che dirottiamo. Con `DROP` resterebbe appeso a ritentare.

Bloccata anche la 443 verso gli indirizzi dei resolver pubblici noti — nessuno
naviga legittimamente su `8.8.8.8:443`.

⚠️ **Trappola schivata per una cifra.** L'upstream di AdGuard e'
`dns10.quad9.net`, che risolve a **9.9.9.10** e **149.112.112.10**; nella lista
bloccata ci sono **9.9.9.9** e **149.112.112.112**. Se avesse usato
`dns.quad9.net` invece di `dns10`, il blocco avrebbe tolto il DNS a tutta la
casa. **Verificato dopo l'applicazione, e andava verificato prima.**

### 3. Regole in AdGuard

Prima c'erano **zero** regole personalizzate e una sola lista attiva.

Bloccati: `alphonso.tv` (ACR), `lgsmartad.com`, `lgtvcommon.com` (CDP, beacon,
nudge, recommend), `lgtviot.com`, `lgsmartplatform.com`, `nextlgsdp.com`,
`lgtvsdp.com`, `snu.lge.com`, `lgtvonline.lge.com`.

**Non bloccato di proposito**: `ngfts.lge.com` e `eic-ngfts.lge.com` sono
firmware e immagini. Bloccarli significa niente aggiornamenti di sicurezza, che
e' un peggioramento netto. Per questo non si blocca `lge.com` all'ingrosso.

`lgtviot.com` (cloud ThinQ) e' bloccabile perche' Home Assistant comanda la TV
**in locale via HomeKit** — verificato: `media_player.lg_webos_tv_883d` e
l'integrazione `homekit_controller` caricata. L'utente usa l'app LG solo come
telecomando di riserva e ne fa a meno.

### 4. HbbTV: il banner dei cookie del digitale terrestre

Il banner e' un'**applicazione web trasmessa insieme al canale**. Misurato sul
canale 35 (Focus, Mediaset): `hbbtv.mediaset.net` carica l'app, che contatta
`enabler.datalake.mediaset.it` e `data-enabler-cloud.mediaset.net` — i nomi
dicono da soli cosa fanno — piu' `securepubads.g.doubleclick.net`, gia' bloccato.

Bloccati i tre. **Non** e' bloccato `mediaset.it` all'ingrosso, per non rompere
l'app Infinity: verificato che `www.mediasetplay.mediaset.it` risolva ancora.

Per le altre emittenti servira' osservare il log: RAI e Discovery hanno i propri
endpoint, che compariranno quando quei canali verranno guardati.

### Verifica finale

Cinque domini nuovi provati uno per uno: tutti NXDOMAIN. Tre domini che devono
restare vivi: tutti risolti. AdGuard ripartito, DNS funzionante.

### Cosa questo NON copre

- **Indirizzi scritti in duro nel firmware**: il DNS non li vede. Servirebbe il
  blocco in uscita per destinazione, che e' il default-deny gia' in roadmap.
- **DoH verso host non noti**: gira sulla 443 verso nomi qualsiasi. Il
  dirottamento della 53 e il blocco dei resolver noti coprono i casi comuni.
- `datadoghq.com`: **10.903 query in quattro mesi**, `browser-intake` bloccato
  ma `http-intake` passa. Non bloccato: non si sa quale dispositivo sia e
  l'impatto e' ignoto. Da identificare.

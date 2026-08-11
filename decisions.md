# Log delle decisioni

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

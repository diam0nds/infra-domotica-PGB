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

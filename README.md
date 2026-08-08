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

### Ricerca del secondo router (AP WiFi) — 2026-08-08

Acceso dall'utente ma **non rintracciabile** su `192.168.15.0/24`.

Fatto finora: ping sweep completo del /24, probe TCP (22/80/443) sui candidati,
cattura passiva ARP/DHCP di 45s (nessun traffico), lettura della FDB del bridge.

Risultato: nella FDB compare `c6:c2:98:88:b7:77` su `enp1s0` — **un MAC attivo
sul segmento fisico senza alcun IP nella nostra subnet**. È il candidato più
probabile, ma il bit locally-administered è settato, quindi potrebbe anche
essere uno smartphone con MAC randomizzato.

**Ipotesi principale**: l'AP ha un IP fuori subnet, verosimilmente il default
OpenWrt `192.168.1.1`, quindi irraggiungibile da qui.

**Prossimo passo**: leggere i lease DHCP e la config wireless dal router master,
una volta ottenuto l'accesso SSH. In alternativa, IP alias temporaneo su
`192.168.1.0/24` per sondare `192.168.1.1` (additivo e reversibile).

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

⚠️ Da mettere in sicurezza. Progettazione da fare **dopo** aver letto le
configurazioni reali dei due router (chi distribuisce DHCP, quale DNS viene
annunciato ai client, se l'AP fa DHCP per conto suo).

Direzione proposta, da validare sulle config: i client ricevono come DNS
**il router master** (sempre acceso) invece di AdGuard direttamente; il router
inoltra ad AdGuard come upstream e ripiega su un resolver pubblico se AdGuard
non risponde. Si perde il filtraggio durante il guasto, ma la casa naviga.
Attenzione: dnsmasq interroga gli upstream in parallelo e tiene il più veloce,
quindi serve configurarlo esplicitamente per non aggirare il filtro in
condizioni normali.

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

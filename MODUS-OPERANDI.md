# Modus operandi e standard da replicare

> Questo documento serve a **replicare in modo speculare** sull'impianto della
> casa principale (OPNsense, Synology, domotica) quanto costruito qui.
> Contiene due parti: **come si lavora** e **cosa si costruisce**.
>
> Ogni principio riporta l'episodio concreto che l'ha insegnato: non sono buone
> intenzioni, sono errori già pagati.

---

# Parte 1 — Come si lavora

## 1. Verificare lo stato reale, non fidarsi della documentazione

Leggere sempre con i comandi. Anche questo repo può essere disallineato.

*Episodio*: la roadmap è rimasta indietro per giorni rispetto al lavoro fatto;
il `README` ha contenuto per ore una diagnosi sbagliata sulla porta 51821.

## 2. Misurare, non dedurre

Quando una misura contraddice un ragionamento teorico, **vince la misura**.

*Episodi*, tutti nello stesso lavoro:
- La teoria diceva che `strictorder` garantisse il fallback DNS. Misura: **0
  query risolte su 5**.
- La teoria diceva che il traffico ESTABLISHED non attraversa il DNAT, quindi la
  regola `WG-s2S` non poteva essere la causa. Misura: rimossa la regola, il
  tunnel è salito.
- L'ipotesi era che AdGuard filtrasse tutto. Misura: **7% delle query**.

Tre volte su tre la teoria ha perso. Gli strumenti che hanno dato le risposte:

```sh
kill -USR1 $(pidof dnsmasq); logread     # query per upstream, dati veri
grep <porta> /proc/net/nf_conntrack      # [UNREPLIED] distingue "non esco" da "non mi rispondono"
wg show                                  # handshake e byte per direzione
```

## 3. Cambiare una cosa per volta

Se si cambiano due variabili e qualcosa si muove, non si sa quale l'ha mossa.

*Episodio*: il cambio porta e la rimozione del DNAT, fatti separatamente, hanno
permesso di capire che la causa era la seconda. Fatti insieme, avrebbero
lasciato una diagnosi sbagliata in documentazione.

## 4. Provare il modo in cui una cosa si rompe, non solo che funziona

Un failover non testato **non è un failover**.

*Episodio*: il DNS "funzionava" con AdGuard come unico upstream. Spegnendo
AdGuard davvero: zero risoluzione. Il test è durato 6 minuti e ha evitato di
scoprirlo durante un blackout, da lontano.

## 5. Fail-safe, non fail-open

Ogni meccanismo va progettato perché un errore di configurazione produca un
guasto **visibile**, non una falsa sicurezza.

*Episodio*: `.gitattributes` di git-crypt è stato invertito — cifra tutto per
default con allowlist esplicita — perché la logica opposta pubblica in chiaro un
file nuovo **senza generare alcun errore**.

Stesso principio nel watchdog DNS: dopo un riavvio parte dal fallback pubblico,
perché è meglio partire senza filtro che partire senza DNS.

## 6. Mai stampare segreti, e redigere alla fonte

Filtrare per **nome del campo** è insufficiente: bisogna sapere cosa contiene un
file prima di mostrarlo.

*Episodio*: due chiavi private WireGuard sono finite in chiaro in una
conversazione perché il filtro copriva `key` e `password` ma non `private_key`.
Entrambe hanno dovuto essere rigenerate.

## 7. Chiavi separate per scopo

Una chiave per uso, così una compromissione non si propaga e la revoca è chirurgica.

| Chiave | Uso |
|---|---|
| `id_ed25519_github` | solo push sul repo di backup |
| `id_ed25519_infra` | solo nodi OpenWrt |
| `id_rsa` | preesistente cluster Proxmox, **mai riusata** |

## 8. Documentare il perché e le alternative scartate

Una decisione senza motivazione viene riaperta ogni volta. `decisions.md`
registra anche ciò che è stato **valutato e scartato**, così non si ridiscute.

*Episodio*: WoL, AMISCE e modifica NVRAM sono documentati come scartati, con il
motivo. Senza quella nota, ogni sessione ripartirebbe da lì.

## 9. Correggere subito la documentazione sbagliata

Una documentazione errata è peggio di nessuna documentazione.

*Episodio*: la diagnosi "la porta 51821 non funziona" era stata scritta in tre
file. Appena smentita è stata corretta in tutti e tre, conservando la traccia
dell'errore per non ripeterlo.

## 10. Su un sito non presidiato, preferire ciò che si autoripristina

Nessuno è sul posto per settimane: una soluzione che richiede presenza fisica non
è una soluzione.

*Corollario appreso a caro prezzo*: **un servizio critico non deve dipendere da
un nodo che si spegne.** Il DDNS gira su Home Assistant, che gira sul PVE, che
resta spento per giorni — quindi dopo un blackout la casa diventa
irraggiungibile proprio quando serve raggiungerla.

Regola: i servizi che servono a *recuperare* l'infrastruttura vanno sul nodo
**sempre acceso** (il router), non su quello che ospita i servizi.

## 11. Rispettare i vincoli hardware come vincoli reali

eMMC senza sostituzione possibile, 8,4 MB di flash sul router, 4 GB di RAM
liberi sul PVE. Niente stack write-heavy, niente liste enormi, liste in RAM
quando possibile.

## 12. Su un apparato remoto, armare il ripristino PRIMA di toccare

Una regola firewall sbagliata, o un `ifdown` sull'interfaccia da cui si è
collegati, taglia l'accesso a un apparato che sta in una casa vuota. Non esiste
rimedio da remoto.

**Protocollo obbligatorio per ogni modifica su router master e AP**, con
`scripts/router/safe-change.sh`:

```sh
safe-change.sh arm firewall 300     # backup + ripristino automatico fra 5 min
# ...applico UNA modifica...
# ...verifico di essere ancora dentro E che la modifica faccia quel che deve...
safe-change.sh confirm firewall     # solo ora disarmo
```

Se la verifica non arriva — perché la modifica ha tagliato l'accesso — la
configurazione torna da sola allo stato precedente e la sessione si recupera.
È l'interruttore dell'uomo morto.

Regole che lo accompagnano:

- **Mai** `/etc/init.d/network restart`: rimbalza `br-lan` e fa cadere la
  sessione. Solo `ifdown`/`ifup` sull'interfaccia specifica
- Verificare da un percorso che **non dipende** dalla modifica in corso
- Una modifica per volta, con conferma in mezzo: se se ne fanno due e qualcosa
  si rompe, non si sa quale
- Il pacchetto `network` è il più pericoloso: il ripristino rimette il file ma
  non riavvia nulla, perché un riavvio globale è peggio del problema
- Firmware e `sysupgrade`: **mai** senza un via libera esplicito e la procedura
  di recupero TFTP pronta

## 13. Proporre, aspettare l'ok, poi agire

È produzione domestica: DNS, WiFi e domotica sono servizi che una famiglia usa.
Le verifiche in sola lettura si fanno liberamente; le modifiche si concordano.

---

# Parte 2 — Standard tecnici da replicare

## Backup delle configurazioni

- Repo **git privato** con **git-crypt** in logica fail-safe (allowlist di ciò
  che resta in chiaro)
- **Verifica pre-push** che cloni il repo senza chiave e controlli che ogni file
  fuori allowlist inizi con `\0GITCRYPT\0`. Nessun push se falla
- Chiave git-crypt **fuori dalla macchina** (password manager), con la procedura
  di ripristino accanto e un checksum per verificarne l'integrità
- Raccolta **non solo di `/etc/config`**: servono anche cron, `rc.local`,
  `authorized_keys`, `sysupgrade.conf`, script custom ed elenco pacchetti,
  altrimenti dopo un riflash si ripristina la configurazione e si perde il resto
- Cron **giornaliero + `@reboot`**: su una macchina accesa in modo imprevedibile
  il solo orario fisso non scatta mai
- Retry sul push: un blip di rete non deve costare 24 ore di backup non replicato

## Architettura DNS

```
client  ->  router (unico DNS annunciato)  ->  AdGuard  ->  DoH esterno
                    |
                    +-- watchdog: se AdGuard tace, ripiega su resolver pubblico
```

- **Nessun `dhcp_option 6`**: i client ricevono il router, non AdGuard
  direttamente. Un solo punto da cambiare
- `noresolv='1'`: altrimenti dnsmasq usa **anche** i DNS imposti dalla WAN e il
  filtro viene aggirato
- `strictorder='1'` con AdGuard primo
- ⚠️ **L'ordine in uci va scritto invertito**: dnsmasq costruisce la lista
  interna al contrario. Verificare sempre sui contatori, non sul file
- AdGuard con `blocking_mode: nxdomain`: con `default` restituisce `0.0.0.0` e la
  protezione anti-rebind di dnsmasq **scarta la risposta**
- Watchdog che riscrive gli upstream in un file **in RAM** riletto con SIGHUP:
  nessun riavvio del servizio, nessuna scrittura sulla flash
- Il watchdog è prudente nel degradare (2 verifiche) e rapido nel ripristinare (1)

## Segmentazione di rete

Lo schema di questo sito è corretto e va replicato:

| Zona | Può raggiungere | Non può raggiungere |
|---|---|---|
| LAN | wan, IoT, tunnel | — |
| IoT | solo wan | **la LAN** |
| Guest | solo wan | LAN e IoT |

- Eccezioni per la domotica **puntuali** (host e porta specifici), non aperture
  di zona
- `input=REJECT` sulle zone non fidate: gli oggetti IoT non devono raggiungere
  SSH e interfaccia web del router
- Lease DHCP statici con nomi parlanti per tutta la domotica: diventa
  l'inventario

## Accesso e gestione

- SSH **solo a chiave**, password disabilitata — ma **dopo** aver verificato la
  chiave da ogni punto da cui serve
- Interfaccia web con reindirizzamento HTTPS obbligatorio, in ascolto solo
  sull'interfaccia di gestione
- Hostname espliciti per sito e ruolo (`pgb-gw`, `pgb-ap`), mai il default
- Log **persistenti**: il buffer da 64 KB in RAM si perde al riavvio, cioè
  esattamente quando servirebbe

## VPN

- Un tunnel site-to-site fra le case, iniziato dal lato con IP dinamico
- `persistent_keepalive` sul lato che inizia
- **DDNS sul router**, non su una VM
- Regole di **input** per le porte WireGuard, non port forward: WireGuard
  ascolta sull'host, non c'è nulla dietro da inoltrare
- Nella sezione `[Peer]` dei client va la chiave del **server**, non la propria
- Verificare **entrambe le direzioni**: rispondere e iniziare sono capacità
  diverse

---

# Parte 3 — Ordine per un sito nuovo

1. **Inventario e accessi** — leggere tutto, non modificare nulla
2. **Backup cifrato** — prima di ogni ottimizzazione, così ogni modifica è un
   diff reversibile
3. **Assessment** sicurezza e ottimizzazione, con gravità e priorità
4. **Segmentazione** e chiusura dell'amministrazione
5. **DNS** con fallback, e test del guasto
6. **VPN** e verifica delle due direzioni
7. **WiFi**, misurando prima di cambiare canali
8. **Filtri e domotica**
9. **Backup dei dati**, non solo delle configurazioni

## Da chiedere prima di iniziare sull'altra casa

L'infrastruttura principale **non è mai stata analizzata**. Prima di progettare:

- OPNsense è il router di frontiera, o c'è un apparato del provider davanti?
- Il Synology: cosa ospita, e sta davanti o dietro OPNsense?
- Chi aggiorna `diam0nds.synology.me`?
- Esiste già segmentazione fra LAN, IoT e ospiti?
- Dove gira la domotica: Home Assistant anche là, o un altro sistema?
- I backup dei dati esistono, e dove?
- L'IP è statico o dinamico?

Non fare assunzioni: qui l'assunzione "l'AP ha un IP fuori subnet" ha fatto
perdere tempo, quando la realtà era che l'AP non era in rete affatto.

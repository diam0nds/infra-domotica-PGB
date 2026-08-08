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

## In coda

### 1. Accesso SSH ai due router OpenWrt
Sblocca il backup delle loro configurazioni, l'individuazione dell'AP e
l'analisi del DNS. Prerequisito di quasi tutto il resto.
**Stato**: chiave pubblica consegnata all'utente, da incollare in LuCI.

### 2. Individuare il secondo router (AP WiFi)
Acceso ma non rintracciabile su `192.168.15.0/24`. Ipotesi: IP fuori subnet,
verosimilmente il default OpenWrt `192.168.1.1`. Si risolve leggendo i lease
DHCP dal master, una volta ottenuto l'accesso.

### 3. Mettere in sicurezza il DNS
AdGuard gira sul PVE ed è il DNS della rete: quando il PVE va giù, la casa non
naviga. Aggravato dal fatto che il PVE resta spento 8-14 giorni e che nessuno
è sul posto per intervenire. Progettazione da fare dopo aver letto le config
reali dei router. Vedi `README.md`.

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

#!/bin/bash
# Verifica che git-crypt stia davvero cifrando tutto quello che deve.
#
# Come funziona: fa un clone bare del repo (che copia gli oggetti cosi' come
# sono, cioe' cifrati) e poi lo riclona in un working tree SENZA la chiave.
# Quello che si vede li' dentro e' esattamente cio' che finirebbe su GitHub.
#
# Da eseguire PRIMA di ogni push e dopo OGNI modifica a .gitattributes:
# git-crypt cifra solo cio' che i pattern intercettano, e un pattern sbagliato
# non produce nessun errore — semplicemente pusha il file in chiaro.
#
# Esce con codice 1 se trova anche un solo file che doveva essere cifrato e
# non lo e'.

set -uo pipefail

REPO=${1:-/root/infra}

# L'header di git-crypt inizia con un byte null, quindi NON si puo' leggere
# con $(head -c ...): la command substitution di bash scarta i null e il
# confronto fallirebbe sempre, segnalando come "in chiaro" file perfettamente
# cifrati. Si confronta a livello binario con cmp.
MAGIC_FILE=$(mktemp)
printf '\0GITCRYPT\0' > "$MAGIC_FILE"

# File che devono restare leggibili — deve combaciare con .gitattributes
is_allowed_plaintext() {
  case "$1" in
    .gitattributes|.gitignore|README.md|decisions.md|ROADMAP.md|MODUS-OPERANDI.md|scripts/*) return 0 ;;
    *) return 1 ;;
  esac
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP" "$MAGIC_FILE"' EXIT

git clone -q --bare "$REPO" "$TMP/bare.git"  || { echo "clone bare fallito"; exit 1; }
git clone -q "$TMP/bare.git" "$TMP/work"     || { echo "clone fallito"; exit 1; }

cd "$TMP/work" || exit 1

fail=0; enc=0; plain=0
while IFS= read -r f; do
  [ -L "$f" ] && continue          # i symlink non hanno contenuto da cifrare
  [ -f "$f" ] || continue
  if cmp -s -n 10 "$f" "$MAGIC_FILE" 2>/dev/null; then
    enc=$((enc+1))
  elif is_allowed_plaintext "$f"; then
    plain=$((plain+1))
  else
    echo "  !!! IN CHIARO E NON DOVREBBE: $f"
    fail=$((fail+1))
  fi
done < <(git ls-files)

echo
echo "  cifrati:              $enc"
echo "  in chiaro (previsti): $plain"
echo "  IN CHIARO A SORPRESA: $fail"
echo

if [ "$fail" -gt 0 ]; then
  echo "  ESITO: FALLITO — non pushare finche' non e' risolto"
  exit 1
fi
echo "  ESITO: OK — tutto cio' che non e' in allowlist risulta cifrato"

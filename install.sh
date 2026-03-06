#!/usr/bin/env bash
# KeePass QuickShell — installer
# Edita config.json, poi esegui: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${BLUE}→${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   KeePass QuickShell — Installer         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Legge config.json ─────────────────────────────────────────────────────────
[[ -f "$CONFIG" ]] || err "config.json non trovato in $SCRIPT_DIR"

expand() { echo "${1/#\~/$HOME}"; }

QS_DIR=$(expand     "$(jq -r '.qs_dir      // "~/.config/quickshell/ii"'                    "$CONFIG")")
HYPR_DIR=$(expand   "$(jq -r '.hypr_dir    // "~/.config/hypr"'                             "$CONFIG")")
VAULT_PATH=$(expand "$(jq -r '.vault_path  // "~/Nextcloud/secrets/end4dot-keepass.kdbx"'   "$CONFIG")")
GEN_LANG=$(         jq -r  '.gen_lang    // "it"'                                            "$CONFIG")
CREATE_VAULT=$(     jq -r  '.create_vault // false'                                          "$CONFIG")

info "Configurazione:"
echo "  qs_dir:       $QS_DIR"
echo "  hypr_dir:     $HYPR_DIR"
echo "  vault_path:   $VAULT_PATH"
echo "  gen_lang:     $GEN_LANG"
echo "  create_vault: $CREATE_VAULT"
echo ""

# ── Dipendenze ────────────────────────────────────────────────────────────────
info "Controllo dipendenze..."
missing=()
chk()  { command -v "$1" >/dev/null 2>&1 && ok "$1" || { echo -e "  ${RED}✗${NC} $1  (pacchetto: $2)"; missing+=("$1"); }; }
chks() { command -v "$1" >/dev/null 2>&1 && ok "$1" || warn "$1 non trovato — opzionale ($2)"; }

chk  keepassxc-cli "keepassxc"
chk  wl-copy       "wl-clipboard"
chk  wl-paste      "wl-clipboard"
chk  jq            "jq"
chk  qs            "quickshell"
chks cliphist      "pulizia clipboard history"

(( ${#missing[@]} == 0 )) || err "Dipendenze mancanti: ${missing[*]}"
echo ""

# ── Verifica directory ────────────────────────────────────────────────────────
[[ -d "$QS_DIR" ]]   || err "qs_dir non trovata: $QS_DIR"
[[ -d "$HYPR_DIR" ]] || err "hypr_dir non trovata: $HYPR_DIR"

# ── Vault ─────────────────────────────────────────────────────────────────────
if [[ -f "$VAULT_PATH" ]]; then
  ok "Vault trovato: $VAULT_PATH"
elif [[ "$CREATE_VAULT" == "true" ]]; then
  info "Creazione vault: $VAULT_PATH"
  mkdir -p "$(dirname "$VAULT_PATH")"
  # Unico prompt necessario: la master password non può stare in config.json
  printf '\e[>0u'; trap 'printf "\e[<u"' EXIT
  read -r -s -p "  Master password: "  db_pass;  echo
  read -r -s -p "  Conferma:        "  db_pass2; echo
  [[ "$db_pass" == "$db_pass2" ]] || err "Le password non corrispondono"
  printf '%s\n%s\n' "$db_pass" "$db_pass" | keepassxc-cli db-create -q -p "$VAULT_PATH"
  ok "Vault creato"
else
  warn "Vault non trovato: $VAULT_PATH"
  warn "Imposta \"create_vault\": true in config.json per crearlo, oppure crealo manualmente."
fi
echo ""

# ── Copia file ────────────────────────────────────────────────────────────────
info "Copia file..."
bash "$SCRIPT_DIR/apply.sh" "$QS_DIR" "$HYPR_DIR"

# ── Patch vaultPath in KeePass.qml ───────────────────────────────────────────
QML="$QS_DIR/services/KeePass.qml"
if [[ -f "$QML" ]]; then
  info "Patch vault path in KeePass.qml..."
  sed -i "s|property string vaultPath:.*|property string vaultPath: FileUtils.trimFileProtocol(\"$VAULT_PATH\")|" "$QML"
  ok "vaultPath → $VAULT_PATH"
fi

# ── Scrive ~/.config/keepassqs/config ────────────────────────────────────────
KP_CFG="$HOME/.config/keepassqs"
mkdir -p "$KP_CFG"
info "Scrittura $KP_CFG/config..."
cat > "$KP_CFG/config" <<EOF
KP_VAULT_PATH="\${KP_VAULT_PATH:-$VAULT_PATH}"
KP_GEN_LANG="\${KP_GEN_LANG:-$GEN_LANG}"
KP_WORDLIST_DIR="\${KP_WORDLIST_DIR:-$KP_CFG/wordlists}"
EOF
ok "Config scritto"
echo ""

# ── Svuota cache password (vault path potrebbe essere cambiato) ───────────────
SCRIPT_DEST="$HYPR_DIR/custom/scripts/quickshell-keepass"
if [[ -f "$SCRIPT_DEST" ]]; then
  "$SCRIPT_DEST" lock 2>/dev/null && info "Cache password svuotata" || true
fi

echo -e "${GREEN}${BOLD}Installazione completata!${NC}"
echo "Segui le patch manuali stampate sopra, poi: qs reload"
echo ""

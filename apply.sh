#!/bin/bash
# Applica KeePass + QuickShell integration
# Uso: ./apply.sh [qs-config-dir] [hypr-config-dir]
# Default: ~/.config/quickshell/ii  e  ~/.config/hypr

QS="${1:-$HOME/.config/quickshell/ii}"
HYPR="${2:-$HOME/.config/hypr}"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script
cp "$SCRIPT_DIR/hypr/custom/scripts/quickshell-keepass" "$HYPR/custom/scripts/quickshell-keepass"
chmod +x "$HYPR/custom/scripts/quickshell-keepass"

# QML service
cp "$SCRIPT_DIR/quickshell/ii/services/KeePass.qml" "$QS/services/KeePass.qml"

# UI module
mkdir -p "$QS/modules/ii/keepass"
cp "$SCRIPT_DIR/quickshell/ii/modules/ii/keepass/KeepassPanel.qml" "$QS/modules/ii/keepass/KeepassPanel.qml"

# Wordlists
KP_CFG_DIR="${KP_CFG_DIR:-$HOME/.config/keepassqs}"
mkdir -p "$KP_CFG_DIR/wordlists"
cp "$SCRIPT_DIR/wordlists/"*.json "$KP_CFG_DIR/wordlists/"

echo ""
echo "=== Patch manuale richiesta ==="
echo ""
echo "1) $QS/modules/common/Config.qml"
echo "   Aggiungi dentro 'property JsonObject prefix':"
echo "     property string keepass: \"p \""
echo ""
echo "2) $QS/services/LauncherSearch.qml"
echo "   a) Riga property string query: aggiungere sotto:"
echo "      property bool keepassTriggered: false"
echo "   b) In 'property list<var> results', prima del blocco clipboard:"
echo "      if (root.query.startsWith(Config.options.search.prefix.keepass)) {"
echo "          if (!root.keepassTriggered) {"
echo "              root.keepassTriggered = true"
echo "              KeePass.openList()"
echo "              GlobalStates.overviewOpen = false"
echo "              root.query = \"\""
echo "          }"
echo "          return []"
echo "      } else {"
echo "          root.keepassTriggered = false"
echo "      }"
echo "   c) In ensurePrefix(), aggiungere keepass alla lista:"
echo "      Config.options.search.prefix.keepass,"
echo ""
echo "3) $QS/panelFamilies/IllogicalImpulseFamily.qml"
echo "   Aggiungi import: import qs.modules.ii.keepass"
echo "   Aggiungi loader: PanelLoader { component: KeepassPanel {} }"
echo ""
echo "4) $HYPR/custom/keybinds.conf"
echo "   bindd = Super, P, KeePass vault, exec, qs -c \$qsConfig ipc call keepass toggle"
echo "   bindd = Super+Shift, P, KeePass add entry, exec, qs -c \$qsConfig ipc call keepass add"
echo ""
echo "Poi: qs reload"

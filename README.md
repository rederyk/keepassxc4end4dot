# keepassxc4end4dot — KeePassXC integration for dots-hyprland (ii)

A KeePass integration for [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (Illogical Impulse config).
Adds a floating panel to browse, copy and add KeePass entries directly from your desktop, without opening KeePassXC.

> Made with the help of [Claude](https://claude.ai) (Anthropic).

---

## Features

- **Browse & copy** — search entries, copy password or username to clipboard (auto-removed from cliphist)
- **Unlock with cache** — the vault password is cached for a configurable TTL (5 min / 30 min / 4 h); no re-entry needed while the cache is valid
- **Add entry** — save a new entry directly from the panel
- **Password generator** — generate a random password with configurable length (8 / 12 / 20) and charset (a-z, A-Z, 0-9, symbols)
- **Wordlist-based passwords** — generate memorable passphrases from multilingual wordlists (it / en / de)
- **Show/hide password** — toggle visibility in the add form
- **Inject selected text as password** — select a password anywhere on screen, press `Super+Shift+P` and it is pre-filled in the add form (via Wayland primary selection)

---

## Requirements

| Package | Purpose |
|---------|---------|
| `keepassxc` | provides `keepassxc-cli` |
| `wl-clipboard` | provides `wl-copy` / `wl-paste` (Wayland clipboard + primary selection) |
| `jq` | reads `config.json` during install |
| `cliphist` | optional — keeps clipboard history clean of copied secrets |

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/rederyk/keepassxc4end4dot
cd keepassxc4end4dot
```

### 2. Edit `config.json`

All install options are set in `config.json` — no interactive prompts:

```json
{
  "qs_dir":      "~/.config/quickshell/ii",
  "hypr_dir":    "~/.config/hypr",
  "vault_path":  "~/Nextcloud/secrets/end4dot-keepass.kdbx",
  "gen_lang":    "it",
  "create_vault": false
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `qs_dir` | `~/.config/quickshell/ii` | Path to the QuickShell ii config directory |
| `hypr_dir` | `~/.config/hypr` | Path to the Hyprland config directory |
| `vault_path` | `~/Nextcloud/secrets/end4dot-keepass.kdbx` | Path to your KeePassXC vault |
| `gen_lang` | `it` | Wordlist language for passphrase generation (`it`, `en`, `de`) |
| `create_vault` | `false` | Set to `true` to create a new vault at `vault_path` during install |

> If `create_vault` is `true`, the installer will prompt once for the master password (it cannot be stored in `config.json` for security reasons).

### 3. Run the installer

```bash
./install.sh
```

The installer will:
- Check all required dependencies
- Create the vault if `create_vault: true` (prompts for master password)
- Copy QuickShell and Hyprland files to the configured paths
- Patch `vaultPath` in `KeePass.qml`
- Write `~/.config/keepassqs/config` with runtime variables
- Clear the cached password if a previous install exists

---

## Manual patches (required)

After running the installer, apply these patches to the end-4 config files.

### 1. `~/.config/quickshell/ii/modules/common/Config.qml`

Inside `property JsonObject prefix`, add:
```qml
property string keepass: "p "
```

### 2. `~/.config/quickshell/ii/services/LauncherSearch.qml`

**a)** After `property string query`, add:
```qml
property bool keepassTriggered: false
```

**b)** In `property list<var> results`, before the clipboard block:
```qml
if (root.query.startsWith(Config.options.search.prefix.keepass)) {
    if (!root.keepassTriggered) {
        root.keepassTriggered = true
        KeePass.openList()
        GlobalStates.overviewOpen = false
        root.query = ""
    }
    return []
} else {
    root.keepassTriggered = false
}
```

**c)** In `ensurePrefix()`, add `keepass` to the prefix list:
```qml
Config.options.search.prefix.keepass,
```

### 3. `~/.config/quickshell/ii/panelFamilies/IllogicalImpulseFamily.qml`

Add import:
```qml
import qs.modules.ii.keepass
```

Add loader inside the main Scope:
```qml
PanelLoader { component: KeepassPanel {} }
```

### 4. `~/.config/hypr/custom/keybinds.conf`

```
bindd = Super, P, KeePass vault, exec, qs -c $qsConfig ipc call keepass toggle
bindd = Super+Shift, P, KeePass add entry (inject selection), exec, qs -c $qsConfig ipc call keepass add
```

Then reload QuickShell:
```bash
qs reload
```

---

## Usage

| Action | How |
|--------|-----|
| Open vault browser | `Super+P` |
| Open add entry form | `Super+Shift+P` |
| Add with selected password | Select text anywhere → `Super+Shift+P` |
| Search entries | Type in the search field |
| Copy password | Select entry → Enter (or click **Copy Password**) |
| Copy username | Select entry → **Copy Username** |
| Reveal password | Select entry → **Show** |
| Lock vault | Click the lock icon in the panel header |
| Type `p ` in launcher | Opens vault browser from the overview |

### Password generator (add form)

- Click **Generate** to fill the password field with a random password
- Adjust **length**: `8` · `12` · `20`
- Toggle **charset**: `A-Z` (uppercase) · `0-9` (digits) · `!@#` (symbols)
- Lowercase letters are always included
- Switch to **wordlist mode** to generate a passphrase from the language set in `gen_lang`

---

## Vault path

The default vault path is set in `config.json` and written to `~/.config/keepassqs/config`.
You can override it at runtime with the `KP_VAULT_PATH` environment variable, or edit `vaultPath` in `KeePass.qml`.

---

## Wordlists

Passphrases are generated from JSON wordlists in the `wordlists/` directory.
Three languages are included: `it.json`, `en.json`, `de.json`.
Set `gen_lang` in `config.json` to pick the default language.

---

## License

MIT

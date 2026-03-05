# Tentativi di navigazione da tastiera per KeepassPanel.qml

## Obiettivo

Aggiungere navigazione da tastiera al pannello KeePass:
- Focus su `filterField` (ToolbarTextField) all'apertura
- Frecce Su/Giu per navigare la lista (`entryList`)
- Tab per ciclare tra filterField → entryList → showButton → copyButton → copyUsernameButton → filterField
- Lettere digitate nella lista → redirect a filterField (search-as-you-type)
- Su dalla prima voce → torna a filterField

## Struttura dei componenti

- `ToolbarTextField` = direttamente `TextField` (QtQuick.Controls 2), **non** un wrapper/FocusScope
- `DialogListItem` = `RippleButton` → `Button` (QtQuick.Controls 2), ha `activeFocusOnTab: true` di default
- `DialogButton` = `RippleButton` → `Button`
- `entryList` = `ListView` (QtQuick), `keyNavigationEnabled: true` di default (gestisce Up/Down internamente)
- Il pannello usa `WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand` + `HyprlandFocusGrab`

## Warning presente nel log (pre-esistente, non correlato)

```
WARN: Could not attach Keys property to: qs::wayland::layershell::WaylandPanelInterface_QML_XXXX is not an Item
```
Questo warning riguarda il `Keys.onPressed` sul `PanelWindow` (che non è un QQuickItem). Non impatta i child item.

```
WARN scene: @modules/ii/keepass/KeepassPanel.qml[...]: Unable to assign [undefined] to QColor
```
Pre-esistente, riguarda colori non trovati nel tema attivo.

---

## Tentativo 1 — `forceActiveFocus()` + `Keys.onPressed` semplice

**Modifiche**:
- `focusDefault()`: `entryList.forceActiveFocus()` → `filterField.forceActiveFocus()`
- `filterField`: aggiunto `Keys.onPressed` con Down/Enter → `entryList.forceActiveFocus()`
- `entryList`: rimosso `KeyNavigation.tab/backtab` statici, aggiunto handling manuale Tab/Backtab/Up/Down/printable nel `Keys.onPressed`
- `copyUsernameButton`: `KeyNavigation.tab` → `filterField` invece di `entryList`
- Delegate: `focus: false`, `activeFocusOnTab: false`, `onClicked` → `entryList.forceActiveFocus()`

**Problema riscontrato**:
- Focus rimane su `entryList` (non va su `filterField`)
- Frecce non funzionano
- Causa sospetta: `focus: true` su `entryList` sovrascriveva il `forceActiveFocus()` su filterField quando il layout diventava visibile

---

## Tentativo 2 — Timer 50ms + `keyNavigationEnabled: false` + `Keys.priority: Keys.BeforeItem`

**Modifiche aggiuntive**:
- Sostituito `filterField.forceActiveFocus()` con `focusTimer.restart()` (Timer 50ms) per evitare race condition
- `entryList`: rimosso `focus: true`, aggiunto `keyNavigationEnabled: false`, `Keys.priority: Keys.BeforeItem`
- Delegate: confermato `focus: false`, `activeFocusOnTab: false`

**Razionale**:
- `keyNavigationEnabled: true` (default ListView) consuma Up/Down internamente prima che `Keys.onPressed` li veda
- `Keys.priority: Keys.BeforeItem` fa scattare il nostro handler prima dell'handling interno del ListView
- Timer 50ms per dare tempo al layout di renderizzarsi prima di assegnare il focus

**Problema riscontrato**:
- Niente cambiato dal punto di vista utente
- Focus ancora non su filterField
- Frecce ancora non funzionano
- Tab esce dalla finestra invece di ciclare

---

## Tentativo 3 — `Qt.callLater` + `KeyNavigation.tab` su filterField

**Modifiche aggiuntive**:
- Rimosso il Timer, sostituito con `Qt.callLater(filterField.forceActiveFocus)` in `focusDefault()`
- `filterField`: aggiunto `KeyNavigation.tab: entryList` e `KeyNavigation.backtab: entryList` (override nativo QML del Tab di TextField)
- `filterField`: aggiunto `Keys.priority: Keys.BeforeItem`

**Razionale**:
- `Qt.callLater` differisce al frame successivo (più affidabile del Timer fisso)
- `KeyNavigation.tab` è il modo nativo QML per override del Tab su un TextField
- Il SearchBar dello stesso codebase (SearchBar.qml) usa `Keys.onPressed` su ToolbarTextField per intercettare Tab — confermato che funziona

**Problema riscontrato**:
- Ancora niente. Comportamento identico ai tentativi precedenti.
- Il `forceActiveFocus()` su `filterField` (TextField) sembra non avere effetto

---

## Ipotesi non verificate

1. **`HyprlandFocusGrab` interferisce con il focus QML**: Il grab di Hyprland potrebbe resettare il focus al primo item focusabile quando si attiva, bypassando `forceActiveFocus()`. Da investigare nella documentazione di Quickshell.

2. **`WlrKeyboardFocus.OnDemand` e routing degli eventi**: Possibile che gli eventi tastiera non raggiungano tutti i QML item come previsto in un overlay layer Wayland.

3. **`filterField` (TextField) non accetta `forceActiveFocus()`** in questo contesto Quickshell/Wayland: potrebbe richiedere un meccanismo diverso.

4. **Il `ColumnLayout` con `visible: false` → `true`** potrebbe resettare il focus dopo il nostro `Qt.callLater`.

5. **`column` con `focus: true`** potrebbe riclamare il focus dopo il nostro `forceActiveFocus()` su filterField.

## Cose da cercare

- Quickshell docs / issues su keyboard focus con `WlrLayershell` e `HyprlandFocusGrab`
- Come altri pannelli Quickshell (es. sidebarRight) gestiscono il focus da tastiera
- Se `forceActiveFocus()` funziona su `TextField` dentro un `PanelWindow` Quickshell
- Quickshell GitHub issues: "keyboard focus", "forceActiveFocus", "TextField focus"
- Differenza tra `activeFocusOnTab` e `focusPolicy` in QQC2 in ambiente Wayland layer-shell

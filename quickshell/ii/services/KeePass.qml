pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string scriptPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/scripts/quickshell-keepass`)
    property string vaultPath: FileUtils.trimFileProtocol(`${Directories.home}/Nextcloud/secrets/end4dot-keepass.kdbx`)

    property bool open: false
    property bool addMode: false
    property bool unlocked: false
    property bool busy: false
    property string lastError: ""
    property string pendingPassword: ""

    property string password: ""
    property list<string> entries: []
    property string filter: ""

    property string selectedEntry: ""
    property bool reveal: false
    property string revealedPassword: ""
    property string generatedPassword: ""

    // TTL selezionabile: 300 (5 min), 1800 (30 min), 14400 (4 ore)
    property int cacheTtl: 300

    function resetSensitive() {
        password = ""
        unlocked = false
        entries = []
        selectedEntry = ""
        reveal = false
        revealedPassword = ""
        lastError = ""
    }

    function openList() {
        open = true
        addMode = false
        resetSensitive()
        // Prova subito senza password: il script userà la cache se ancora valida
        refreshEntries()
    }

    function openAdd() {
        open = true
        addMode = true
        resetSensitive()
        refreshEntries()
    }

    function close() {
        open = false
        addMode = false
        pendingPassword = ""
        resetSensitive()
    }

    function openAddWithSelection() {
        if (open && addMode) {
            close()
            return
        }
        selectionProc.exec(["wl-paste", "--primary"])
    }

    function lock() {
        lockProc.exec({
            environment: { KP_VAULT_PATH: root.vaultPath },
            command: [scriptPath, "lock"]
        })
        resetSensitive()
    }

    function envFor() {
        return {
            KP_VAULT_PATH: root.vaultPath,
            KP_NONINTERACTIVE: "1",
            KP_CACHE_TTL: root.cacheTtl.toString()
        }
    }

    function unlock(passwordValue) {
        if (!passwordValue || passwordValue.trim().length === 0) {
            lastError = Translation.tr("Missing password")
            return
        }
        password = passwordValue
        refreshEntries()
    }

    function refreshEntries() {
        busy = true
        listProc.buffer = []
        listProc.exec({
            environment: envFor(),
            command: [scriptPath, "ls", "-R", "-f"]
        })
    }

    function filteredEntries(query) {
        const q = (query ?? "").trim().toLowerCase()
        if (q.length === 0) return entries
        return entries.filter(e => e.toLowerCase().includes(q))
    }

    function openEntry(entry) {
        selectedEntry = entry
        reveal = false
        revealedPassword = ""
    }

    function showPassword() {
        if (!selectedEntry) return
        getProc.exec({
            environment: envFor(),
            command: [scriptPath, "get", selectedEntry, "password"]
        })
    }

    function copyPassword() {
        if (!selectedEntry) return
        copyGetProc.exec({
            environment: envFor(),
            command: [scriptPath, "get", selectedEntry, "password"]
        })
    }

    function copyUsername() {
        if (!selectedEntry) return
        copyUsernameProc.exec({
            environment: envFor(),
            command: [scriptPath, "get", selectedEntry, "username"]
        })
    }

    function generate(length, useUpper, useNumbers, useSymbols, useWords) {
        genProc.exec({
            environment: {
                KP_GEN_LENGTH:  length.toString(),
                KP_GEN_UPPER:   useUpper   ? "1" : "0",
                KP_GEN_NUMBERS: useNumbers ? "1" : "0",
                KP_GEN_SYMBOLS: useSymbols ? "1" : "0",
                KP_GEN_WORDS:   useWords   ? "1" : "0"
            },
            command: [scriptPath, "generate"]
        })
    }

    function addEntry(entry, entryPassword, username = "", url = "") {
        if (!entry || entry.trim().length === 0 || !entryPassword) {
            lastError = Translation.tr("Missing entry name or password")
            return
        }
        addProc.entryPassword = entryPassword
        addProc.exec({
            environment: envFor(),
            command: [scriptPath, "add", entry, username, url]
        })
    }

    Process {
        id: lockProc
    }

    Timer {
        id: autoCloseTimer
        interval: 400
        repeat: false
        onTriggered: root.close()
    }

    Process {
        id: listProc
        property list<string> buffer: []
        onRunningChanged: {
            if (listProc.running && root.password.length > 0) {
                listProc.stdinEnabled = true
                listProc.write(`${root.password}\n`)
                listProc.stdinEnabled = false
            }
        }
        stdout: SplitParser {
            onRead: (line) => {
                if (line && line.trim().length > 0)
                    listProc.buffer.push(line)
            }
        }
        onExited: (exitCode, exitStatus) => {
            busy = false
            if (exitCode === 0) {
                entries = listProc.buffer
                unlocked = true
                lastError = ""
            } else {
                entries = []
                unlocked = false
                // Mostra errore solo se l'utente aveva inserito la password
                // (non durante l'auto-check all'apertura con cache vuota)
                if (password.length > 0)
                    lastError = Translation.tr("Unlock failed")
            }
        }
    }

    Process {
        id: getProc
        onRunningChanged: {
            if (getProc.running && root.password.length > 0) {
                getProc.stdinEnabled = true
                getProc.write(`${root.password}\n`)
                getProc.stdinEnabled = false
            }
        }
        stdout: StdioCollector {
            id: passwordCollector
            onStreamFinished: {
                const pwd = passwordCollector.text.replace(/\n+$/, "")
                revealedPassword = pwd
                reveal = true
                lastError = ""
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                lastError = Translation.tr("Failed to read password")
            }
        }
    }

    Timer {
        id: cliphistCleanupTimer
        interval: 150
        repeat: false
        onTriggered: {
            cliphistCleanupProc.exec(["bash", "-c", "cliphist list | head -n 1 | cliphist delete"])
        }
    }

    Process {
        id: cliphistCleanupProc
    }

    Process {
        id: copyGetProc
        onRunningChanged: {
            if (copyGetProc.running && root.password.length > 0) {
                copyGetProc.stdinEnabled = true
                copyGetProc.write(`${root.password}\n`)
                copyGetProc.stdinEnabled = false
            }
        }
        stdout: StdioCollector {
            id: copyCollector
            onStreamFinished: {
                const value = copyCollector.text.replace(/\n+$/, "")
                if (!value || value.length === 0) {
                    lastError = Translation.tr("Failed to copy password")
                    return
                }
                Quickshell.clipboardText = value
                lastError = ""
                cliphistCleanupTimer.restart()
                autoCloseTimer.restart()
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                lastError = Translation.tr("Failed to copy password")
            }
        }
    }

    Process {
        id: copyUsernameProc
        onRunningChanged: {
            if (copyUsernameProc.running && root.password.length > 0) {
                copyUsernameProc.stdinEnabled = true
                copyUsernameProc.write(`${root.password}\n`)
                copyUsernameProc.stdinEnabled = false
            }
        }
        stdout: StdioCollector {
            id: copyUsernameCollector
            onStreamFinished: {
                const value = copyUsernameCollector.text.replace(/\n+$/, "")
                if (!value || value.length === 0) {
                    lastError = Translation.tr("Failed to copy username")
                    return
                }
                Quickshell.clipboardText = value
                lastError = ""
                autoCloseTimer.restart()
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                lastError = Translation.tr("Failed to copy username")
            }
        }
    }

    Process {
        id: addProc
        property string entryPassword: ""
        onRunningChanged: {
            if (addProc.running) {
                addProc.stdinEnabled = true
                // db password on line 1 (only if not cached), entry password on next line
                const payload = root.password.length > 0
                    ? `${root.password}\n${addProc.entryPassword}\n`
                    : `${addProc.entryPassword}\n`
                addProc.write(payload)
                addProc.stdinEnabled = false
            }
        }
        onExited: (exitCode, exitStatus) => {
            addProc.entryPassword = ""
            if (exitCode === 0) {
                lastError = ""
                refreshEntries()
            } else {
                lastError = Translation.tr("Failed to add entry")
            }
        }
    }

    Process {
        id: genProc
        stdout: StdioCollector {
            id: genCollector
            onStreamFinished: {
                root.generatedPassword = genCollector.text.replace(/\n+$/, "")
            }
        }
    }

    Process {
        id: selectionProc
        stdout: StdioCollector {
            id: selectionCollector
            onStreamFinished: {
                const sel = selectionCollector.text.replace(/\n+$/, "").trim()
                root.pendingPassword = sel
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.pendingPassword = ""
            root.open = true
            root.addMode = true
            root.resetSensitive()
            root.refreshEntries()
        }
    }
}

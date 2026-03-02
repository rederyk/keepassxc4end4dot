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

    property string password: ""
    property list<string> entries: []
    property string filter: ""

    property string selectedEntry: ""
    property bool reveal: false
    property string revealedPassword: ""

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
    }

    function close() {
        open = false
        addMode = false
        resetSensitive()
    }

    function lock() {
        lockProc.exec({
            environment: { KP_VAULT_PATH: root.vaultPath },
            command: [scriptPath, "lock"]
        })
        resetSensitive()
    }

    function envFor(passwordValue) {
        const env = {
            KP_VAULT_PATH: root.vaultPath,
            KP_NONINTERACTIVE: "1",
            KP_CACHE_TTL: root.cacheTtl.toString()
        }
        // Only set KP_PASSWORD if non-empty — when empty the script reads from cache
        if (passwordValue && passwordValue.length > 0)
            env.KP_PASSWORD = passwordValue
        return env
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
            environment: envFor(password),
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
            environment: envFor(password),
            command: [scriptPath, "get", selectedEntry, "password"]
        })
    }

    function copyPassword() {
        if (!selectedEntry) return
        copyGetProc.exec({
            environment: envFor(password),
            command: [scriptPath, "get", selectedEntry, "password"]
        })
    }

    function copyUsername() {
        if (!selectedEntry) return
        copyUsernameProc.exec({
            environment: envFor(password),
            command: [scriptPath, "get", selectedEntry, "username"]
        })
    }

    function addEntry(entry, entryPassword, username = "", url = "") {
        if (!entry || entry.trim().length === 0 || !entryPassword) {
            lastError = Translation.tr("Missing entry name or password")
            return
        }
        addProc.entryPassword = entryPassword
        addProc.exec({
            environment: envFor(password),
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
                addProc.write(`${addProc.entryPassword}\n`)
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
}

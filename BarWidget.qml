import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.brukb.docker-remote"

  readonly property string statusScript:
    Qt.resolvedUrl("bin/docker-remote-status").toString().replace(/^file:\/\//, "")
  readonly property string actionScript:
    Qt.resolvedUrl("bin/docker-remote-action").toString().replace(/^file:\/\//, "")
  readonly property string configScript:
    Qt.resolvedUrl("bin/docker-remote-config").toString().replace(/^file:\/\//, "")

  readonly property string instanceId: setting("instanceId", "default")
  readonly property int interval: Math.max(5, setting("interval", 15))
  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool notifyUnhealthy: setting("notifyUnhealthy", true) !== false
  readonly property string terminalCmd: setting("terminal", "xdg-terminal-exec")

  property var hosts: []
  property string activeHostId: ""
  property var hostStates: ({})
  property string fetchTargetId: ""
  property bool fetching: false
  property int backgroundHostIndex: 0

  function hostRecord(id) {
    for (var i = 0; i < hosts.length; i++)
      if (hosts[i].id === id) return hosts[i]
    return null
  }

  function activeRecord() {
    return hostRecord(activeHostId)
  }

  function stateFor(id) {
    return hostStates[id] || {
      info: {},
      errorText: "",
      everLoaded: false,
      busyId: ""
    }
  }

  function patchHostState(id, patch) {
    var cur = stateFor(id)
    var next = {}
    var k
    for (k in hostStates) next[k] = hostStates[k]
    var merged = {
      info: patch.info !== undefined ? patch.info : cur.info,
      errorText: patch.errorText !== undefined ? patch.errorText : cur.errorText,
      everLoaded: patch.everLoaded !== undefined ? patch.everLoaded : cur.everLoaded,
      busyId: patch.busyId !== undefined ? patch.busyId : cur.busyId
    }
    next[id] = merged
    hostStates = next
  }

  readonly property var active: activeRecord()
  readonly property var activeState: stateFor(activeHostId)

  readonly property string host: active ? String(active.host || "") : ""
  readonly property string sshUser: active ? String(active.sshUser || "") : ""
  readonly property string clusterLabel: active ? hostField(active, "label").trim() : ""
  readonly property string sshIdentityFile: active ? String(active.sshIdentityFile || "") : ""
  readonly property string portBaseUrl: {
    if (!active) return ""
    var configured = String(active.portBaseUrl || "").trim()
    if (configured !== "") return configured
    if (host !== "") return "http://" + host
    return ""
  }

  readonly property bool configured: hosts.length > 0 && host !== "" && sshUser !== ""
  readonly property string displayLabel:
    clusterLabel !== "" ? clusterLabel : (host !== "" ? host : "Docker")

  readonly property var info: activeState.info || ({})
  readonly property string errorText: activeState.errorText || ""
  readonly property bool everLoaded: activeState.everLoaded === true
  readonly property string busyId: activeState.busyId || ""

  readonly property bool reachable:
    configured && info.reachable === true && errorText === ""

  readonly property int totalCount: (info.containers || []).length
  readonly property int runningCount: {
    var n = 0
    var all = info.containers || []
    for (var i = 0; i < all.length; i++)
      if (all[i].state === "running") n++
    return n
  }
  readonly property int unhealthyCount: {
    var n = 0
    var all = info.containers || []
    for (var i = 0; i < all.length; i++)
      if (all[i].health === "unhealthy") n++
    return n
  }
  readonly property bool alerting: {
    if (!everLoaded || hosts.length === 0) return false
    var i, st, inf
    for (i = 0; i < hosts.length; i++) {
      st = stateFor(hosts[i].id)
      if (!st.everLoaded) continue
      inf = st.info || {}
      if (st.errorText || inf.reachable === false) return true
      var cs = inf.containers || []
      for (var j = 0; j < cs.length; j++)
        if (cs[j].health === "unhealthy") return true
    }
    return false
  }

  readonly property var hostStatus:
    info.hostStats && typeof info.hostStats === "object" ? info.hostStats : null

  readonly property var grouped: {
    var conts = info.containers || []
    var portOwner = {}
    var i, j, c
    for (i = 0; i < conts.length; i++) {
      c = conts[i]
      if (c.state !== "running") continue
      for (j = 0; j < (c.ports || []).length; j++)
        portOwner[c.ports[j].host] = c.name
    }

    var byProject = {}
    var alone = []
    for (i = 0; i < conts.length; i++) {
      c = conts[i]
      var entry = {
        id: c.id,
        name: c.project ? (c.service || c.name) : c.name,
        image: (c.image || "").replace(/:latest$/, ""),
        state: c.state,
        health: c.health || "",
        workingDir: c.workingDir || "",
        configFiles: c.configFiles || "",
        portsList: portEntries(c.ports || []),
        note: ""
      }
      if (c.state !== "running") {
        for (j = 0; j < (c.ports || []).length; j++) {
          var owner = portOwner[c.ports[j].host]
          if (owner && owner !== c.name) {
            entry.note = "port " + c.ports[j].host + " in use by " + owner
            break
          }
        }
      }
      if (c.project) {
        if (!byProject[c.project]) byProject[c.project] = []
        byProject[c.project].push(entry)
      } else {
        alone.push(entry)
      }
    }

    var byName = function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 }
    var stackList = Object.keys(byProject).sort().map(function(name) {
      return { name: name, containers: byProject[name].sort(byName) }
    })
    return { stacks: stackList, standalone: alone.sort(byName) }
  }

  readonly property var stacks: grouped.stacks
  readonly property var standalone: grouped.standalone

  function portEntries(ports) {
    var out = []
    for (var i = 0; i < ports.length; i++) {
      var hp = ports[i].host
      var cont = ports[i].container || ""
      var udp = cont.indexOf("/udp") >= 0
      cont = cont.split("/")[0]
      out.push({
        label: (hp === cont ? hp : hp + "→" + cont) + (udp ? "/udp" : ""),
        host: hp,
        web: !udp
      })
    }
    return out
  }

  function stackRunning(stack) {
    var n = 0
    for (var i = 0; i < stack.containers.length; i++)
      if (stack.containers[i].state === "running") n++
    return n
  }

  function hostField(rec, key) {
    if (!rec) return ""
    var v = rec[key]
    if (v === undefined || v === null) return ""
    return String(v)
  }

  function hostLabel(rec) {
    if (!rec) return "Host"
    var name = hostField(rec, "label").trim()
    if (name !== "") return name
    var hostName = hostField(rec, "host").trim()
    if (hostName !== "") return hostName
    var id = hostField(rec, "id").trim()
    return id !== "" ? id : "Host"
  }

  readonly property bool opened:
    panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  function applyStore(text) {
    try {
      var store = JSON.parse(text)
      root.hosts = store.hosts || []
      root.activeHostId = store.activeId || (root.hosts.length > 0 ? root.hosts[0].id : "")
      if (root.hosts.length === 0) {
        root.hostStates = ({})
        return
      }
      var next = {}
      var i, h
      for (i = 0; i < root.hosts.length; i++) {
        h = root.hosts[i]
        if (hostStates[h.id]) next[h.id] = hostStates[h.id]
      }
      root.hostStates = next
    } catch (e) {}
  }

  function applyPayload(text, hostId) {
    var id = hostId || fetchTargetId || activeHostId
    if (!id) return
    try {
      var next = JSON.parse(text)
      if (!next || typeof next !== "object") {
        patchHostState(id, { everLoaded: true, errorText: "invalid response from poller" })
        return
      }
      if (next.error) {
        patchHostState(id, { everLoaded: true, errorText: String(next.error), info: next })
        return
      }
      if (notifyUnhealthy)
        notifyNewUnhealthy(stateFor(id).info.containers || [], next.containers || [], hostLabel(hostRecord(id)))
      patchHostState(id, { everLoaded: true, errorText: "", info: next })
    } catch (e) {
      patchHostState(id, { everLoaded: true, errorText: "invalid response from poller" })
    }
  }

  function notifyNewUnhealthy(before, after, label) {
    var prev = {}
    var i
    for (i = 0; i < before.length; i++)
      prev[before[i].id] = before[i].health || ""
    for (i = 0; i < after.length; i++) {
      var c = after[i]
      if (c.health === "unhealthy" && prev[c.id] !== "unhealthy") {
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Docker Remote",
          label + ": unhealthy", (c.service || c.name) + " is failing its health check"])
      }
    }
  }

  function loadConfig() {
    if (configLoader.running) return
    configLoader.running = true
  }

  function recordCommand(rec) {
    if (!rec) return []
    var port = String(rec.portBaseUrl || "").trim()
    if (port === "" && rec.host) port = "http://" + rec.host
    return [rec.host, rec.sshUser, rec.sshIdentityFile || "", port]
  }

  function refreshHostById(id, verbose) {
    var rec = hostRecord(id)
    if (!rec || !rec.host || !rec.sshUser) return false
    if (verbose ? detailsFetcher.running : fetcher.running) return false
    fetchTargetId = rec.id
    var cmd = ["/bin/bash", statusScript].concat(recordCommand(rec))
    if (verbose) cmd.push("--verbose")
    if (verbose) {
      detailsFetcher.command = cmd
      detailsFetcher.running = true
    } else {
      fetcher.command = cmd
      fetcher.running = true
    }
    return true
  }

  function refreshBackgroundHost() {
    if (hosts.length <= 1) return
    if (fetcher.running || detailsFetcher.running) return
    var i, idx, h
    for (i = 0; i < hosts.length; i++) {
      idx = (backgroundHostIndex + i) % hosts.length
      h = hosts[idx]
      if (h.id === activeHostId) continue
      if (refreshHostById(h.id, false)) {
        backgroundHostIndex = (idx + 1) % hosts.length
        return
      }
    }
  }

  function refresh(verbose) {
    if (hosts.length === 0) {
      patchHostState(activeHostId || "pending", { everLoaded: true, errorText: "", info: { reachable: false, containers: [] } })
      return
    }
    refreshHostById(activeHostId, verbose)
  }

  function selectHost(id) {
    if (!id || id === activeHostId) return
    activeHostId = id
    if (activeSelector.running) return
    activeSelector.command = ["/bin/bash", configScript, "set-active", instanceId, id]
    activeSelector.running = true
    refresh(false)
  }

  function setBusyId(id, value) {
    patchHostState(id || activeHostId, { busyId: value || "" })
  }

  function addHost(hostValue, userValue, labelValue, portValue, identityValue) {
    if (hostAdder.running) return
    hostAdder.command = [
      "/bin/bash", configScript, "add", instanceId,
      "host=" + hostValue,
      "sshUser=" + userValue,
      "label=" + labelValue,
      "portBaseUrl=" + portValue,
      "sshIdentityFile=" + identityValue
    ]
    hostAdder.running = true
  }

  function removeHost(id) {
    if (!id || hostRemover.running) return
    hostRemover.command = ["/bin/bash", configScript, "remove", instanceId, id]
    hostRemover.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  Component.onCompleted: loadConfig()

  Process {
    id: configLoader
    running: false
    command: ["/bin/bash", root.configScript, "list", root.instanceId]
    stdout: StdioCollector {
      onStreamFinished: {
        root.applyStore(text)
        root.refresh(false)
      }
    }
  }

  Process {
    id: activeSelector
    running: false
    stdout: StdioCollector { onStreamFinished: root.applyStore(text) }
  }

  Process {
    id: hostAdder
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.applyStore(text)
        if (panelLoader.item) panelLoader.item.addingHost = false
        root.refresh(false)
      }
    }
  }

  Process {
    id: hostRemover
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.applyStore(text)
        if (panelLoader.item) {
          panelLoader.item.addingHost = root.hosts.length === 0
          panelLoader.item.pendingConfirm = null
        }
        root.refresh(false)
      }
    }
  }

  Process {
    id: fetcher
    running: false
    onRunningChanged: root.fetching = fetcher.running || detailsFetcher.running
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(text, root.fetchTargetId)
    }
  }

  Process {
    id: detailsFetcher
    running: false
    onRunningChanged: root.fetching = fetcher.running || detailsFetcher.running
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(text, root.fetchTargetId)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Timer {
    interval: (root.opened ? 10 : root.interval) * 1000
    running: root.hosts.length > 0
    repeat: true
    triggeredOnStart: false
    onTriggered: {
      root.refresh(root.opened)
      root.refreshBackgroundHost()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.alerting
    text: {
      if (root.hosts.length === 0 || !root.everLoaded) return "󰡨"
      if (!root.reachable && root.hosts.length === 1) return "󰡨"
      if (root.showCount && root.totalCount > 0)
        return "󰡨 " + root.runningCount + "/" + root.totalCount
      if (root.runningCount > 0) return "󰡨 " + root.runningCount
      return "󰡨"
    }
    slotSize: root.showCount && root.totalCount > 0 ? -1 : Style.bar.statusSlot
    tooltipText: {
      if (root.hosts.length === 0) return "Docker Remote — add a host"
      if (!root.reachable) return root.displayLabel + ": " + (root.errorText || "unreachable")
      var s = root.displayLabel + " — " + root.runningCount + "/" + root.totalCount + " running"
      if (root.unhealthyCount > 0) s += " · " + root.unhealthyCount + " unhealthy"
      if (root.hosts.length > 1) s += " · " + root.hosts.length + " hosts"
      return s
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refresh(root.opened)
    }

    Rectangle {
      visible: root.unhealthyCount > 0 && root.reachable
      width: Style.space(6)
      height: width
      radius: width / 2
      color: root.bar && root.bar.urgent !== undefined ? root.bar.urgent : "#cc6666"
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(4)
      anchors.topMargin: Style.space(4)
    }
  }
}

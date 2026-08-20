import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.brukb.docker-remote"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barForeground: bar ? bar.barForeground : Style.foreground
  readonly property color dim: Qt.darker(barForeground, 1.4)
  readonly property color urgent: bar && bar.urgent !== undefined ? bar.urgent : "#cc6666"
  readonly property color faint: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.25)

  readonly property bool configured: hostWidget ? hostWidget.configured : false
  readonly property var hosts: hostWidget ? hostWidget.hosts : []
  readonly property string activeHostId: hostWidget ? hostWidget.activeHostId : ""
  property bool addingHost: false
  readonly property bool reachable: hostWidget ? hostWidget.reachable : false
  readonly property string title: hostWidget ? hostWidget.displayLabel : "Docker"
  readonly property var stacks: hostWidget ? hostWidget.stacks : []
  readonly property var standalone: hostWidget ? hostWidget.standalone : []
  readonly property int runningCount: hostWidget ? hostWidget.runningCount : 0
  readonly property int totalCount: hostWidget ? hostWidget.totalCount : 0
  readonly property int unhealthyCount: hostWidget ? hostWidget.unhealthyCount : 0
  readonly property string errorText: hostWidget ? hostWidget.errorText : ""
  readonly property bool fetching: hostWidget ? hostWidget.fetching : false
  readonly property var hostStatus: hostWidget ? hostWidget.hostStatus : null
  readonly property string portBaseUrl: hostWidget ? hostWidget.portBaseUrl : ""
  readonly property string terminalCmd: hostWidget ? hostWidget.terminalCmd : "xdg-terminal-exec"

  property var stats: ({})
  property var pendingConfirm: null
  property bool spinning: false
  property string setupHost: ""
  property string setupUser: ""
  property string setupLabel: ""
  property string setupPortBase: ""
  property string setupIdentity: ""
  property string setupError: ""

  readonly property string statusText: {
    if (addingHost || hosts.length === 0) return "Add a remote Docker host"
    if (!configured) return "Choose a remote host below"
    if (fetching && !everLoaded) return "Connecting…"
    if (!reachable) return errorText !== "" ? errorText : "Remote host unreachable"
    if (totalCount === 0) return "No containers on " + title
    var s = runningCount + " of " + totalCount + " running"
    if (unhealthyCount > 0) s += " · " + unhealthyCount + " unhealthy"
    return s
  }

  readonly property bool everLoaded: hostWidget ? hostWidget.everLoaded : false

  function refresh(verbose) {
    if (hostWidget) hostWidget.refresh(verbose === true)
  }

  function sshArgs() {
    var args = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "LogLevel=ERROR"]
    if (hostWidget && hostWidget.sshIdentityFile !== "")
      args = args.concat(["-i", hostWidget.sshIdentityFile])
    return args
  }

  function sshTarget() {
    return hostWidget.sshUser + "@" + hostWidget.host
  }

  function runAction(cmd) {
    if (actionProc.running || !hostWidget) return
    actionProc.command = cmd
    actionProc.running = true
  }

  function setBusy(value) {
    if (hostWidget) hostWidget.setBusyId(hostWidget.activeHostId, value || "")
  }

  function containerAction(c, action) {
    if (!hostWidget || hostWidget.busyId !== "" || !reachable) return
    setBusy(c.id)
    var act = action
    if (action === "start" && c.state === "paused") act = "unpause"
    runAction([
      hostWidget.actionScript, hostWidget.host, hostWidget.sshUser,
      hostWidget.sshIdentityFile, "container", act, c.id
    ])
  }

  function stackAction(stack, start) {
    if (!hostWidget || hostWidget.busyId !== "" || !reachable) return
    var i, c
    setBusy("stack:" + stack.name)
    if (start) {
      for (i = 0; i < stack.containers.length; i++) {
        c = stack.containers[i]
        if (!c.workingDir) continue
        runAction([
          hostWidget.actionScript, hostWidget.host, hostWidget.sshUser,
          hostWidget.sshIdentityFile, "stack-start", c.workingDir, c.configFiles || ""
        ])
        return
      }
    }
    var ids = []
    for (i = 0; i < stack.containers.length; i++) {
      c = stack.containers[i]
      if (start !== (c.state === "running")) ids.push(c.id)
    }
    if (ids.length === 0) {
      setBusy("")
      return
    }
    runAction([
      hostWidget.actionScript, hostWidget.host, hostWidget.sshUser,
      hostWidget.sshIdentityFile, "stack-stop"
    ].concat(ids))
  }

  function requestConfirm(message, confirmText, cmd, busyKey) {
    if (!hostWidget || hostWidget.busyId !== "" || !reachable) return
    pendingConfirm = {
      kind: "action",
      message: message,
      confirmText: confirmText,
      cmd: cmd,
      busyKey: busyKey
    }
  }

  function requestRemoveHost(rec) {
    if (!hostWidget || !rec || hostWidget.busyId !== "") return
    pendingConfirm = {
      kind: "host",
      message: "Remove " + hostTabLabel(rec) + " (" + (rec.host || rec.id) + ") from this widget?",
      confirmText: "Remove",
      hostId: rec.id
    }
  }

  function requestRemoveActiveHost() {
    if (!hostWidget) return
    var rec = hostWidget.activeRecord()
    if (rec) requestRemoveHost(rec)
  }

  function acceptConfirm() {
    if (!pendingConfirm || !hostWidget) return
    if (pendingConfirm.kind === "host") {
      hostWidget.removeHost(pendingConfirm.hostId)
      pendingConfirm = null
      return
    }
    setBusy(pendingConfirm.busyKey)
    runAction(pendingConfirm.cmd)
    pendingConfirm = null
  }

  function requestRemove(c) {
    requestConfirm(
      "Remove container " + c.name + " on " + title + "? Named volumes are kept.",
      "Remove",
      [hostWidget.actionScript, hostWidget.host, hostWidget.sshUser,
       hostWidget.sshIdentityFile, "container", "rm", c.id],
      c.id)
  }

  function runDetachedArgv(argv) {
    root.close()
    Quickshell.execDetached(argv)
  }

  function runDetachedShell(cmd) {
    root.close()
    if (root.bar) root.bar.run(cmd)
  }

  function showLogs(c) {
    var ssh = ["ssh", "-t"].concat(sshArgs()).concat([
      sshTarget(), "docker", "logs", "--tail", "200", "-f", c.id
    ])
    runDetachedArgv([terminalCmd, "--"].concat(ssh))
  }

  function openShell(c) {
    var ssh = ["ssh", "-t"].concat(sshArgs()).concat([
      sshTarget(), "docker", "exec", "-it", c.id, "sh"
    ])
    runDetachedArgv([terminalCmd, "--"].concat(ssh))
  }

  function portUrl(hostPort) {
    var base = String(portBaseUrl || "").replace(/\/$/, "")
    if (base === "") return "http://" + (hostWidget ? hostWidget.host : "") + ":" + hostPort
    // Scheme comes from portBaseUrl (http:// or https://). Docker does not expose it per port.
    var m = base.match(/^(https?:\/\/[^/:]+)(?::[0-9]+)?(\/.*)?$/)
    if (m) return m[1] + ":" + hostPort + (m[2] || "")
    return base + ":" + hostPort
  }

  function openPort(hostPort) {
    // xdg-open uses the desktop URL handler (new tab in the active browser).
    // omarchy-launch-browser wraps uwsm-app and can pin a specific app window.
    runDetachedArgv(["xdg-open", portUrl(hostPort)])
  }

  function openHostTerminal() {
    runDetachedArgv([terminalCmd, "--", "ssh", "-t"].concat(sshArgs()).concat([sshTarget()]))
  }

  function gib(bytes) { return (bytes / 1073741824).toFixed(1) }
  function gibRound(bytes) { return Math.round(bytes / 1073741824) }

  onFetchingChanged: {
    if (fetching) {
      spinning = true
      spinFloor.restart()
    }
  }

  Timer {
    id: spinFloor
    interval: 500
    onTriggered: root.spinning = false
  }

  function clearSetupFields() {
    setupHost = ""
    setupUser = ""
    setupLabel = ""
    setupPortBase = ""
    setupIdentity = ""
    setupError = ""
  }

  function enterAddMode() {
    clearSetupFields()
    addingHost = true
  }

  function hostTabAlert(rec) {
    if (!hostWidget || !rec) return false
    var st = hostWidget.stateFor(rec.id)
    if (!st.everLoaded) return false
    if (st.errorText || (st.info && st.info.reachable === false)) return true
    var cs = (st.info && st.info.containers) || []
    for (var i = 0; i < cs.length; i++)
      if (cs[i].health === "unhealthy") return true
    return false
  }

  function cancelAddMode() {
    addingHost = false
    setupError = ""
  }

  function hostTabLabel(rec) {
    if (hostWidget) return hostWidget.hostLabel(rec)
    if (!rec) return "Host"
    var name = rec["label"] !== undefined ? String(rec["label"]).trim() : ""
    if (name !== "") return name
    var hostName = rec["host"] !== undefined ? String(rec["host"]).trim() : ""
    if (hostName !== "") return hostName
    return rec["id"] || "Host"
  }

  readonly property bool showSetup: addingHost || hosts.length === 0
  readonly property bool showHostContent: configured && !addingHost

  function saveSetup() {
    setupError = ""
    var host = setupHostField.currentValue().trim()
    var user = setupUserField.currentValue().trim()
    var label = setupLabelField.currentValue().trim()
    var portBase = setupPortBaseField.currentValue().trim()
    var identity = setupIdentityField.currentValue().trim()
    setupHost = host
    setupUser = user
    setupLabel = label
    setupPortBase = portBase
    setupIdentity = identity
    if (host === "" || user === "") {
      setupError = "Host and SSH user are required."
      return
    }
    if (hostWidget)
      hostWidget.addHost(host, user, label, portBase, identity)
  }

  function updateStats(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      try {
        var s = JSON.parse(lines[i])
        if (s.ID) next[s.ID] = {
          cpu: s.CPUPerc || "",
          mem: (s.MemUsage || "").split(" /")[0].replace(/\.[0-9]+/, "")
        }
      } catch (e) {}
    }
    stats = next
  }

  onOpenedChanged: {
    if (opened) {
      if (hosts.length === 0) addingHost = true
      else addingHost = false
      setupHost = hostWidget ? hostWidget.host : ""
      setupUser = hostWidget ? hostWidget.sshUser : ""
      setupLabel = hostWidget ? hostWidget.clusterLabel : ""
      setupPortBase = hostWidget ? hostWidget.portBaseUrl : ""
      setupIdentity = hostWidget ? hostWidget.sshIdentityFile : ""
      refresh(true)
    } else {
      addingHost = false
      pendingConfirm = null
      stats = {}
    }
  }

  Process {
    id: actionProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var payload = JSON.parse(text)
          if (payload.error && hostWidget)
            hostWidget.patchHostState(hostWidget.activeHostId, { errorText: String(payload.error) })
        } catch (e) {}
        if (hostWidget) hostWidget.setBusyId(hostWidget.activeHostId, "")
        refresh(true)
      }
    }
    onExited: if (hostWidget) hostWidget.setBusyId(hostWidget.activeHostId, "")
  }

  Process {
    id: statsProc
    running: false
    stdout: StdioCollector { onStreamFinished: root.updateStats(text) }
  }

  Timer {
    interval: 3000
    running: root.opened && root.reachable
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!hostWidget || statsProc.running) return
      var ssh = ["ssh"].concat(root.sshArgs()).concat([
        root.sshTarget(), "docker", "stats", "--no-stream", "--format", "{{json .}}"
      ])
      statsProc.command = ssh
      statsProc.running = true
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "Docker · " + root.title
            meta: root.statusText
            foreground: root.barForeground
            fontFamily: root.fontFamily
            iconOpacity: root.reachable ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: "󰡨"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item {
            width: parent.width
            height: hostTabBar.implicitHeight
            visible: root.hosts.length > 0

            Row {
              id: hostTabBar
              width: parent.width
              spacing: Style.space(4)

              Flickable {
                id: tabScroller
                width: Math.max(0, parent.width - removeHostTabBtn.implicitWidth
                  - addHostBtn.implicitWidth - Style.space(8))
                height: tabRow.implicitHeight
                contentWidth: tabRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                Row {
                  id: tabRow
                  spacing: Style.space(4)

                  Repeater {
                    model: root.hosts

                    Button {
                      required property var modelData
                      text: root.hostTabLabel(modelData)
                      bordered: true
                      active: !root.addingHost && modelData.id === root.activeHostId
                      fontSize: Style.font.caption
                      foreground: root.barForeground
                      fontFamily: root.fontFamily
                      tooltipText: {
                        var tip = root.hostTabLabel(modelData)
                        var host = modelData && modelData["host"] ? modelData["host"] : ""
                        if (host !== "" && tip !== host) return tip + " · " + host + " · right-click to remove"
                        return (host || tip) + " · right-click to remove"
                      }
                      onClicked: {
                        root.cancelAddMode()
                        if (hostWidget) hostWidget.selectHost(modelData.id)
                      }
                      onRightClicked: root.requestRemoveHost(modelData)

                      Rectangle {
                        visible: root.hostTabAlert(modelData)
                        width: Style.space(6)
                        height: width
                        radius: width / 2
                        color: root.urgent
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: Style.space(4)
                        anchors.topMargin: Style.space(4)
                      }
                    }
                  }
                }
              }

              Button {
                id: removeHostTabBtn
                iconText: "󰆴"
                text: ""
                bordered: true
                visible: root.hosts.length > 0 && !root.addingHost
                tooltipText: "Remove active host"
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onClicked: root.requestRemoveActiveHost()
              }

              Button {
                id: addHostBtn
                iconText: "󰐕"
                text: ""
                bordered: true
                active: root.addingHost
                tooltipText: "Add host"
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onClicked: root.enterAddMode()
              }
            }
          }

          Rectangle {
            width: parent.width
            visible: root.showHostContent && root.reachable && root.hostStatus !== null
            height: Math.max(hostRow.implicitHeight, hostButtonsRow.implicitHeight) + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.barForeground, 0.08)
            border.width: 1
            border.color: Util.alpha(root.barForeground, 0.3)

            Row {
              id: hostButtonsRow
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              PanelActionButton {
                id: hostTerminalBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰆍"
                tooltipText: "Terminal on host"
                foreground: root.barForeground
                fontFamily: root.fontFamily
                fontSize: Style.font.icon + 6
                onClicked: root.openHostTerminal()
              }

              PanelActionButton {
                id: refreshBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.barForeground
                fontFamily: root.fontFamily
                fontSize: Style.font.icon + 6
                onClicked: root.refresh(true)

                RotationAnimator {
                  target: refreshBtn
                  from: 0
                  to: 360
                  duration: 700
                  loops: Animation.Infinite
                  running: root.spinning
                  onRunningChanged: if (!running) refreshBtn.rotation = 0
                }
              }
            }

            Row {
              id: hostRow
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒋"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostStatus
                  ? "CPU " + Math.round(root.hostStatus.cpu * 100) + "%" : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostStatus
                  ? "RAM " + root.gib(root.hostStatus.mem_used) + "/"
                    + root.gibRound(root.hostStatus.mem_total) + " GiB" : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostStatus
                  ? "Disk " + root.gib(root.hostStatus.disk_used) + "/"
                    + root.gibRound(root.hostStatus.disk_total) + " GiB" : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Column {
            visible: root.showSetup
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.addingHost && root.hosts.length > 0 ? "ADD HOST" : "REMOTE HOST"
              foreground: root.barForeground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "SSH to a host where your user can run docker. Keys/agent only — no password prompts from the bar."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            LabeledField {
              id: setupHostField
              label: "Host"
              text: root.setupHost
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onValueEdited: function(v) { root.setupHost = v }
            }
            LabeledField {
              id: setupUserField
              label: "SSH user"
              text: root.setupUser
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onValueEdited: function(v) { root.setupUser = v }
            }
            LabeledField {
              id: setupLabelField
              label: "Label"
              text: root.setupLabel
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onValueEdited: function(v) { root.setupLabel = v }
            }
            LabeledField {
              id: setupPortBaseField
              label: "Port base URL"
              text: root.setupPortBase
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onValueEdited: function(v) { root.setupPortBase = v }
            }
            LabeledField {
              id: setupIdentityField
              label: "SSH key file"
              text: root.setupIdentity
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onValueEdited: function(v) { root.setupIdentity = v }
            }

            Text {
              visible: root.setupError !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.setupError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                iconText: "󰄬"
                text: root.addingHost && root.hosts.length > 0 ? "Add host" : "Save and connect"
                bordered: true
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onClicked: root.saveSetup()
              }

              Button {
                visible: root.addingHost && root.hosts.length > 0
                iconText: "󰅖"
                text: "Cancel"
                bordered: true
                foreground: root.barForeground
                fontFamily: root.fontFamily
                onClicked: root.cancelAddMode()
              }
            }
          }

          Column {
            visible: root.showHostContent && !root.reachable && !root.fetching
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Check SSH access, docker group membership on the remote host, and that the Docker daemon is running."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              iconText: "󰑐"
              text: "Retry"
              bordered: true
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onClicked: root.refresh(true)
            }
          }

          Repeater {
            model: root.stacks

            Column {
              required property var modelData
              readonly property bool stackBusy:
                hostWidget && hostWidget.busyId === ("stack:" + modelData.name)
              readonly property int upCount:
                hostWidget ? hostWidget.stackRunning(modelData) : 0
              readonly property bool anyUp: upCount > 0

              width: parent.width
              spacing: Style.space(8)
              visible: root.showHostContent && root.reachable

              PanelSeparator { foreground: root.barForeground }

              Item {
                width: parent.width
                implicitHeight: Math.max(hdr.implicitHeight, stackBtn.implicitHeight)

                PanelSectionHeader {
                  id: hdr
                  text: modelData.name.toUpperCase() + " · " + upCount + "/"
                    + modelData.containers.length + " up"
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  foreground: root.barForeground
                  fontFamily: root.fontFamily
                }

                Button {
                  id: stackBtn
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: anyUp ? "󰓛" : "󰐊"
                  text: anyUp ? "Stop" : "Start"
                  fontSize: Style.font.caption
                  bordered: true
                  enabled: root.reachable && !stackBusy && (!hostWidget || hostWidget.busyId === "")
                  opacity: stackBusy ? 0.5 : 1
                  foreground: root.barForeground
                  fontFamily: root.fontFamily
                  onClicked: root.stackAction(modelData, !anyUp)
                }
              }

              Repeater {
                model: modelData.containers
                delegate: ContainerRow {
                  required property var modelData
                  width: parent.width
                  container: modelData
                  groupBusy: stackBusy
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showHostContent && root.reachable && root.standalone.length > 0
            foreground: root.barForeground
          }

          Column {
            visible: root.showHostContent && root.reachable && root.standalone.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CONTAINERS"
              foreground: root.barForeground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.standalone
              delegate: ContainerRow {
                required property var modelData
                width: parent.width
                container: modelData
                groupBusy: false
              }
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        opened: root.pendingConfirm !== null
        message: root.pendingConfirm ? root.pendingConfirm.message : ""
        confirmText: root.pendingConfirm ? root.pendingConfirm.confirmText : "Confirm"
        fontFamily: root.fontFamily
        onConfirmed: root.acceptConfirm()
        onCanceled: root.pendingConfirm = null
      }
    }
  }

  component LabeledField: Column {
    id: fieldRoot
    property string label: ""
    property string text: ""
    property color foreground
    property string fontFamily: Style.font.family
    signal valueEdited(string value)

    function currentValue() {
      return input.text
    }

    width: parent.width
    spacing: Style.space(4)

    Text {
      text: fieldRoot.label
      color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.68)
      font.family: fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: input
      width: parent.width
      text: fieldRoot.text
      color: foreground
      font.family: fontFamily
      onTextChanged: fieldRoot.valueEdited(text)
      onEditingFinished: fieldRoot.valueEdited(text)
    }
  }

  component ContainerRow: Column {
    id: row
    property var container: ({})
    property bool groupBusy: false

    readonly property bool running: container.state === "running"
    readonly property bool paused: container.state === "paused"
    readonly property bool unhealthy: container.health === "unhealthy"
    readonly property bool rowBusy:
      hostWidget && (hostWidget.busyId === container.id || groupBusy)
    readonly property var stat: root.stats[container.id] || null
    readonly property string detail: {
      if (unhealthy) return "unhealthy"
      if (container.health === "starting") return "starting"
      if (paused) return "paused"
      if (container.state === "restarting") return "restarting"
      if (!running) return "exited"
      return ""
    }

    spacing: Style.space(2)
    opacity: rowBusy ? 0.5 : 1

    Item {
      width: parent.width
      implicitHeight: Math.max(nameCol.implicitHeight, actions.implicitHeight)

      Rectangle {
        id: dot
        width: Style.space(8)
        height: width
        radius: width / 2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: row.unhealthy ? root.urgent : (row.running ? root.barForeground : "transparent")
        border.width: row.running || row.unhealthy ? 0 : 1
        border.color: root.faint
      }

      Column {
        id: nameCol
        anchors.left: dot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: portsRow.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: row.container.name || ""
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: (row.container.image || "")
            + (row.running && row.stat ? " · " + row.stat.cpu + " · " + row.stat.mem : "")
            + (row.detail ? " · " + row.detail : "")
          color: row.unhealthy ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: portsRow
        anchors.right: actions.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Repeater {
          model: row.container.portsList || []
          delegate: Text {
            required property var modelData
            text: modelData.label
            color: portArea.containsMouse ? root.barForeground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              id: portArea
              anchors.fill: parent
              enabled: modelData.web && row.running
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.openPort(modelData.host)
            }
          }
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Button {
          iconText: "󰈙"
          tooltipText: "Logs"
          fontSize: Style.font.caption
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.showLogs(row.container)
        }

        Button {
          opacity: row.running ? 1 : 0
          enabled: row.running
          iconText: "󰆍"
          tooltipText: "Shell"
          fontSize: Style.font.caption
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.openShell(row.container)
        }

        Button {
          visible: !row.running
          iconText: "󰩺"
          tooltipText: "Remove"
          fontSize: Style.font.caption
          bordered: true
          enabled: root.reachable && !row.rowBusy && (!hostWidget || hostWidget.busyId === "")
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.requestRemove(row.container)
        }

        Button {
          visible: row.running
          iconText: "󰜉"
          tooltipText: "Restart"
          fontSize: Style.font.caption
          bordered: true
          enabled: root.reachable && !row.rowBusy && (!hostWidget || hostWidget.busyId === "")
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.containerAction(row.container, "restart")
        }

        Button {
          iconText: row.running ? "󰓛" : "󰐊"
          tooltipText: row.running ? "Stop" : (row.paused ? "Unpause" : "Start")
          fontSize: Style.font.caption
          bordered: true
          enabled: root.reachable && !row.rowBusy && (!hostWidget || hostWidget.busyId === "")
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.containerAction(row.container, row.running ? "stop" : "start")
        }
      }
    }

    Text {
      visible: !row.running && !!row.container.note
      x: Style.space(18)
      width: parent.width - x
      wrapMode: Text.WordWrap
      text: "󰀦 " + (row.container.note || "")
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}

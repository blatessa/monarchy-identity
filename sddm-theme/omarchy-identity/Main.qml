// omarchy-identity login theme: Omarchy's look, plus an editable username line so directory
// (corporate) users can sign in. Upstream theme only logs in userModel.lastUser.
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function tryLogin() {
    var user = username.text.trim()
    if (user.length === 0) {
      username.forceActiveFocus()
      return
    }
    sddm.login(user, password.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 28

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    // username
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Item { width: 34; height: 38 }   // aligns with the lock icon below

      Item {
        width: userEntry.width
        height: userEntry.height

        Image {
          id: userEntry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        TextInput {
          id: username
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 20
          color: "#a9b1d6"
          selectionColor: "#33467c"
          selectedTextColor: "#c0caf5"
          selectByMouse: true
          clip: true
          text: userModel.lastUser
          inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhPreferLowercase
          KeyNavigation.tab: password
          KeyNavigation.down: password
          onTextChanged: root.loginFailed = false
          Keys.onReturnPressed: password.forceActiveFocus()
          Keys.onEnterPressed: password.forceActiveFocus()
        }
      }
    }

    // password
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "•"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          KeyNavigation.backtab: username
          KeyNavigation.up: username
          onTextChanged: root.loginFailed = false
          Keys.onReturnPressed: root.tryLogin()
          Keys.onEnterPressed: root.tryLogin()
        }
      }
    }
  }

  Component.onCompleted: {
    if (username.text.length > 0) password.forceActiveFocus()
    else username.forceActiveFocus()
  }
}

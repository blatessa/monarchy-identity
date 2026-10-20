// monarchy-identity login theme: Omarchy's look, plus an editable username line so directory
// (corporate) users can sign in. Upstream theme only logs in userModel.lastUser. When the directory wants a code after
// the password (lib/login-steps says so), a code line appears, and the password and code go to SDDM together. When the
// password must be changed, two new-password lines appear the same way.
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property bool loginFailed: false
  property string message: ""   // from the directory during sign-in, e.g. the number to approve on the phone
  property bool trying: false   // a sign-in is in progress (SDDM reports a failure twice; the first one counts)
  property bool codeAsked: false   // this attempt: lib/login-steps said a code is wanted
  property bool codeWanted: false   // the code line is showing
  property bool newAsked: false   // this attempt: lib/login-steps said a new password is wanted
  property bool newWanted: false   // the new-password lines are showing
  property bool changed: false   // this attempt: the directory took the new password
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
    if (root.codeWanted && code.text.trim().length === 0) {
      code.forceActiveFocus()
      return
    }
    if (root.newWanted) {
      if (newPassword.text.length === 0) { newPassword.forceActiveFocus(); return }
      if (confirmPassword.text !== newPassword.text) {
        root.message = "The new passwords don't match. Type the new one again."
        confirmPassword.text = ""
        confirmPassword.forceActiveFocus()
        return
      }
    }
    root.message = ""
    root.codeAsked = false
    root.newAsked = false
    root.changed = false
    root.trying = true
    // lib/login-steps splits them: the first line answers the password prompt, the second the code prompt, the third
    // the new-password prompts
    var secret = password.text
    if (root.codeWanted || root.newWanted) secret += "\n" + (root.codeWanted ? code.text.trim() : "")
    if (root.newWanted) secret += "\n" + newPassword.text
    sddm.login(user, secret, root.sessionIndex)
  }

  function clearNew() {
    root.newWanted = false
    newPassword.text = ""
    confirmPassword.text = ""
  }

  Connections {
    target: sddm
    function onInformationMessage(message) {
      // the directory's own words while it's asked; SDDM's error text after a failure isn't for people
      if (!root.trying || root.codeAsked || root.newAsked) return
      if (message === "monarchy-identity: code wanted") root.codeAsked = true
      else if (message === "monarchy-identity: new password wanted") root.newAsked = true
      else if (message === "monarchy-identity: password changed") root.changed = true
      else root.message = message
    }
    function onLoginFailed() {
      if (!root.trying) return
      root.trying = false
      if (root.changed) {   // the directory has the new password: it's the password from now on
        password.text = newPassword.text
        root.clearNew()
        if (!root.codeAsked) {   // signing in again with it didn't finish (a code is spent once): try again
          root.message = root.codeWanted ? "Password changed. Enter a new code to sign in." : "Password changed. Press Enter to sign in."
          if (root.codeWanted) { code.text = ""; code.forceActiveFocus() } else password.forceActiveFocus()
          return
        }
      }
      if (root.newAsked) {   // the password was right, but must be changed (the directory's message says so)
        root.newAsked = false
        root.newWanted = true
        newPassword.text = ""
        confirmPassword.text = ""
        if (root.codeWanted) {   // that code is spent: a fresh one with the new password
          code.text = ""
          code.forceActiveFocus()
        } else newPassword.forceActiveFocus()
        return
      }
      if (root.newWanted) {   // the new password wasn't taken: the directory's message says why
        root.loginFailed = true
        newPassword.text = ""
        confirmPassword.text = ""
        newPassword.forceActiveFocus()
        return
      }
      if (root.codeAsked) {   // the password was right; now the code (the directory's message says which)
        root.codeAsked = false
        root.codeWanted = true
        code.text = ""
        code.forceActiveFocus()
        return
      }
      root.loginFailed = true
      root.message = ""
      if (root.codeWanted) {
        code.text = ""
        code.forceActiveFocus()
        return
      }
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.trying = false
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
          onTextChanged: { root.loginFailed = false; root.codeWanted = false; root.clearNew() }
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
          KeyNavigation.tab: root.newWanted ? newPassword : code
          KeyNavigation.down: root.newWanted ? newPassword : code
          onTextChanged: { root.loginFailed = false; if (activeFocus) { root.codeWanted = false; root.clearNew() } }
          Keys.onReturnPressed: root.tryLogin()
          Keys.onEnterPressed: root.tryLogin()
        }
      }
    }

    // code, when the directory wants one after the password
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15
      visible: root.codeWanted

      Item { width: 34; height: 38 }

      Item {
        width: codeEntry.width
        height: codeEntry.height

        Image {
          id: codeEntry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        TextInput {
          id: code
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          color: "#a9b1d6"
          selectionColor: "#33467c"
          selectedTextColor: "#c0caf5"
          inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
          maximumLength: 16
          KeyNavigation.backtab: password
          KeyNavigation.up: password
          onTextChanged: root.loginFailed = false
          Keys.onReturnPressed: root.tryLogin()
          Keys.onEnterPressed: root.tryLogin()
        }
      }
    }

    // new password, when the password must be changed
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15
      visible: root.newWanted

      Item { width: 34; height: 38 }

      Item {
        width: newPasswordEntry.width
        height: newPasswordEntry.height

        Image {
          id: newPasswordEntry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          visible: newPassword.text.length === 0
          text: "new password"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 18
          color: "#565f89"
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(newPassword.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: newPassword
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
          KeyNavigation.backtab: password
          KeyNavigation.up: password
          KeyNavigation.tab: confirmPassword
          KeyNavigation.down: confirmPassword
          onTextChanged: root.loginFailed = false
          Keys.onReturnPressed: confirmPassword.forceActiveFocus()
          Keys.onEnterPressed: confirmPassword.forceActiveFocus()
        }
      }
    }

    // new password again, when the password must be changed
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15
      visible: root.newWanted

      Item { width: 34; height: 38 }

      Item {
        width: confirmPasswordEntry.width
        height: confirmPasswordEntry.height

        Image {
          id: confirmPasswordEntry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          visible: confirmPassword.text.length === 0
          text: "new password again"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 18
          color: "#565f89"
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(confirmPassword.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: confirmPassword
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
          KeyNavigation.backtab: newPassword
          KeyNavigation.up: newPassword
          onTextChanged: root.loginFailed = false
          Keys.onReturnPressed: root.tryLogin()
          Keys.onEnterPressed: root.tryLogin()
        }
      }
    }

    Text {
      width: Math.min(root.width * 0.8, 720)
      anchors.horizontalCenter: parent.horizontalCenter
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: root.message.length > 0
      text: root.message
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 18
      color: "#a9b1d6"
    }
  }

  Component.onCompleted: {
    if (username.text.length > 0) password.forceActiveFocus()
    else username.forceActiveFocus()
  }
}

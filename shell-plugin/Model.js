.pragma library

// Pure parsing of `monarchy-identity status --json`. No QML or shell types so
// tests/test_model.js can run it under node.
//
// state: "unavailable" | "local" | "ok" | "warn"
//   unavailable  CLI missing, errored, or printed something unparseable
//   local        parsed fine, machine is not enrolled
//   ok           enrolled, no posture warnings
//   warn         enrolled, but autologin is on or local wheel members exist

function unavailable(reason) {
  return {
    state: "unavailable",
    summary: "identity: unavailable",
    reason: String(reason || ""),
    warnings: [],
    rows: []
  }
}

function wheelList(value) {
  if (Array.isArray(value)) return value.map(String).filter(function(s) { return s !== "" })
  return String(value === undefined || value === null ? "" : value)
    .split(",").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" })
}

function parse(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return unavailable("unparseable output") }
  if (data === null || typeof data !== "object" || Array.isArray(data)) return unavailable("unexpected output")
  if (typeof data.enrolled !== "boolean") return unavailable("missing 'enrolled'")

  var provider = String(data.provider || "local")
  var mode = String(data.login_mode || "none")
  var autologin = data.autologin === true
  var wheel = wheelList(data.wheel_members)

  var warnings = []
  if (data.enrolled) {
    if (autologin) warnings.push("Autologin is enabled")
    if (wheel.length > 0) warnings.push("Local admins: " + wheel.join(", "))
  }

  var state = !data.enrolled ? "local" : (warnings.length > 0 ? "warn" : "ok")
  var summary = state === "local" ? "identity: not enrolled"
    : state === "ok" ? "identity: " + provider
    : "identity: " + provider + " (" + warnings.length + (warnings.length === 1 ? " warning)" : " warnings)")

  return {
    state: state,
    summary: summary,
    reason: "",
    warnings: warnings,
    rows: [
      { label: "Enrolled", value: data.enrolled ? "yes" : "no" },
      { label: "Provider", value: provider },
      { label: "Login mode", value: mode },
      { label: "Autologin", value: autologin ? "on" : "off" },
      { label: "Local admins", value: wheel.length > 0 ? wheel.join(", ") : "none" }
    ]
  }
}

// Nerd Font glyphs for the bar button.
function glyph(state) {
  if (state === "ok") return ""          // id-card
  if (state === "warn") return ""        // warning triangle
  if (state === "local") return ""       // user-circle-o
  return ""                              // question mark
}

.pragma library
// Why a sign-in failed, in people's words. HEARD is what SDDM passed on during the try: the modules' messages, then
// PAM's text for the result (pam_strerror). docs/dev/findings.md has what each case sends.
function explain(heard) {
  var all = heard.join("\n")
  if (all.indexOf("The account is locked") !== -1) {   // Omarchy's faillock, after too many wrong passwords
    var m = /\((\d+) minutes? left to unlock\)/.exec(all)
    return "Too many wrong passwords. Try again in " + (m ? m[1] + (m[1] === "1" ? " minute." : " minutes.") : "a few minutes.")
  }
  switch (heard.length ? heard[heard.length - 1] : "") {
  case "Authentication failure": return "Wrong password."
  case "User not known to the underlying authentication module":
    return "No account with that name. A first sign-in on this laptop needs the internet."
  case "Permission denied": return "This account can't sign in on this laptop. Ask IT."
  case "User account has expired": return "This account has expired. Ask IT."
  }
  return ""
}

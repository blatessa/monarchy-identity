// Run: node tests/test_model.js   (Model.js is a QML library; strip the pragma for node)
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const M = new Function(src + "; return { parse, unavailable, glyph }")()

const ok = (o) => JSON.stringify(Object.assign({ enrolled: true, provider: "sssd", login_mode: "groups", autologin: false, wheel_members: "" }, o))

let r = M.parse(ok({}));                       assert.equal(r.state, "ok");   assert.equal(r.summary, "identity: sssd")
r = M.parse(ok({ autologin: true }));          assert.equal(r.state, "warn"); assert.match(r.summary, /1 warning\)/)
r = M.parse(ok({ wheel_members: "brady,bob" })); assert.equal(r.state, "warn"); assert.match(r.warnings[0], /brady, bob/)
r = M.parse(ok({ autologin: true, wheel_members: "x" })); assert.match(r.summary, /2 warnings\)/)
r = M.parse(ok({ enrolled: false, provider: "local", login_mode: "none", autologin: true, wheel_members: "brady" }))
assert.equal(r.state, "local"); assert.equal(r.warnings.length, 0); assert.equal(r.summary, "identity: not enrolled")
r = M.parse(ok({ wheel_members: ["a", "b"] })); assert.equal(r.state, "warn")   // array form tolerated
for (const bad of ["", "not json", "[]", "null", "{}", '{"enrolled":"yes"}', undefined]) {
  r = M.parse(bad); assert.equal(r.state, "unavailable", "bad input: " + bad); assert.equal(r.summary, "identity: unavailable")
}
assert.equal(M.unavailable("x").reason, "x")
for (const s of ["ok", "warn", "local", "unavailable"]) assert.ok(M.glyph(s).length >= 1)
console.log("Model.js: all tests passed")

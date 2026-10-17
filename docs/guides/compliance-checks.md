# Compliance checks

Signing in with company credentials is one part of a laptop being in good shape. Others are whether the disk is
encrypted, whether a firewall is running, whether autologin is off and whether the screen locks. `monarchy-identity check`
turns your answer into pass or fail, per laptop, so your MDM, Ansible or a cron job can act on the result.

You write down what "healthy" means once, in a policy file. Every rule you list is checked and every rule you leave out
is ignored.

1. Copy the example and edit it:

    ```bash
    sudo install -m 644 /usr/share/doc/monarchy-identity/policy.example.toml /etc/monarchy-identity/policy.toml
    ```

2. Run it:

    ```bash
    monarchy-identity check            # human-readable
    monarchy-identity check --json     # machine-readable
    ```

![check output](../img/check.png)

The example is from a test VM that is not hardened, so several rules fail.

| Exit | Meaning |
|---|---|
| 0 | Every checked rule passed (skipped rules do not fail). |
| 1 | At least one rule failed. |
| 2 | Bad policy or input: missing file, unknown key, bad value, no rules. |

Exit 2 for unknown keys is deliberate: a typo must not silently weaken a policy. Values the tool cannot determine
fail the rule unless `unknown_is_failure = false`, in which case the rule is reported `SKIP`.

`--json` prints `{"compliant": bool, "results": [{"rule", "result", "detail"}]}`, where `result` is `PASS`, `FAIL` or
`SKIP`.

`check` runs the posture probes as the invoking user. The screen-lock rule reads that user's
`~/.config/omarchy/shell.json`; when run as root through an MDM it reads root's home and reports `unknown`. Run it
as the desktop user, or set `unknown_is_failure = false`, if you use `max_screen_lock_seconds`.

All rules are listed in [Compliance policy file](../reference/policy-file.md).

## Using it as an MDM or osquery check

`check` is a plain executable with an exit code, so it works as a custom compliance script. For ad-hoc queries
use the JSON report directly:

```bash
monarchy-identity status --json | jq -e '.enrolled and .compliance.disk_encryption=="true"'
```

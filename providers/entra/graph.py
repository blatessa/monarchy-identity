#!/usr/bin/env python3
"""Ask Entra ID what enroll needs to check before changing anything. Standard library only.

usage: graph.py discover TENANT
           prints the tenant id; fails if Entra has no such tenant
       graph.py resolve TENANT CLIENT_ID [--groups a,b] [--users u@x,v@x]    (client secret on stdin)
           prints "group<TAB>name<TAB>id" per group and "user<TAB>name" per user; fails, naming every group or user
           Entra doesn't have, or the credential problem in admin terms

The secret is an app registration's client secret (client credentials flow, Group.Read.All and User.Read.All
application permissions). Nothing is written anywhere.
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

AUTHORITY = "https://login.microsoftonline.com"
GRAPH = "https://graph.microsoft.com/v1.0"
TIMEOUT = 20

# AADSTS codes an admin can act on, in their terms.
AADSTS = {
    "90002": "Entra has no tenant named {tenant}",
    "700016": "the tenant has no app registration with client id {client}",
    "700038": "the tenant has no app registration with client id {client}",
    "7000215": "the client secret is wrong",
    "7000222": "the client secret has expired; create a new one for the app registration",
    "700024": "the client secret is not valid yet",
}


def fail(msg):
    sys.exit(msg)


def request(url, data=None, token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except ValueError:
            return e.code, {}
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        fail(f"cannot reach Entra ID ({getattr(e, 'reason', e)}); check the network and try again")


def discover(tenant):
    status, doc = request(f"{AUTHORITY}/{urllib.parse.quote(tenant)}/v2.0/.well-known/openid-configuration")
    issuer = doc.get("issuer", "") if status == 200 else ""
    parts = issuer.rstrip("/").split("/")
    if len(parts) < 2 or parts[-1] != "v2.0":
        fail(f"Entra has no tenant named {tenant}")
    return parts[-2]


def token(tenant, client, secret):
    status, doc = request(f"{AUTHORITY}/{urllib.parse.quote(tenant)}/oauth2/v2.0/token", {
        "grant_type": "client_credentials", "client_id": client, "client_secret": secret,
        "scope": "https://graph.microsoft.com/.default"})
    if status == 200 and doc.get("access_token"):
        return doc["access_token"]
    for code in doc.get("error_codes", []):
        if str(code) in AADSTS:
            fail(AADSTS[str(code)].format(tenant=tenant, client=client))
    fail(f"Entra refused the app registration's credentials: {doc.get('error_description', status).splitlines()[0]}")


def graph_get(path, tok):
    status, doc = request(GRAPH + path, token=tok)
    if status == 403:
        fail("the app registration may not read the directory: give it the Group.Read.All and User.Read.All "
             "application permissions, with admin consent")
    return status, doc


def resolve(tenant, client, groups, users, secret):
    tok = token(tenant, client, secret)
    out, missing, dupes = [], [], []
    for name in groups:
        q = urllib.parse.quote("displayName eq '" + name.replace("'", "''") + "'")
        status, doc = graph_get(f"/groups?$filter={q}&$select=id,displayName", tok)
        found = doc.get("value", []) if status == 200 else []
        if not found:
            missing.append(name)
        elif len(found) > 1:
            dupes.append(name)
        else:
            out.append(f"group\t{name}\t{found[0]['id']}")
    for upn in users:
        status, doc = graph_get(f"/users/{urllib.parse.quote(upn)}?$select=userPrincipalName", tok)
        if status == 200:
            out.append(f"user\t{doc.get('userPrincipalName', upn)}")
        else:
            missing.append(upn)
    problems = []
    if missing:
        problems.append("Entra has no group or user named: " + ", ".join(missing))
    if dupes:
        problems.append("more than one Entra group is named: " + ", ".join(dupes) + " (rename one; sign-in can't tell them apart)")
    if problems:
        fail("; ".join(problems))
    print("\n".join(out))


def split(v):
    return [x for x in v.split(",") if x]


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "discover":
        print(discover(a[1]))
    elif len(a) >= 3 and a[0] == "resolve":
        opts = dict(zip(a[3::2], a[4::2]))
        if set(opts) - {"--groups", "--users"} or len(a[3:]) % 2:
            fail(__doc__)
        secret = sys.stdin.readline().rstrip("\n")
        if not secret:
            fail("empty client secret")
        resolve(a[1], a[2], split(opts.get("--groups", "")), split(opts.get("--users", "")), secret)
    else:
        fail(__doc__)


if __name__ == "__main__":
    main()

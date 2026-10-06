#!/usr/bin/env python3
"""Cloudflare set-up for grails.arjoon.xyz, from the command line (standard library only).

  1. the `grails` CNAME to Vercel, if it is missing (DNS only, so Vercel can issue its own certificate);
  2. an Email Routing rule that sends hi@arjoon.xyz to your real inbox (Email Routing is already on for the zone).

It needs an API token, which it reads from CLOUDFLARE_API_TOKEN or asks for without echoing it. Make one at
https://dash.cloudflare.com/profile/api-tokens ▸ Create Token ▸ Custom token with:
  Zone ▸ Zone ▸ Read          Zone ▸ DNS ▸ Edit          Zone ▸ Email Routing Rules ▸ Edit
  Account ▸ Email Routing Addresses ▸ Edit               (zone resources: Include ▸ arjoon.xyz)

  Scripts/cloudflare-setup.py --to you@example.com          show what it would do
  Scripts/cloudflare-setup.py --to you@example.com --apply  do it

It never deletes anything, and running it again changes nothing that is already right. If the --to address is new to Cloudflare, it
sends a confirmation email to it: the rule starts working once the link in that email is clicked.
"""
import argparse, getpass, json, os, sys, urllib.error, urllib.request

API = os.environ.get("CF_API_BASE", "https://api.cloudflare.com/client/v4")
ZONE = "arjoon.xyz"
HOST = "grails.arjoon.xyz"
TARGET = "cname.vercel-dns.com"
ALIAS = "hi@arjoon.xyz"


def call(token, method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        try:
            data = json.load(e)
        except Exception:
            data = {"success": False, "errors": [{"message": f"HTTP {e.code}"}]}
    if not data.get("success"):
        msg = "; ".join(str(x.get("message")) for x in data.get("errors", [])) or "failed"
        sys.exit(f"Cloudflare said no ({method} {path}): {msg}")
    return data["result"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--to", required=True, help="the inbox hi@arjoon.xyz should land in")
    ap.add_argument("--apply", action="store_true", help="make the changes (otherwise only say what would change)")
    args = ap.parse_args()
    token = os.environ.get("CLOUDFLARE_API_TOKEN") or getpass.getpass("Cloudflare API token (not shown): ").strip()
    if not token:
        sys.exit("No token.")

    zones = call(token, "GET", f"/zones?name={ZONE}")
    if not zones:
        sys.exit(f"The token can't see the zone {ZONE}.")
    zone, account = zones[0]["id"], zones[0]["account"]["id"]
    todo = []

    # 1. DNS
    records = call(token, "GET", f"/zones/{zone}/dns_records?name={HOST}")
    good = [r for r in records if r["type"] == "CNAME" and r["content"].rstrip(".") == TARGET]
    if good:
        print(f"ok    {HOST} already points to {TARGET}" + (" (proxied)" if good[0].get("proxied") else ""))
    elif records:
        print(f"skip  {HOST} exists as {records[0]['type']} {records[0]['content']}: left alone, change it by hand if it is wrong")
    else:
        todo.append(("create the CNAME", lambda: call(token, "POST", f"/zones/{zone}/dns_records",
                     {"type": "CNAME", "name": "grails", "content": TARGET, "proxied": False, "ttl": 1})))
        print(f"add   CNAME {HOST} → {TARGET} (DNS only)")

    # 2. Email Routing
    rules = call(token, "GET", f"/zones/{zone}/email/routing/rules")
    mine = [r for r in rules if any(m.get("value", "").lower() == ALIAS for m in r.get("matchers", []))]
    if mine:
        where = [a.get("value") for r in mine for a in r.get("actions", [])]
        print(f"ok    {ALIAS} already routes to {', '.join(map(str, where))}")
    else:
        addresses = call(token, "GET", f"/accounts/{account}/email/routing/addresses")
        known = [a for a in addresses if a["email"].lower() == args.to.lower()]
        if not known:
            todo.append(("add the destination address", lambda: call(token, "POST", f"/accounts/{account}/email/routing/addresses", {"email": args.to})))
            print(f"add   destination {args.to} (Cloudflare emails it a confirmation link)")
        elif not known[0].get("verified"):
            print(f"wait  {args.to} is not confirmed yet: click the link in Cloudflare's email to it")
        todo.append(("create the rule", lambda: call(token, "POST", f"/zones/{zone}/email/routing/rules", {
            "name": f"{ALIAS} → inbox", "enabled": True,
            "matchers": [{"type": "literal", "field": "to", "value": ALIAS}],
            "actions": [{"type": "forward", "value": [args.to]}]})))
        print(f"add   rule {ALIAS} → {args.to}")

    if not todo:
        print("\nNothing to change.")
        return
    if not args.apply:
        print("\nDry run. Add --apply to make these changes.")
        return
    for label, fn in todo:
        fn()
        print(f"done  {label}")
    print("\nDone. If a confirmation email was sent, click its link; then write to hi@arjoon.xyz to test.")


if __name__ == "__main__":
    main()

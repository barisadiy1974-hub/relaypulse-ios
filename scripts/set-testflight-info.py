#!/usr/bin/env python3
"""Populate RelayPulse TestFlight information through App Store Connect API.

The App Store Connect signing details and reviewer contact information are read
only from environment variables.  They are deliberately never stored here.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request


APP_ID = "6808128260"
API_ROOT = "https://api.appstoreconnect.apple.com/v1"
LOCALE = "en-US"
DESCRIPTION = """RelayPulse lets you watch over your own servers from your iPhone.

Add a server once — address, port, and your SSH key or password — and
RelayPulse checks on it for you. It shows whether the machine is reachable,
whether the service you track is running, and how it is doing on CPU, memory,
bandwidth and connections. When something goes down you get a notification
instead of finding out hours later.

See everything on one colour-coded screen, tap a server for detail and history,
and act on a problem without leaving the app. AI-assisted diagnosis is there if
you want it: supply your own OpenAI or Anthropic key and the app reads the
error output and suggests a fix. It stays off until you turn it on.

There is no account and no RelayPulse server anywhere. Your list and your
credentials stay on the device, with keys and passwords in the iOS Keychain,
and the app talks only to the machines you enter.

Not ready to add a real one? Tap "Try Demo Fleet" on the first screen and look
around a sample fleet without connecting to anything.
"""
REVIEW_NOTES = """No account is required. RelayPulse has no sign-in and no backend of any kind.

The app administers servers the user already owns, so it normally needs a
server to talk to. For review you do not need one:

1. Launch the app.
2. On the first screen ("No relays yet"), tap "Try Demo Fleet".
3. A fictional sample fleet loads and every screen becomes browsable —
   dashboard, per-server detail, tools and settings.

While demo mode is on, no connection is made to any machine: SSH is disabled
outright, and the sample addresses come from the RFC 5737 documentation ranges,
which belong to no real host.

Two permission prompts may appear:
- Local Network — only when a server address is on the local network. Not
  needed in demo mode.
- Notifications — used to alert the user when one of their own servers is down.

AI-assisted diagnosis is off by default and requires the user's own API key.
It is not exercised in demo mode.

Privacy policy: https://barisadiy1974-hub.github.io/relaypulse/privacy.html
"""


def env(name):
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def read_der_length(data, offset):
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 2:
        raise ValueError("Unsupported DER signature length")
    length = int.from_bytes(data[offset : offset + count], "big")
    return length, offset + count


def der_ecdsa_to_jose(der):
    """Convert OpenSSL's DER ECDSA signature to JWT's 64-byte ES256 form."""
    if not der or der[0] != 0x30:
        raise ValueError("OpenSSL did not return a DER ECDSA signature")
    sequence_length, offset = read_der_length(der, 1)
    if offset + sequence_length != len(der):
        raise ValueError("Malformed DER ECDSA signature")

    integers = []
    for _ in range(2):
        if offset >= len(der) or der[offset] != 0x02:
            raise ValueError("Malformed DER ECDSA integer")
        integer_length, offset = read_der_length(der, offset + 1)
        integer = der[offset : offset + integer_length]
        offset += integer_length
        integer = integer.lstrip(b"\x00") or b"\x00"
        if len(integer) > 32:
            raise ValueError("ECDSA integer is larger than ES256")
        integers.append(integer.rjust(32, b"\x00"))
    return b"".join(integers)


def jwt():
    header = {"alg": "ES256", "kid": env("ASC_KEY_ID"), "typ": "JWT"}
    payload = {
        "iss": env("ASC_ISSUER_ID"),
        "exp": int(time.time()) + 900,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        f"{base64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{base64url(json.dumps(payload, separators=(',', ':')).encode())}"
    ).encode("ascii")
    signed = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", env("ASC_KEY_PATH")],
        input=signing_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if signed.returncode:
        raise RuntimeError(signed.stderr.decode("utf-8", "replace").strip())
    return f"{signing_input.decode('ascii')}.{base64url(der_ecdsa_to_jose(signed.stdout))}"


def request(method, path, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {jwt()}",
        "Accept": "application/json",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(API_ROOT + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        # The caller explicitly needs Apple's unmodified JSON error response.
        sys.stderr.write(error.read().decode("utf-8", "replace") + "\n")
        raise SystemExit(error.code)


def resource(kind, identifier, attributes, relationships=None):
    data = {"type": kind, "attributes": attributes}
    if identifier is not None:
        data["id"] = identifier
    if relationships:
        data["relationships"] = relationships
    return {"data": data}


def main():
    for name in (
        "ASC_ISSUER_ID",
        "ASC_KEY_ID",
        "ASC_KEY_PATH",
        "ASC_CONTACT_LAST_NAME",
        "ASC_CONTACT_PHONE",
        "ASC_CONTACT_EMAIL",
    ):
        env(name)

    app = request("GET", f"/apps/{APP_ID}")["data"]
    print(f"Verified app: {app['attributes'].get('bundleId', '(no bundle id returned)')}")

    localization_attributes = {
        "feedbackEmail": env("ASC_CONTACT_EMAIL"),
        "marketingUrl": "https://barisadiy1974-hub.github.io/relaypulse/",
        "privacyPolicyUrl": "https://barisadiy1974-hub.github.io/relaypulse/privacy.html",
        "description": DESCRIPTION,
    }
    localizations = request("GET", f"/apps/{APP_ID}/betaAppLocalizations")["data"]
    existing = next(
        (item for item in localizations if item["attributes"].get("locale") == LOCALE), None
    )
    if existing:
        localization = request(
            "PATCH",
            f"/betaAppLocalizations/{existing['id']}",
            resource("betaAppLocalizations", existing["id"], localization_attributes),
        )["data"]
    else:
        localization = request(
            "POST",
            "/betaAppLocalizations",
            resource(
                "betaAppLocalizations",
                None,
                {"locale": LOCALE, **localization_attributes},
                {"app": {"data": {"type": "apps", "id": APP_ID}}},
            ),
        )["data"]

    review_detail = request("GET", f"/apps/{APP_ID}/betaAppReviewDetail")["data"]
    review_attributes = {
        "contactFirstName": "Baris",
        "contactLastName": env("ASC_CONTACT_LAST_NAME"),
        "contactEmail": env("ASC_CONTACT_EMAIL"),
        "contactPhone": env("ASC_CONTACT_PHONE"),
        "demoAccountRequired": False,
        "demoAccountName": None,
        "demoAccountPassword": None,
        "notes": REVIEW_NOTES,
    }
    review = request(
        "PATCH",
        f"/betaAppReviewDetails/{review_detail['id']}",
        resource("betaAppReviewDetails", review_detail["id"], review_attributes),
    )["data"]

    # Re-read from Apple after writing; do not rely on PATCH responses.
    saved_localizations = request("GET", f"/apps/{APP_ID}/betaAppLocalizations")["data"]
    saved_localization = next(
        item for item in saved_localizations if item["id"] == localization["id"]
    )
    saved_review = request("GET", f"/apps/{APP_ID}/betaAppReviewDetail")["data"]

    print("\nSaved betaAppLocalization:")
    print(json.dumps({"id": saved_localization["id"], "attributes": saved_localization["attributes"]}, indent=2))
    print("\nSaved betaAppReviewDetail:")
    print(json.dumps({"id": saved_review["id"], "attributes": saved_review["attributes"]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError) as error:
        sys.stderr.write(f"{error}\n")
        raise SystemExit(1)

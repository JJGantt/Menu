#!/usr/bin/env python3
"""Put a just-uploaded build in front of the public-link testers (external group "capExt").

External groups never pick up new builds on their own, so release.sh runs this after the upload:
wait for App Store Connect to finish processing the build, add it to capExt, and submit it to Beta
App Review (a later build of an already-approved version clears in seconds).
Usage: testflight_public.py <build number>"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request

APP_ID = "6775855684"
CAPEXT = "718c1d73-ec87-4762-906a-4c66ecc46c99"
KEY_ID, ISSUER = "P8Y337A8RC", "141a8ead-b829-4e58-b9ff-b8c95f8c4ed9"
KEY = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")


def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def token():
    h = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    p = b64(json.dumps({"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=f"{h}.{p}".encode(),
                         capture_output=True, check=True).stdout
    # DER ECDSA signature -> the raw r||s the JWT wants
    i = 2; r = der[i + 2:i + 2 + der[i + 1]]; i += 2 + der[i + 1]; s = der[i + 2:i + 2 + der[i + 1]]
    return f"{h}.{p}.{b64(r[-32:].rjust(32, b'\0') + s[-32:].rjust(32, b'\0'))}"


def api(path, method="GET", body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        t = r.read()
        return json.loads(t) if t else None


def main(version):
    # Processing has no notification this script can receive, so it checks every 30s, for at most 30 min.
    for _ in range(60):
        builds = api(f"/v1/builds?filter[app]={APP_ID}&filter[version]={version}&fields[builds]=processingState")["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_YET_LISTED"
        if state == "VALID": break
        if state in ("FAILED", "INVALID"): sys.exit(f"build {version} processing ended {state}")
        print(f"  build {version}: {state}, waiting", flush=True)
        time.sleep(30)
    else:
        sys.exit(f"build {version} was not processed within 30 minutes; add it to capExt by hand")
    bid = builds[0]["id"]
    # Linked from the build's side: the group's side (/v1/betaGroups/{id}/relationships/builds) answers
    # 404 "no resource of type builds" for a build that has just finished processing.
    api(f"/v1/builds/{bid}/relationships/betaGroups", "POST", {"data": [{"type": "betaGroups", "id": CAPEXT}]})
    st = api(f"/v1/builds/{bid}/buildBetaDetail")["data"]["attributes"]["externalBuildState"]
    if st == "READY_FOR_BETA_SUBMISSION":
        api("/v1/betaAppReviewSubmissions", "POST",
            {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    for _ in range(10):
        st = api(f"/v1/builds/{bid}/buildBetaDetail")["data"]["attributes"]["externalBuildState"]
        if st == "IN_BETA_TESTING": break
        time.sleep(10)
    print(f"✓ build {version} in capExt: {st}")


if __name__ == "__main__":
    main(sys.argv[1])

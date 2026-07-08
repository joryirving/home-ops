import json
import os
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LATITUDE = os.environ["LATITUDE"]
LONGITUDE = os.environ["LONGITUDE"]
RADIUS_NM = os.environ.get("RADIUS_NM", "250")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "60"))
API_URL = f"https://api.adsb.lol/v2/point/{LATITUDE}/{LONGITUDE}/{RADIUS_NM}"

cache = {"body": b'{"now": 0, "aircraft": []}'}


def fetch():
    req = urllib.request.Request(API_URL, headers={"User-Agent": "acars-processor-adsb-shim"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)
    now = data.get("now", 0)
    if now > 1e12:  # ms -> s, tar1090 aircraft.json uses seconds
        now = now / 1000
    aircraft = data.get("ac", [])
    for a in aircraft:
        # readsb reports "ground" for grounded aircraft; the tar1090
        # annotator unmarshals alt_baro as an integer
        if isinstance(a.get("alt_baro"), str):
            a["alt_baro"] = 0
    cache["body"] = json.dumps({"now": now, "aircraft": aircraft}).encode()
    print(f"refreshed: {len(aircraft)} aircraft within {RADIUS_NM}nm", flush=True)


def poll():
    while True:
        try:
            fetch()
        except Exception as e:
            print(f"poll failed: {e}", flush=True)
        time.sleep(POLL_INTERVAL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/data/aircraft.json"):
            body = cache["body"]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass


threading.Thread(target=poll, daemon=True).start()
ThreadingHTTPServer(("", 8080), Handler).serve_forever()

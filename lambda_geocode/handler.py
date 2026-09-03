import os
import json
import re
import urllib.parse
import urllib.request
import math
import boto3

# Lambda geocode handler
# - follows short deep links and parses final URL for coordinates
# - prefers Places Details -> Places TextSearch -> Geocoding API for named places
# - supports optional `addressText` to force geocoding for homes/shops/malls
# - parses /dir/ destination coords when present

GEOCODE_KEY = os.environ.get("GOOGLE_MAPS_API_KEY")
DDB = boto3.resource("dynamodb")

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST,OPTIONS"
}


def respond(status=200, body=None):
    return {
        "statusCode": status,
        "headers": {**CORS_HEADERS, "Content-Type": "application/json"},
        "body": json.dumps(body or {})
    }


def resolve_redirect_url(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/7.64"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.geturl()


def parse_latlng_from_url(url):
    # Try a series of patterns; marker-style patterns have priority over viewport @
    patterns = [
        r'!3d([-+]?[0-9]+\.[0-9]+)!4d([-+]?[0-9]+\.[0-9]+)',
        r'/place/.*?/([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)',
        r'/dir/([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)(?:/|[?&]|$)',
        r'/dir/.*/([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)',
        r'[?&]ll=([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)',
        r'[?&]q=([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)',
        r'/@([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+),',
        r'@([-+]?[0-9]+\.[0-9]+),([-+]?[0-9]+\.[0-9]+)'
    ]
    for p in patterns:
        m = re.search(p, url)
        if m:
            try:
                return {"lat": float(m.group(1)), "lng": float(m.group(2)), "pattern": p}
            except Exception:
                pass
    return None


def extract_place_id(url):
    m = re.search(r'(ChI[0-9A-Za-z_-]{8,})', url)
    return m.group(1) if m else None


def extract_name_from_url(url):
    parsed = urllib.parse.urlparse(url)
    segs = [s for s in parsed.path.split('/') if s]
    qs = urllib.parse.parse_qs(parsed.query)

    for key in ['destination', 'q', 'query']:
        if qs.get(key):
            value = qs[key][0]
            if value and not re.match(r'^[-+]?\d+\.?\d*,[-+]?\d+\.?\d*$', value):
                return urllib.parse.unquote(value).replace('+', ' ').strip()

    # prefer /place/<name>
    if 'place' in segs:
        idx = segs.index('place')
        if idx + 1 < len(segs):
            raw = segs[idx + 1]
            raw = re.split(r'[@]|data=|/data|/dir|/maps', raw)[0]
            name = urllib.parse.unquote(raw).replace('+', ' ').strip()
            if name:
                return name

    # handle /dir/lat,lng/destination and /dir/?api=1&origin=...&destination=...
    if 'dir' in segs:
        try:
            idx = segs.index('dir')
            if idx + 1 < len(segs):
                candidate = urllib.parse.unquote(segs[idx + 1]).replace('+', ' ')
                if re.match(r'^[-+]?\d+\.?\d*,[-+]?\d+\.?\d*$', candidate):
                    if idx + 2 < len(segs):
                        candidate = urllib.parse.unquote(segs[idx + 2]).replace('+', ' ')
                candidate = re.sub(r'@[-\d.,]+.*', '', candidate)
                if candidate and not re.match(r'^[-+]?\d+\.?\d*,[-+]?\d+\.?\d*$', candidate):
                    return candidate
        except Exception:
            pass

    # last resort: last path segment
    if segs:
        last = urllib.parse.unquote(segs[-1])
        last = re.sub(r'@[-\d.,]+.*', '', last)
        if last and not re.match(r'^[-+]?\d+\.?\d*,[-+]?\d+\.?\d*$', last):
            return last.replace('+', ' ')
    return None


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.load(resp)


def call_places_details(place_id):
    if not GEOCODE_KEY:
        return None
    url = f"https://maps.googleapis.com/maps/api/place/details/json?place_id={urllib.parse.quote(place_id)}&fields=geometry&key={GEOCODE_KEY}"
    return fetch_json(url)


def call_places_textsearch(query):
    if not GEOCODE_KEY:
        return None
    q = urllib.parse.quote(query)
    url = f"https://maps.googleapis.com/maps/api/place/textsearch/json?query={q}&key={GEOCODE_KEY}"
    return fetch_json(url)


def geocode_by_api(address):
    if not GEOCODE_KEY:
        return None
    q = urllib.parse.quote(address)
    url = f"https://maps.googleapis.com/maps/api/geocode/json?address={q}&key={GEOCODE_KEY}"
    return fetch_json(url)


def is_probable_street_address(text: str) -> bool:
    # simple heuristic: contains a number and a street-type word
    if not text or not isinstance(text, str):
        return False
    if re.search(r'\d+', text) and re.search(r'\b(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct)\b', text, re.I):
        return True
    return False


def parse_event_body(event):
    body = event.get('body')
    data = {}
    if body:
        if isinstance(body, str):
            try:
                data = json.loads(body)
            except Exception:
                data = {"address": body}
        elif isinstance(body, dict):
            data = body
    if not data:
        data = event.get('queryStringParameters') or {}
    if not data.get('address') and event.get('address'):
        data['address'] = event.get('address')
    return data


def lambda_handler(event, context):
    print('DEBUG event:', json.dumps(event, default=str))
    method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method')
    if method == 'OPTIONS':
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ''}

    data = parse_event_body(event)
    print('DEBUG parsed body:', json.dumps(data, default=str))

    # Accept either deep link in `address` or raw address in `addressText`
    address_input = (data.get('address') or data.get('q') or '').strip() if data else ''
    address_text = (data.get('addressText') or data.get('address_text') or '').strip() if data else ''

    # If caller provided a human-readable addressText, prefer geocoding that (homes, shops)
    if address_text:
        if GEOCODE_KEY:
            gg = geocode_by_api(address_text)
            print('DEBUG geocode for addressText raw:', json.dumps(gg)[:1600] if gg else None)
            if gg and gg.get('status') == 'OK' and gg.get('results'):
                loc = gg['results'][0]['geometry']['location']
                return respond(200, {"lat": loc.get('lat'), "lng": loc.get('lng'), "source": 'geocode_addressText'})

    if not address_input:
        return respond(400, {"error": "address required (or provide addressText)"})

    try:
        final = None
        if isinstance(address_input, str) and (address_input.startswith('http') or 'maps.app.goo.gl' in address_input or 'goo.gl/maps' in address_input):
            try:
                final = resolve_redirect_url(address_input)
                print('DEBUG resolved final URL:', final)
            except Exception as e:
                print('DEBUG resolve failed:', e)
        url_to_use = final or address_input

        # 1) Try to parse coords found in URL (dir, place, marker, viewport)
        parsed = parse_latlng_from_url(url_to_use)
        print('DEBUG parsed coords from URL:', parsed)

        # 2) Extract place name or id
        name = extract_name_from_url(url_to_use)
        place_id = extract_place_id(url_to_use)
        print('DEBUG extracted name:', name, 'place_id:', place_id)

        # 3) If place_id available prefer Places Details
        if place_id and GEOCODE_KEY:
            pd = call_places_details(place_id)
            print('DEBUG places.details raw:', json.dumps(pd)[:1600] if pd else None)
            if pd and pd.get('status') == 'OK' and pd.get('result', {}).get('geometry'):
                loc = pd['result']['geometry']['location']
                return respond(200, {"lat": loc.get('lat'), "lng": loc.get('lng'), "source": 'places_details'})

        # 4) If name looks like a street address, prefer Geocoding
        if name and is_probable_street_address(name) and GEOCODE_KEY:
            gg = geocode_by_api(name)
            print('DEBUG geocode by name raw (probable address):', json.dumps(gg)[:1600] if gg else None)
            if gg and gg.get('status') == 'OK' and gg.get('results'):
                loc = gg['results'][0]['geometry']['location']
                return respond(200, {"lat": loc.get('lat'), "lng": loc.get('lng'), "source": 'geocode_name'})

        # 5) Try Places Text Search for malls/shops/establishments
        if name and GEOCODE_KEY:
            pts = call_places_textsearch(name)
            print('DEBUG places.textsearch raw:', json.dumps(pts)[:1600] if pts else None)
            if pts and pts.get('status') == 'OK' and pts.get('results'):
                loc = pts['results'][0]['geometry']['location']
                return respond(200, {"lat": loc.get('lat'), "lng": loc.get('lng'), "source": 'places_textsearch'})

        # 6) If parsed coords exist from URL, return them
        if parsed:
            return respond(200, {"lat": parsed['lat'], "lng": parsed['lng'], "source": 'url'})

        # 7) Final fallback: Geocoding API on the URL or address_text
        if GEOCODE_KEY:
            gg = geocode_by_api(url_to_use)
            print('DEBUG geocode.raw:', json.dumps(gg)[:1600] if gg else None)
            if gg and gg.get('status') == 'OK' and gg.get('results'):
                loc = gg['results'][0]['geometry']['location']
                return respond(200, {"lat": loc.get('lat'), "lng": loc.get('lng'), "source": 'geocode_api'})

        return respond(404, {"error": "no results"})
    except Exception as e:
        print('ERROR exception:', str(e))
        return respond(500, {"error": str(e)})

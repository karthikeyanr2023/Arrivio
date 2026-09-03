import json
import math
import os
import boto3
from decimal import Decimal


dynamodb = boto3.resource("dynamodb")
MERCHANT_TABLE_NAME = os.environ.get("MERCHANT_TABLE_NAME", "ArrivioMerchantProfiles")
merchant_table = dynamodb.Table(MERCHANT_TABLE_NAME)


CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}


def decimal_to_float(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {k: decimal_to_float(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decimal_to_float(v) for v in value]
    return value


def haversine_km(lat1, lng1, lat2, lng2):
    radius_km = 6371.0
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)

    a = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radius_km * c


def get_merchant_geocode(merchant):
    address = merchant.get("address") or {}
    geocode = merchant.get("geocode") or address.get("geocode") or {}

    if not geocode:
        return None, None

    try:
        lat = float(geocode.get("lat"))
        lng = float(geocode.get("lng"))
        return lat, lng
    except (TypeError, ValueError):
        return None, None


def response(status_code, message, data=None):
    body = {"message": message}
    if data is not None:
        body["data"] = data
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=str),
    }


def lambda_handler(event, context):
    if event.get("httpMethod") == "OPTIONS":
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ""}

    try:
        if event.get("body"):
            body = json.loads(event.get("body") or "{}")
        else:
            body = event.get("queryStringParameters") or {}
    except Exception:
        return response(400, "Invalid JSON body")

    lat = body.get("lat")
    lng = body.get("lng")

    if lat is None or lng is None:
        return response(400, "Missing required lat/lng values")

    try:
        destination_lat = float(lat)
        destination_lng = float(lng)
    except (TypeError, ValueError):
        return response(400, "lat and lng must be numeric")

    try:
        scan_result = merchant_table.scan()
        merchants = scan_result.get("Items", [])
    except Exception as exc:
        print("DynamoDB scan failed:", exc)
        return response(500, "Unable to load merchant profiles")

    results = []

    for merchant in merchants:
        merchant_name = (
            merchant.get("fullName")
            or merchant.get("name")
            or merchant.get("MerchantName")
            or "Merchant"
        )
        merchant_email = merchant.get("email") or merchant.get("MerchantEmail")
        merchant_lat, merchant_lng = get_merchant_geocode(merchant)

        if merchant_lat is None or merchant_lng is None:
            continue

        distance_km = haversine_km(destination_lat, destination_lng, merchant_lat, merchant_lng)

        results.append(
            {
                "merchantName": merchant_name,
                "merchantEmail": merchant_email,
                "distanceKm": round(distance_km, 2),
                "lat": merchant_lat,
                "lng": merchant_lng,
                "city": (merchant.get("address") or {}).get("city") or "",
                "country": merchant.get("country") or "",
            }
        )

    results.sort(key=lambda item: item["distanceKm"])

    return response(200, "Merchant distances calculated successfully", results)

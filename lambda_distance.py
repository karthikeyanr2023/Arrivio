import json
import math
import os
import boto3
from datetime import date, datetime
from decimal import Decimal
from boto3.dynamodb.conditions import Key


dynamodb = boto3.resource("dynamodb")
MERCHANT_TABLE_NAME = os.environ.get("MERCHANT_TABLE_NAME", "ArrivioMerchantProfiles")
merchant_table = dynamodb.Table(MERCHANT_TABLE_NAME)
DEALS_TABLE_NAME = os.environ.get("DEALS_TABLE_NAME", "merchant_deals")
COUPONS_TABLE_NAME = os.environ.get("COUPONS_TABLE_NAME", "merchant_coupons")
deals_table = dynamodb.Table(DEALS_TABLE_NAME)
coupons_table = dynamodb.Table(COUPONS_TABLE_NAME)
lambda_client = boto3.client("lambda")
RANKING_LAMBDA_NAME = os.environ.get("RANKING_LAMBDA_NAME", "ResultsbsdonUserBehavior")
OCCASION_RANKING_LAMBDA_NAME = os.environ.get("OCCASION_RANKING_LAMBDA_NAME", "OccasionRanking")


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


def response(status_code, message, data=None, ranking_debug=None):
    body = {"message": message}
    if data is not None:
        body["data"] = data
    if ranking_debug is not None:
        body["rankingDebug"] = ranking_debug
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=str),
    }


def offer_is_active(offer):
    end_date = (
        offer.get("to")
        or offer.get("validTo")
        or offer.get("endDate")
        or offer.get("dateTo")
        or offer.get("expirationDate")
        or offer.get("expiry")
        or offer.get("valid_until")
    )
    if not end_date:
        return True

    try:
        return date.fromisoformat(str(end_date)[:10]) >= datetime.utcnow().date()
    except ValueError:
        return True


def merchant_id_candidates(merchant):
    merchant_id = str(
        merchant.get("merchantId")
        or merchant.get("email")
        or merchant.get("MerchantEmail")
        or ""
    ).strip().lower()
    if not merchant_id:
        return []

    candidates = {merchant_id}
    if merchant_id.endswith("@gmail.com"):
        candidates.add(merchant_id[: -len("@gmail.com")])
    elif "@" not in merchant_id:
        candidates.add(f"{merchant_id}@gmail.com")
    return sorted(candidates)


def fetch_merchant_offers(table, merchant, id_field):
    offers = []
    seen_ids = set()

    for merchant_id in merchant_id_candidates(merchant):
        query_args = {
            "IndexName": "merchantId-index",
            "KeyConditionExpression": Key("merchantId").eq(merchant_id),
        }
        while True:
            result = table.query(**query_args)
            for offer in result.get("Items", []):
                offer_id = offer.get(id_field) or offer.get("id")
                if offer_id and offer_id in seen_ids:
                    continue
                if offer_id:
                    seen_ids.add(offer_id)
                if offer_is_active(offer):
                    offers.append(offer)

            last_key = result.get("LastEvaluatedKey")
            if not last_key:
                break
            query_args["ExclusiveStartKey"] = last_key

    return offers


def fetch_merchant_offers_for_results(results):
    for merchant in results:
        merchant["deals"] = fetch_merchant_offers(deals_table, merchant, "dealId")
        merchant["coupons"] = fetch_merchant_offers(coupons_table, merchant, "couponId")
    return results


def rank_merchants(results, user_id):
    if not results:
        return results, False, {"status": "RANKING SKIPPED - no merchants"}
    if not user_id:
        print("Personalization skipped: request did not include userId")
        return results, False, {"status": "RANKING SKIPPED - request had no userId"}
    if not RANKING_LAMBDA_NAME:
        print("Personalization skipped: RANKING_LAMBDA_NAME is not configured")
        return results, False, {"status": "RANKING SKIPPED - RANKING_LAMBDA_NAME not configured"}

    payload_to_send = {
        "userId": user_id,
        "merchants": decimal_to_float(
            [
                {
                    "merchantId": merchant["merchantId"],
                    "merchantName": merchant["merchantName"],
                    "category": merchant["category"],
                    "distanceMiles": merchant["distanceMiles"],
                    "deals": merchant["deals"],
                    "coupons": merchant["coupons"],
                }
                for merchant in results
            ]
        ),
    }

    print("STEP 1 - Invoking ResultsbsdonUserBehavior Lambda:", RANKING_LAMBDA_NAME)
    print("STEP 1 - Personalization payload merchant count:", len(payload_to_send["merchants"]))
    print("STEP 1 - Personalization payload sample:", json.dumps(payload_to_send, default=str)[:2000])

    try:
        invocation = lambda_client.invoke(
            FunctionName=RANKING_LAMBDA_NAME,
            InvocationType="RequestResponse",
            Payload=json.dumps(payload_to_send).encode("utf-8"),
        )
        print("STEP 1 - ResultsbsdonUserBehavior invoke status:", invocation.get("StatusCode"))
        print("STEP 1 - ResultsbsdonUserBehavior function error:", invocation.get("FunctionError"))

        if invocation.get("FunctionError"):
            raise RuntimeError("Ranking Lambda reported an execution error")

        payload = json.loads(invocation["Payload"].read() or b"{}")
        body = payload.get("body", payload)
        if isinstance(body, str):
            body = json.loads(body)

        print("STEP 1 - ResultsbsdonUserBehavior raw response:", json.dumps(body, default=str)[:4000])

        ranked_ids = body.get("rankedMerchantIds")
        if body.get("rankingApplied") is not True or not isinstance(ranked_ids, list):
            print("Personalization unavailable:", body.get("message", "ranking was not applied"))
            return results, False, body.get("debug") or {"status": body.get("message", "ranking was not applied")}

        by_id = {item["merchantId"]: item for item in results}
        ordered = [by_id[merchant_id] for merchant_id in ranked_ids if merchant_id in by_id]
        ordered_ids = {item["merchantId"] for item in ordered}
        ordered.extend(item for item in results if item["merchantId"] not in ordered_ids)
        print("STEP 1 - ResultsbsdonUserBehavior final ordered IDs:", [item["merchantId"] for item in ordered])
        return ordered, True, body.get("debug")
    except Exception as exc:
        print("Merchant ranking failed; keeping distance order:", exc)
        return results, False, {"status": "RANKING FAILED - distance order kept", "error": str(exc)}


def rank_merchants_by_occasion(results, user_id, occasion):
    occasion_value = str(occasion or "").strip()
    if not results:
        return results, False, {"status": "OCCASION RANKING SKIPPED - no merchants"}
    if not occasion_value:
        return results, False, {"status": "OCCASION RANKING SKIPPED - no occasion selected"}
    if not OCCASION_RANKING_LAMBDA_NAME:
        return results, False, {"status": "OCCASION RANKING SKIPPED - lambda not configured"}

    payload_to_send = {
        "userId": user_id,
        "occasion": occasion_value,
        "merchants": decimal_to_float(
            [
                {
                    "merchantId": merchant["merchantId"],
                    "merchantName": merchant["merchantName"],
                    "category": merchant["category"],
                    "distanceMiles": merchant["distanceMiles"],
                    "deals": merchant.get("deals", []),
                    "coupons": merchant.get("coupons", []),
                }
                for merchant in results
            ]
        ),
    }

    print("STEP 2 - Invoking OccasionRanking Lambda:", OCCASION_RANKING_LAMBDA_NAME)
    print("STEP 2 - Occasion value:", occasion_value)
    print("STEP 2 - Occasion payload merchant count:", len(payload_to_send["merchants"]))
    print("STEP 2 - Occasion payload sample:", json.dumps(payload_to_send, default=str)[:2000])

    try:
        invocation = lambda_client.invoke(
            FunctionName=OCCASION_RANKING_LAMBDA_NAME,
            InvocationType="RequestResponse",
            Payload=json.dumps(payload_to_send).encode("utf-8"),
        )
        print("STEP 2 - OccasionRanking invoke status:", invocation.get("StatusCode"))
        print("STEP 2 - OccasionRanking function error:", invocation.get("FunctionError"))

        if invocation.get("FunctionError"):
            raise RuntimeError("Occasion ranking Lambda reported an execution error")

        payload = json.loads(invocation["Payload"].read() or b"{}")
        body = payload.get("body", payload)
        if isinstance(body, str):
            body = json.loads(body)

        print("STEP 2 - OccasionRanking raw response:", json.dumps(body, default=str)[:4000])

        ranked_ids = body.get("rankedMerchantIds")
        if body.get("rankingApplied") is not True or not isinstance(ranked_ids, list):
            print("Occasion ranking unavailable:", body.get("message", "occasion ranking was not applied"))
            return results, False, body.get("debug") or {"status": body.get("message", "occasion ranking was not applied")}

        by_id = {item["merchantId"]: item for item in results}
        ordered = [by_id[merchant_id] for merchant_id in ranked_ids if merchant_id in by_id]
        ordered_ids = {item["merchantId"] for item in ordered}
        ordered.extend(item for item in results if item["merchantId"] not in ordered_ids)
        print("STEP 2 - OccasionRanking final ordered IDs:", [item["merchantId"] for item in ordered])
        return ordered, True, body.get("debug")
    except Exception as exc:
        print("Occasion ranking failed; keeping current order:", exc)
        return results, False, {"status": "OCCASION RANKING FAILED - current order kept", "error": str(exc)}


def handle_request(event, context):
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
    user_id = str(body.get("userId") or "").strip()
    occasion = str(body.get("occasion") or "").strip()
    try:
        radius_miles = float(body.get("radiusMiles", 25))
    except (TypeError, ValueError):
        return response(400, "radiusMiles must be numeric")
    if not 0 < radius_miles <= 50:
        return response(400, "radiusMiles must be greater than 0 and no more than 50")

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

    last_evaluated_key = scan_result.get("LastEvaluatedKey")
    while last_evaluated_key:
        try:
            scan_result = merchant_table.scan(ExclusiveStartKey=last_evaluated_key)
        except Exception as exc:
            print("DynamoDB merchant scan pagination failed:", exc)
            return response(500, "Unable to load merchant profiles")
        merchants.extend(scan_result.get("Items", []))
        last_evaluated_key = scan_result.get("LastEvaluatedKey")

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
        distance_miles = distance_km * 0.621371
        if distance_miles > radius_miles:
            continue

        merchant_id = (
            merchant.get("merchantId")
            or merchant_email
            or merchant.get("MerchantEmail")
            or merchant_name.lower().replace(" ", "-")
        )

        results.append(
            {
                "merchantId": str(merchant_id).strip().lower(),
                "merchantName": merchant_name,
                "merchantEmail": merchant_email,
                "address": merchant.get("address") or {},
                "phone": (merchant.get("businessDetails") or {}).get("phone")
                or (merchant.get("businessDetails") or {}).get("contactNumber")
                or "",
                "category": (merchant.get("businessDetails") or {}).get("type") or "General",
                "distanceKm": round(distance_km, 2),
                "distanceMiles": round(distance_miles, 2),
                "lat": merchant_lat,
                "lng": merchant_lng,
                "city": (merchant.get("address") or {}).get("city") or "",
                "country": merchant.get("country") or "",
            }
        )

    results.sort(key=lambda item: item["distanceMiles"])
    results = results[:50]

    try:
        results = fetch_merchant_offers_for_results(results)
    except Exception as exc:
        print("Unable to load merchant offers:", exc)
        for merchant in results:
            merchant.pop("deals", None)
            merchant.pop("coupons", None)
        return response(
            200,
            "Nearby merchants loaded in distance order",
            results,
            {"status": "RANKING SKIPPED - offers could not be loaded", "error": str(exc)},
        )

    print("STEP 0 - Request summary: userId=", user_id, "occasion=", occasion, "resultsCount=", len(results))
    results, ranking_applied, ranking_debug = rank_merchants(results, user_id)
    print("STEP 0 - After personalization: ranking_applied=", ranking_applied, "resultCount=", len(results))
    results, occasion_applied, occasion_debug = rank_merchants_by_occasion(results, user_id, occasion)
    print("STEP 0 - After occasion ranking: occasion_applied=", occasion_applied, "resultCount=", len(results))

    debug_info = ranking_debug or {"status": "RANKING SKIPPED"}
    if occasion_applied:
        debug_info = {**debug_info, "occasionRanking": occasion_debug}
    elif occasion:
        debug_info = {**debug_info, "occasionRanking": occasion_debug}

    message = "Nearby merchants loaded in distance order"
    if ranking_applied:
        message = "Personalized nearby merchants loaded"
    if occasion_applied:
        message = "Personalized and occasion-ranked nearby merchants loaded"
    return response(200, message, results, debug_info)


def lambda_handler(event, context):
    try:
        return handle_request(event, context)
    except Exception as exc:
        print("Unhandled error:", repr(exc))
        return response(500, "Unexpected error: " + str(exc))

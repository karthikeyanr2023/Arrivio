import os
import json
import boto3
from datetime import datetime


dynamodb = boto3.resource("dynamodb")
# existing user table (keeps backwards compatibility)
USER_TABLE_NAME = os.environ.get("TABLE_NAME", "ArrivioNewUserReg")
user_table = dynamodb.Table(USER_TABLE_NAME)
# new merchant table
MERCHANT_TABLE_NAME = os.environ.get("MERCHANT_TABLE_NAME", "ArrivioMerchantProfiles")
merchant_table = dynamodb.Table(MERCHANT_TABLE_NAME)

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}


def lambda_handler(event, context):
    method = (
        event.get("httpMethod")
        or (event.get("requestContext") or {}).get("http", {}).get("method")
        or ""
    ).upper()

    path = (
        event.get("path")
        or (event.get("requestContext") or {}).get("http", {}).get("path")
        or ""
    )
    path = path.lower()

    if method == "OPTIONS":
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ""}

    if method == "GET":
        if path.endswith("/profiles"):
            return list_profiles(event)
        return get_profile(event)

    if method == "POST":
        return save_profile(event)

    return response(405, "Method not allowed")


def list_profiles(event):
    params = event.get("queryStringParameters") or {}
    profile_type = (params.get("type") or params.get("profileType") or "user").strip().lower()
    table = merchant_table if profile_type == "merchant" else user_table

    try:
        result = table.scan()
        items = result.get("Items", [])
        return response(200, f"{profile_type.capitalize()} profiles loaded", items)
    except Exception as exc:
        print("DynamoDB scan failed:", exc)
        return response(500, "Unable to load profiles")


def get_profile(event):
    params = event.get("queryStringParameters") or {}
    email = (params.get("email") or "").strip().lower()
    profile_type = (params.get("type") or params.get("profileType") or "user").strip().lower()
    if not email:
        return response(400, "Missing email query parameter")

    try:
        if profile_type == 'merchant':
            result = merchant_table.get_item(Key={"MerchantEmail": email})
        else:
            result = user_table.get_item(Key={"Userprofile": email})
        item = result.get("Item")
        if not item:
            return response(404, "Profile not found")
        return response(200, "Profile loaded", item)
    except Exception as exc:
        print("DynamoDB get failed:", exc)
        return response(500, "Unable to load profile")


def save_profile(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, "Invalid JSON body")

    # determine profile type: 'user' or 'merchant'
    profile_type = (body.get('profileType') or 'user').strip().lower()

    if profile_type == 'merchant':
        # merchant-specific validation
        full_name = (body.get("fullName") or "").strip()
        email = (body.get("email") or "").strip().lower()
        country = (body.get("country") or "").strip()
        address = body.get("address") or {}
        business = body.get('businessDetails') or {}

        if not full_name:
            return response(400, "Please provide a full name for merchant.")
        if not email or not email.endswith("@gmail.com"):
            return response(400, "Please provide a valid Gmail address for merchant.")
        if not country:
            return response(400, "Please provide a country for merchant.")

        if not isinstance(address, dict):
            address = {}
        street = (address.get("street") or "").strip()
        city = (address.get("city") or "").strip()
        zipcode = (address.get("zipcode") or "").strip()
        if not street or not city or not zipcode:
            return response(400, "Please provide complete address for merchant.")

        # business details validation
        title = (business.get('title') or '').strip()
        btype = (business.get('type') or '').strip()
        option = (business.get('option') or '').strip()
        if not title or not btype or not option:
            return response(400, "Please provide business title, type and option for merchant.")

        item = {
            "MerchantEmail": email,
            "fullName": full_name,
            "email": email,
            "country": country,
            "address": {
                "street": street,
                "city": city,
                "zipcode": zipcode,
            },
            "businessDetails": business,
            "createdAt": datetime.utcnow().isoformat() + "Z",
        }

        try:
            merchant_table.put_item(Item=item)
            return response(200, "Merchant profile saved successfully.", item)
        except Exception as exc:
            print("DynamoDB put failed (merchant):", exc)
            return response(500, "Failed to save merchant profile")

    # fallback: user profile (existing behavior)
    full_name = (body.get("fullName") or "").strip()
    email = (body.get("email") or "").strip().lower()
    country = (body.get("country") or "").strip()
    address = body.get("address") or {}
    preferences = body.get("preferences") or []
    if not isinstance(preferences, list):
        preferences = [preferences]

    if not full_name:
        return response(400, "Please provide a full name.")
    if not email or not email.endswith("@gmail.com"):
        return response(400, "Please provide a valid Gmail address.")
    if not country:
        return response(400, "Please provide a country.")
    if not preferences:
        return response(400, "Please select at least one preference.")

    if not isinstance(address, dict):
        address = {}

    street = (address.get("street") or "").strip()
    city = (address.get("city") or "").strip()
    zipcode = (address.get("zipcode") or "").strip()

    if not street:
        return response(400, "Please provide your street address.")
    if not city:
        return response(400, "Please provide your city.")
    if not zipcode:
        return response(400, "Please provide your zip code.")

    item = {
        "Userprofile": email,
        "fullName": full_name,
        "email": email,
        "country": country,
        "address": {
            "street": street,
            "city": city,
            "zipcode": zipcode,
        },
        "preferences": preferences,
        "createdAt": datetime.utcnow().isoformat() + "Z",
    }

    try:
        user_table.put_item(Item=item)
        return response(200, "Profile saved successfully.", item)
    except Exception as exc:
        print("DynamoDB put failed:", exc)
        return response(500, "Failed to save profile")


def response(status_code, message, data=None):
    body = {"message": message}
    if data is not None:
        body["data"] = data
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body),
    }

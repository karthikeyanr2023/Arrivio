import os
import json
import boto3
from datetime import datetime


dynamodb = boto3.resource("dynamodb")
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

    if method == "OPTIONS":
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ""}

    if method == "GET":
        return get_merchant(event)

    if method == "POST":
        return save_merchant(event)

    return response(405, "Method not allowed")


def get_merchant(event):
    params = event.get("queryStringParameters") or {}
    email = (params.get("email") or "").strip().lower()
    if not email:
        return response(400, "Missing email query parameter")
    try:
        result = merchant_table.get_item(Key={"MerchantEmail": email})
        item = result.get("Item")
        if not item:
            return response(404, "Merchant profile not found")
        return response(200, "Merchant loaded", item)
    except Exception as exc:
        print("DynamoDB get failed (merchant):", exc)
        return response(500, "Unable to load merchant profile")


def save_merchant(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, "Invalid JSON body")

    # basic validation for merchant profile
    full_name = (body.get("fullName") or "").strip()
    email = (body.get("email") or "").strip().lower()
    country = (body.get("country") or "").strip()
    address = body.get("address") or {}
    business = body.get("businessDetails") or {}

    if not full_name:
        return response(400, "Please provide a full name for merchant.")
    if not email:
        return response(400, "Please provide an email for merchant.")
    if not country:
        return response(400, "Please provide a country for merchant.")

    if not isinstance(address, dict):
        address = {}
    street = (address.get("street") or "").strip()
    city = (address.get("city") or "").strip()
    zipcode = (address.get("zipcode") or "").strip()
    if not street or not city or not zipcode:
        return response(400, "Please provide complete address for merchant.")

    title = (business.get("title") or "").strip()
    btype = (business.get("type") or "").strip()
    option = (business.get("option") or "").strip()
    # allow license and tax id to be optional, but include if present

    if not title or not btype or not option:
        return response(400, "Please provide business title, type and option for merchant.")

    item = {
        "MerchantEmail": email,
        "fullName": full_name,
        "email": email,
        "country": country,
        "address": {"street": street, "city": city, "zipcode": zipcode},
        "businessDetails": business,
        "createdAt": datetime.utcnow().isoformat() + "Z",
    }

    try:
        merchant_table.put_item(Item=item)
        return response(200, "Merchant profile saved successfully.", item)
    except Exception as exc:
        print("DynamoDB put failed (merchant):", exc)
        return response(500, "Failed to save merchant profile")


def response(status_code, message, data=None):
    body = {"message": message}
    if data is not None:
        body["data"] = data
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}

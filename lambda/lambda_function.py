import base64
import json
import os
import time

import boto3

s3 = boto3.client("s3")

# bucket aur prefix env se aate hain, code mein hardcode nahi
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

ROUTES = {
    "/": ("index.html", "text/html"),
    "/index.html": ("index.html", "text/html"),
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}

NOT_FOUND = "<!DOCTYPE html><html><head><title>404</title></head><body><h1>404 - Not Found</h1><p>Nothing here, go back to <a href=\"/\">the CV</a>.</p></body></html>"


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")

    if path not in ROUTES:
        resp = {"statusCode": 404, "headers": {"Content-Type": "text/html"}, "body": NOT_FOUND}
    else:
        key, ctype = ROUTES[path]
        try:
            data = s3.get_object(Bucket=BUCKET, Key=PREFIX + key)["Body"].read()
            if ctype == "application/pdf":
                # pdf binary hai is liye base64 karke bhejna parta hai
                resp = {
                    "statusCode": 200,
                    "headers": {"Content-Type": ctype},
                    "body": base64.b64encode(data).decode(),
                    "isBase64Encoded": True,
                }
            else:
                body = data.decode("utf-8")
                headers = {"Content-Type": ctype}
                if ctype == "text/html":
                    body = body.replace("{{HOSTED_ON}}", "Lambda " + context.function_name)
                    headers["Cache-Control"] = "max-age=60"
                resp = {"statusCode": 200, "headers": headers, "body": body}
        except Exception as e:
            print(json.dumps({"error": str(e)}))
            resp = {"statusCode": 500, "headers": {"Content-Type": "text/html"}, "body": "<h1>500 - could not read the CV</h1>"}

    print(json.dumps({
        "fn": context.function_name,
        "path": path,
        "status": resp["statusCode"],
        "ms": round((time.time() - start) * 1000, 1),
    }))
    return resp

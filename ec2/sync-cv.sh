#!/bin/bash
# copies site/ from the bucket into the web root and fills in the footer
# runs once from user data and then every 5 min from the systemd timer

BUCKET="cv-23l-3024"
PREFIX="site/"
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"

TMP=$(mktemp -d)

if aws s3 sync "s3://$BUCKET/$PREFIX" "$TMP/" --region ap-southeast-2 --only-show-errors; then
    # IMDSv2 wala token pehle lena parta hai
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/instance-id")

    sed -i "s/{{HOSTED_ON}}/EC2 $ID/" "$TMP/index.html"
    cp "$TMP"/* "$WEBROOT/"
    chmod 644 "$WEBROOT"/*
    echo "$(date '+%Y-%m-%d %H:%M:%S') sync ok ($ID)" >> "$LOG"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') sync FAILED" >> "$LOG"
fi

rm -rf "$TMP"

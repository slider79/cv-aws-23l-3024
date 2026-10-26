#!/bin/bash
# runs once when the instance first boots (Amazon Linux 2023)
# no keys anywhere, the aws cli uses the instance role

dnf install -y httpd
systemctl enable --now httpd

# sync script (same as ec2/sync-cv.sh in the repo)
cat > /usr/local/bin/sync-cv.sh <<'EOF'
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
EOF
chmod +x /usr/local/bin/sync-cv.sh

# AL2023 mein cron nahi hota, is liye systemd timer
cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV from S3 into the web root

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Run cv-sync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cv-sync.timer

# first sync right now
/usr/local/bin/sync-cv.sh

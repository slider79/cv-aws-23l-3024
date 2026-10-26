#!/bin/bash
# usage: ./collect-evidence.sh <bucket> <ec2-address> <lambda-address>
# saari evidence evidence.txt mein jati hai

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <bucket-name> <ec2-address> <lambda-address>"
    exit 1
fi

# git bash on windows turns /aws/lambda/... into a C:/ path, this stops that (does nothing on linux)
export MSYS2_ARG_CONV_EXCL="/aws"

BUCKET="$1"
EC2="${2%/}"
LAMBDA="${3%/}"
OUT="evidence.txt"
REGION="ap-southeast-2"
EC2_ROLE="cv-ec2-role-23l-3024"
LAMBDA_ROLE="cv-lambda-role-23l-3024"
INSTANCE_NAME="cv-ec2-23l-3024"
FUNC="cv-func-23l-3024"

# http:// lagao agar address ke sath scheme nahi di
case "$EC2" in http*) ;; *) EC2="http://$EC2" ;; esac
case "$LAMBDA" in http*) ;; *) LAMBDA="https://$LAMBDA" ;; esac

: > "$OUT"

section() {
    echo "" >> "$OUT"
    echo "== $1 ==" >> "$OUT"
}

# command chalao, fail ho to note kar ke aage chalo
run() {
    if ! "$@" >> "$OUT" 2>&1; then
        echo "FAILED: $*" >> "$OUT"
    fi
}

section caller
run aws sts get-caller-identity --output json

section public-access
run aws s3api get-public-access-block --bucket "$BUCKET" --output json

section versioning
run aws s3api get-bucket-versioning --bucket "$BUCKET" --output json

section objects
run aws s3 ls "s3://$BUCKET/site/" --recursive

section ec2-policy
run aws iam list-role-policies --role-name "$EC2_ROLE" --output json
for p in $(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
    run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$p" --output json
done
run aws iam list-attached-role-policies --role-name "$EC2_ROLE" --output json

section lambda-policy
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" --output json
for p in $(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
    run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$p" --output json
done

SG=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)

section security-group
run aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG" \
    --query 'SecurityGroups[0].{GroupId:GroupId,GroupName:GroupName,Inbound:IpPermissions}' --output json

section instance
run aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,HttpTokens:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn}' \
    --output json

section endpoints
for url in "$EC2/" "$EC2/style.css" "$EC2/cv.pdf" "$LAMBDA/" "$LAMBDA/style.css" "$LAMBDA/cv.pdf" "$LAMBDA/anything" \
           "https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"; do
    if RES=$(curl -s -o /dev/null --max-time 15 -w "%{http_code} %{content_type}" "$url" 2>&1); then
        echo "$url -> $RES" >> "$OUT"
    else
        echo "FAILED: curl $url ($RES)" >> "$OUT"
    fi
done

section lambda-logs
# sirf aakhri 15 lines, poora log nahi chahiye
if LOGS=$(aws logs tail "/aws/lambda/$FUNC" --region "$REGION" --since 2h --format short 2>&1); then
    echo "$LOGS" | tail -n 15 >> "$OUT"
else
    echo "$LOGS" >> "$OUT"
    echo "FAILED: aws logs tail" >> "$OUT"
fi

section log-retention
run aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "/aws/lambda/$FUNC" \
    --query 'logGroups[].{name:logGroupName,retentionInDays:retentionInDays}' --output json

echo "DONE"

# CV on AWS - 23L-3024

Muhammad Shuja Jamal, 23L-3024

My CV served two ways from one private S3 bucket: once by Apache on an EC2 instance and once by a Lambda function URL.

| | Address |
|---|---|
| EC2 | http://54.79.100.229/ |
| Lambda | https://cycrddt5mfv4d7ylbagf3an3ba0pmcih.lambda-url.ap-southeast-2.on.aws/ |
| Bucket | cv-23l-3024 (private) |

**Region:** everything is in **ap-southeast-2 (Sydney)**, not the class region. My AWS account was made with the new GitHub sign up and it is a project that AWS only lets me use in Sydney, every other region gives an explicit deny from an organization policy for EC2, Lambda and S3.

## Diagram

```
                         Internet (anyone)
                     /                      \
         http://<ec2 ip>/               https://<id>.lambda-url.ap-southeast-2.on.aws/
                   |                                   |
   +---------------v---------------+     +-------------v--------------+
   | EC2 cv-ec2-23l-3024 (t3.micro)|     | Lambda cv-func-23l-3024    |
   | Apache serves /var/www/html   |     | python, function URL NONE  |
   | systemd timer every 5 min     |     | reads BUCKET + PREFIX env  |
   | runs sync-cv.sh               |     | logs JSON to CloudWatch    |
   | role: cv-ec2-role-23l-3024    |     | role: cv-lambda-role-...   |
   +---------------+---------------+     +-------------+--------------+
                   | s3:ListBucket (site/) + GetObject | s3:GetObject
                   v                                   v
           +-----------------------------------------------+
           | S3 bucket cv-23l-3024 (Block Public Access on, |
           | versioning on)  site/index.html  style.css  cv.pdf
           +-----------------------------------------------+
                   ^
   direct S3 link from a browser  ->  403 Access Denied
```

On the EC2 path the browser hits Apache on the instance, which only serves local files that the timer copied from the bucket every 5 minutes using the instance role, with the footer already filled in with EC2 and the instance id. On the Lambda path the browser hits the function URL, the function reads the file from the bucket with its own role on every request, puts Lambda and the function name in the footer and returns it.

## Repo layout

```
collect-evidence.sh   evidence script (bucket, ec2 address, lambda address)
evidence.txt          output of my own run
site/                 index.html, style.css, cv.pdf (what goes in s3 under site/)
ec2/                  user-data.sh, sync-cv.sh
lambda/               lambda_function.py
iam/                  trust + permission json of both roles
```

## Access denied from the instance

Run from a shell on the instance (EC2 Instance Connect):

```
$ aws s3 rm s3://cv-23l-3024/site/index.html
delete failed: s3://cv-23l-3024/site/index.html An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::743702012575:assumed-role/cv-ec2-role-23l-3024/i-07544841572bdb436 is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3024/site/index.html" because no identity-based policy allows the s3:DeleteObject action
$ echo hacked > /tmp/x.html && aws s3 cp /tmp/x.html s3://cv-23l-3024/site/index.html
upload failed: ../../tmp/x.html to s3://cv-23l-3024/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::743702012575:assumed-role/cv-ec2-role-23l-3024/i-07544841572bdb436 is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3024/site/index.html" because no identity-based policy allows the s3:PutObject action
```

## Last 10 lines of /var/log/cv-sync.log

```
2026-10-26 15:54:58 sync ok (i-07544841572bdb436)
2026-10-26 15:56:26 sync ok (i-07544841572bdb436)
2026-10-26 16:01:26 sync ok (i-07544841572bdb436)
2026-10-26 16:06:26 sync ok (i-07544841572bdb436)
```

## Answers

**1. Why roles instead of access keys? What if the keys were in the user data?**
A role gives the instance or the function temporary credentials that AWS rotates by itself, so there is no long lived secret to store or leak. User data is not secret at all, anyone with describe access on the instance can read it and it also sits on the instance at /var/lib/cloud. If keys were there and they got copied into a public repo or a screenshot, whoever finds them can use them from anywhere until someone deactivates them. With roles there is nothing written down to leak, and even the temporary credentials expire in a few hours.

**2. Someone pastes the S3 address of index.html into a browser. What do they see?**
They get a 403 Access Denied XML error, not the page. The bucket has all four Block Public Access settings on and no bucket policy or ACL for everyone, so an anonymous request has nothing that allows it. Only the two roles can read the objects.

**3. The permission on the function URL.**
When the auth type is NONE, the function gets a resource based policy that lets principal "*" call lambda:InvokeFunctionUrl, with a condition that the URL auth type is NONE, plus a second statement that allows lambda:InvokeFunction only when the call comes through the function URL. So anyone on the internet can trigger the function, but only through that URL and only to run my code. That is fine because the function decides what to return, it only ever reads three fixed keys and gives 404 for everything else, and it can not list or change anything. Making the bucket public would expose everything in it directly with no code in between, so I keep the bucket private and let the function be the only door.

**4. Cost when nobody visits, and at 100x traffic.**
EC2 costs money every hour it is running (plus its disk and public IPv4) even if nobody opens the site, it is just inside the free tier for now. Lambda costs nothing when idle, I only pay per request and per ms, and S3 is a few cents for storage in both cases. If traffic grows 100 times, the single t3.micro would get slow or fall over since there is no load balancer or auto scaling, I would have to scale it myself. Lambda just runs more copies in parallel automatically, the bill grows with the requests but the site keeps working.

**5. You delete the EC2 instance. What do you lose and what do you keep?**
I lose the instance itself, its root disk with Apache, the synced copy of the site, the systemd timer and /var/log/cv-sync.log, and the public IP (a new instance gets a different one). I keep the bucket with all files and versions, both IAM roles and the instance profile, the security group, the Lambda site, and the scripts in this repo. Launching a new instance with the same user data brings the EC2 site back by itself within a few minutes, since all the real content is in S3.

## Sources

The policies, user data and Lambda code were written using the official AWS documentation: S3 Block Public Access, IAM policy condition keys for s3:prefix, IMDSv2 token requests, systemd timers on Amazon Linux 2023, and the Lambda function URL docs for the response format and base64 binary bodies.

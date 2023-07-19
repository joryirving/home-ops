resource "minio_s3_bucket" "bucket" {
  bucket = var.bucket_name
  acl    = "private"
}

resource "minio_iam_user" "user" {
  name   = var.user_name
  secret = var.user_secret
}

resource "minio_iam_policy" "policy" {
  name   = "${var.bucket_name}-policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::${minio_s3_bucket.bucket.bucket}",
                "arn:aws:s3:::${minio_s3_bucket.bucket.bucket}/*"
            ],
            "Sid": ""
        }
    ]
}
EOF
}

resource "minio_iam_user_policy_attachment" "attachment" {
  user_name   = minio_iam_user.user.id
  policy_name = minio_iam_policy.policy.id
}

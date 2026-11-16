resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true # allows destroy even if the bucket has files
}

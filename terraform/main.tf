resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true # allows destroy even if the bucket has files
}


# ONE block → MANY buckets (one per name in var.bucket_names)
resource "aws_s3_bucket" "many" {
  for_each      = toset(var.bucket_names) # loop over every name in the list
  bucket        = each.value              # the current name in the loop
  force_destroy = true                    # allows destroy even if the bucket has files
}



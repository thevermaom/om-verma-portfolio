terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Store the state file in S3 (bucket created by hand) instead of on my laptop
  backend "s3" {
    bucket       = "omverma-tfstate"          # the bucket I created manually
    key          = "resume/terraform.tfstate" # folder/file name INSIDE the bucket
    region       = "ap-south-1"               # Mumbai
    encrypt      = true                       # store the file encrypted
    use_lockfile = true                       # lock: stops two applies running at once
  }
}

provider "aws" {
  region = var.region
}

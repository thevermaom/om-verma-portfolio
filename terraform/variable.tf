variable "region" {
  default = "ap-south-1" # Mumbai
}

variable "bucket_name" {
  default = "krishna1om2yash3som4" # must be globally unique and lowercase
}

# The address range for the whole VPC (65,536 addresses)
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

# A smaller range for the public subnet (256 addresses)
variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}

# A smaller range for the private subnet (256 addresses)
variable "private_subnet_cidr" {
  default = "10.0.2.0/24"
}

# Your home/office IP. No default, so Terraform will ask for it.
variable "my_ip" {
  description = "Your public IP address, e.g. 49.36.12.34"
  type        = string
}

# Where your public key file is
variable "public_key_path" {
  default = "~/.ssh/tf-ec2-key.pub"
}

# One bucket will be created for EACH name in this list
variable "bucket_names" {
  type = list(string)
  default = [
    "krishna1om2yash3som4-iron-man",
    "krishna1om2yash3som4-krish",
    "krishna1om2yash3som4-spider-man",
  ]
}



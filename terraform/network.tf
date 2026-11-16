resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr          # uses the variable from Step 4
  enable_dns_support   = true                  # lets the VPC use DNS
  enable_dns_hostnames = true                  # gives servers a name like ec2-1-2-3-4...amazonaws.com
  tags                 = { Name = "demo-vpc" } # the name you'll see in the AWS console
}


# Ask AWS which data centres (availability zones) exist in Mumbai
data "aws_availability_zones" "available" {
  state = "available"
}

# PUBLIC subnet: your Ubuntu server goes here
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id # put this room inside our VPC
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0] # first data centre
  map_public_ip_on_launch = true                                           # IMPORTANT: gives servers a public IP
  tags                    = { Name = "demo-public-subnet" }
}

# PRIVATE subnet: no internet access (for databases etc. later)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[1] # second data centre
  tags              = { Name = "demo-private-subnet" }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id # attach the door to our VPC
  tags   = { Name = "demo-igw" }
}

# PUBLIC route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                 # "0.0.0.0/0" means "anywhere on the internet"
    gateway_id = aws_internet_gateway.igw.id # ...go through the internet gateway
  }
  tags = { Name = "demo-public-rt" }
}

# Hang the public sign in the public room
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# PRIVATE route table: no internet route, so traffic stays inside the VPC
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "demo-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

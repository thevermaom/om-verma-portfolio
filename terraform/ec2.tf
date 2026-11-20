# 1) Find the latest official Ubuntu 24.04 image
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical, the official publisher of Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Look up the load balancer's security group (created by hand in the console)
# "data" = don't create it, just find it and give me its ID
data "aws_security_group" "alb" {
  name   = "demo-alb-sg"
  vpc_id = aws_vpc.main.id
}

# 2) Security group = firewall
resource "aws_security_group" "ec2_sg" {
  name   = "demo-ec2-sg"
  vpc_id = aws_vpc.main.id

  # Incoming traffic: allow SSH (port 22) from YOUR IP only
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"] # /32 means "exactly this one IP"
  }

  # Incoming traffic: web (port 80) ONLY from the load balancer
  # (opening a server's IP directly is blocked; visitors must use the load balancer)
  ingress {
    description     = "HTTP from the load balancer only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [data.aws_security_group.alb.id] # anyone wearing the ALB's badge
  }

  # Outgoing traffic: allow everything (so Ubuntu can download updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "demo-ec2-sg" }
}

# 3) Upload your PUBLIC key to AWS (the lock)
resource "aws_key_pair" "this" {
  key_name   = "tf-ec2-key"
  public_key = file(pathexpand(var.public_key_path)) # reads the .pub file from your PC
}

# 4) The Ubuntu servers: ONE block → TWO servers
resource "aws_instance" "web" {
  for_each = toset(["a"]) # only server "a" (the master copy for the AMI / auto scaling)

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id # both in the public subnet
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = aws_key_pair.this.key_name

  tags = { Name = "demo-web-${each.key}" } # demo-web-a, demo-web-b

  lifecycle {
    ignore_changes = [ami] # don't rebuild servers when Ubuntu releases a newer image
  }
}

# The old single server IS server "a". Keep it, don't recreate it.
moved {
  from = aws_instance.ubuntu
  to   = aws_instance.web["a"]
}

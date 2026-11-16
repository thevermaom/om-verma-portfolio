# 1) Find the latest official Ubuntu 24.04 image
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical, the official publisher of Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
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

  # Incoming traffic: allow web browsing (HTTP, port 80) from anywhere
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# 4) The Ubuntu server
resource "aws_instance" "ubuntu" {
  ami                    = data.aws_ami.ubuntu.id         # which OS image
  instance_type          = "t3.micro"                     # small size, free-tier eligible
  subnet_id              = aws_subnet.public.id           # put it in the PUBLIC room
  vpc_security_group_ids = [aws_security_group.ec2_sg.id] # attach the firewall
  key_name               = aws_key_pair.this.key_name     # attach the lock

  tags = { Name = "demo-ubuntu-ec2" }
}

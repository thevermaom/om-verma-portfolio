output "public_ip" {
  value = aws_instance.ubuntu.public_ip
}

output "website_url" {
  value = "http://${aws_instance.ubuntu.public_ip}"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/tf-ec2-key ubuntu@${aws_instance.ubuntu.public_ip}"
}

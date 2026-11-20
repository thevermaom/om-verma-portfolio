# Website address of each server
output "website_urls" {
  value = { for name, s in aws_instance.web : name => "http://${s.public_ip}" }
}

# SSH command for each server
output "ssh_commands" {
  value = { for name, s in aws_instance.web : name => "ssh -i ~/.ssh/tf-ec2-key ubuntu@${s.public_ip}" }
}

# 5) Put the portfolio website on the Ubuntu server
#
# How it works:
#   Terraform connects to the server over SSH (same as you did by hand),
#   copies the website files, installs nginx and points it at the files.
#
# "triggers_replace" = if any of these values change, redo the deployment.
# So: edit index.html / styles.css / script.js / nginx.conf, run
# `terraform apply`, and the new version goes live.

resource "terraform_data" "website" {
  triggers_replace = [
    aws_instance.ubuntu.id, # a new server needs the website again
    filemd5("${path.module}/index.html"),
    filemd5("${path.module}/styles.css"),
    filemd5("${path.module}/script.js"),
    filemd5("${path.module}/nginx.conf"),
  ]

  # How Terraform logs in to the server (your private key = the key)
  connection {
    type        = "ssh"
    host        = aws_instance.ubuntu.public_ip
    user        = "ubuntu"
    private_key = file(pathexpand("~/.ssh/tf-ec2-key"))
    timeout     = "5m"
  }

  # Step A: make a temporary folder on the server
  provisioner "remote-exec" {
    inline = ["mkdir -p /tmp/site"]
  }

  # Step B: copy the files from your laptop to the server
  provisioner "file" {
    source      = "${path.module}/index.html"
    destination = "/tmp/site/index.html"
  }

  provisioner "file" {
    source      = "${path.module}/styles.css"
    destination = "/tmp/site/styles.css"
  }

  provisioner "file" {
    source      = "${path.module}/script.js"
    destination = "/tmp/site/script.js"
  }

  provisioner "file" {
    source      = "${path.module}/nginx.conf"
    destination = "/tmp/site/nginx.conf"
  }

  # Step C: install nginx and move the files into place
  provisioner "remote-exec" {
    inline = [
      # wait until Ubuntu has finished its own first-boot setup
      "sudo cloud-init status --wait || true",

      # install the nginx web server (does nothing if already installed)
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx",

      # put the website where nginx.conf says it lives (root /usr/share/nginx/html)
      "sudo mkdir -p /usr/share/nginx/html",
      "sudo cp /tmp/site/index.html /tmp/site/styles.css /tmp/site/script.js /usr/share/nginx/html/",

      # use your nginx.conf instead of Ubuntu's default site
      "sudo cp /tmp/site/nginx.conf /etc/nginx/sites-available/portfolio",
      "sudo ln -sf /etc/nginx/sites-available/portfolio /etc/nginx/sites-enabled/portfolio",
      "sudo rm -f /etc/nginx/sites-enabled/default",

      # check the config, then (re)start nginx and make it start on every boot
      "sudo nginx -t",
      "sudo systemctl enable nginx",
      "sudo systemctl restart nginx",
    ]
  }
}

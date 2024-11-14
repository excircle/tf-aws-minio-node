
resource "aws_instance" "bastion_host" {
  for_each = var.bastion_host == true ? toset(["bastion"]) : toset([])

  ami                         = var.ec2_ami_image
  instance_type               = var.ec2_instance_type_bastion
  key_name                    = aws_key_pair.access_key.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg["bastion"].id]
  subnet_id                   = var.subnets.public[0]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name # Attach Profile To allow AWS CLI commands

  # Bootstrap commands
  user_data                   = <<EOF
#!/bin/bash
# Update and install packages
apt update -y   
apt install mlocate awscli tree jq tzdata chrony -y

# Set the timezone to America/Los_Angeles
echo "Setting timezone to America/Los_Angeles..."
sudo timedatectl set-timezone America/Los_Angeles

# Enable and start chrony service
echo "Enabling and starting chrony service..."
sudo systemctl enable chrony
sudo systemctl start chrony

# Verify the time and timezone settings
echo "Verifying the time and timezone settings..."
timedatectl

# Check the status of chrony service
echo "Checking the status of chrony service..."
sudo chronyc tracking

# Set hostname
hostnamectl set-hostname minio-bastion-host

# Setup mc binary
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin
EOF

  tags = merge(
    local.tag,
    {
      Name = format("%s Bastion Host", var.application_name)
      Purpose = format("%s Cluster Node", var.application_name)
    }
  )
}
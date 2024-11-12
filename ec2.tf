resource "aws_key_pair" "access_key" {
  key_name   = var.ec2_key_name
  public_key = var.sshkey # This key is provided via TF vars on the command line

  tags = merge(
    local.tag,
    {
      Name = format("%s-ec2-key", var.application_name)
      Purpose = format("%s EC2 Key Pair", var.application_name)
    }
  )
}

resource "random_integer" "subnet_selector" {
  for_each = toset(local.host_names)
  min      = 0
  max      = length(var.subnets) - 1
}

resource "aws_instance" "minio_host" {
  for_each = toset(local.host_names) # Creates an EC2 instance per string provided

  ami                         = var.ec2_ami_image
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.access_key.key_name
  associate_public_ip_address = var.make_private == false ? true : false
  vpc_security_group_ids      = [aws_security_group.main_vpc_sg.id]
  subnet_id = length(var.subnets.private) > 0 ? element([for v in var.subnets.private : v], random_integer.subnet_selector[each.key].result % length(var.subnets.private)) : element([for v in var.subnets.public : v], random_integer.subnet_selector[each.key].result % length(var.subnets.public))

  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name # Attach Profile To allow AWS CLI commands

  root_block_device {
    volume_size = var.ebs_root_volume_size
    volume_type = "gp3"
    delete_on_termination = true
  }

  # MinIO EBS volume
  dynamic "ebs_block_device" {
    for_each = toset(slice(local.disks, 0, var.num_disks))
    content {
      device_name = "/dev/xvd${ebs_block_device.value}"
      volume_size = var.ebs_storage_volume_size                                       # Set the size as needed
      delete_on_termination = true
    }
  }

  # User data script to bootstrap MinIO
  user_data = base64encode(templatefile("${path.module}/setup.sh", {
        hosts               = join(" ", local.host_names)
        host_count          = length(local.host_names)
        disk_count          = var.num_disks
        node_name           = "${each.key}"
        package_manager     = var.package_manager
        system_user         = var.system_user
        minio_user          = var.minio_user
  } ))

  tags = merge(
    local.tag,
    {
      Name = "${each.key}"
      Purpose = format("%s Cluster Node", var.application_name)
    }
  )
}

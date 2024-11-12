#!/bin/bash

# Global Variables
package_manager=${package_manager}
system_user=${system_user}
node_name=${node_name}
hosts=${hosts}

install_custom_dependencies() {
    # DEBIAN/APT BASED
    if [[ $1 == "apt" ]]; then
        sudo apt update
        sudo snap install yq
        sudo apt install -y chrony xfsprogs tree tzdata awscli curl wget vim net-tools jq unzip mlocate
    # REDHAT/DNF BASED
    elif [[ $1 == "dnf" ]]; then
        sudo dnf install -y chronyd xfsprogs tree tzdata awscli curl wget vim iproute jq unzip util-linux-user
    # GFYS
    else
        echo "Unsupported package manager: $1"
        exit 1
    fi
}


base_os_configuration() {
  # APT
  sudo hostnamectl set-hostname $node_name

  if [[ $package_manager == "apt" ]]; then
    # Set the timezone to America/Los_Angeles
    echo "Setting timezone to America/Los_Angeles..."
    sudo timedatectl set-timezone America/Los_Angeles
    
    # Enable and start chrony service
    echo "Enabling and starting chrony service..."
    sudo systemctl enable chrony
    sudo systemctl start chrony
  
  # DNF
  elif [[ $package_manager == "dnf" ]]; then
      # Set the timezone to America/Los_Angeles
      echo "Setting timezone to America/Los_Angeles..."
      sudo timedatectl set-timezone America/Los_Angeles
      
      # Enable and start chrony service
      echo "Enabling and starting chrony service..."
      sudo systemctl enable chronyd
      sudo systemctl start chronyd
  else
      echo -e "'package_manager' argument not supplied or is not in the following list ['apt', 'dnf']!\nPlease provide the package manager to use."
      exit 1
  fi

  # Verify the time and timezone settings
  echo "Verifying the time and timezone settings..."
  timedatectl

  # Check the status of chrony service
  echo "Checking the status of chrony service..."
  sudo chronyc tracking

  # Establish Disks
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  DISKS=$(aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" --query "Volumes[*].{VolumeID:VolumeId, DeviceName:Attachments[0].Device}" --region "us-west-2" --output text | grep xvd | awk {'print $1'})
  idx=1
  
  for DISK in $DISKS; do
    sudo mkdir -p /mnt/data$idx
    sudo chown -R root:root /mnt/data$idx
    ((idx++))
  done

  # temp mount
  idx=1
  for DISK in $DISKS; do
  	sudo mkfs.xfs $DISK
  	sudo mount $DISK /mnt/data$idx;
    ((idx++))
  done;

  # Update /etc/hosts file with private ips
  for host in ${hosts}; do
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    PRIVATE_IP=$(aws ec2 describe-instances   --region $REGION   --filters "Name=tag:Name,Values=$host"   --query 'Reservations[*].Instances[*].PrivateIpAddress'   --output text)
    echo -e "$PRIVATE_IP $host" | sudo tee -a /etc/hosts
  done

  # Update SSH config to not ask for fingerprint verification
  sudo install -o ubuntu -g ubuntu -m 0600 /dev/null /home/ubuntu/.ssh/config
  cat > /home/ubuntu/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
EOF

}

############
### MAIN ###
############

main() {
  install_custom_dependencies $package_manager
  base_os_configuration $package_manager
}

main
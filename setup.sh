#!/bin/bash

# Global Variables
package_manager=${package_manager}
system_user=${system_user}
node_name=${node_name}
hosts=${hosts}
minio_user=${minio_user}
host_count=${host_count}
disk_count=${disk_count}

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

  # Create minio-user group
  echo "Creating ${minio_user} Group"
  sudo groupadd -r ${minio_user}

  # Create minio-user user
  echo "Creating ${minio_user} User"
  sudo useradd -m -d /home/${minio_user} -r -g ${minio_user} ${minio_user}

  # Establish Disks
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  DISKS=$(aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" --query "Volumes[*].{VolumeID:VolumeId, DeviceName:Attachments[0].Device}" --region "us-west-2" --output text | grep xvd | awk {'print $1'})
  idx=1
  
  for DISK in $DISKS; do
    echo "Creating /mnt/data$idx"
    sudo mkdir -p /mnt/data$idx
    ((idx++))
  done

  # temp mount
  idx=1
  for DISK in $DISKS; do
    sudo mkfs.xfs $DISK
    sudo mount $DISK /mnt/data$idx;
    echo "Changing /mnt/data$idx ownership to $minio_user"
    sudo chown -R $minio_user:$minio_user /mnt/data$idx
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

function minio_installation() {
  # Download MinIO Server Binary
  wget https://dl.min.io/server/minio/release/linux-amd64/minio

  # Make executable
  chmod +x minio

  # Move into /usr/local/bin
  sudo mv minio /usr/local/bin/

  # Download MinIO Command Line Client
  wget https://dl.min.io/client/mc/release/linux-amd64/mc

  # Make Executable
  chmod +x mc

  # Add to usr local
  sudo mv mc /usr/local/bin
}

function minio_configuration() {
# Create MinIO Defaults File
export node_name=$(hostname | sed "s|-[0-9999]$||g")
sudo tee /etc/default/minio > /dev/null << EOF
# MINIO_ROOT_USER and MINIO_ROOT_PASSWORD sets the root account for the MinIO server.
# This user has unrestricted permissions to perform S3 and administrative API operations on any resource in the deployment.
# Omit to use the default values 'minioadmin:minioadmin'.
# MinIO recommends setting non-default values as a best practice, regardless of environment

MINIO_ROOT_USER=miniominio
MINIO_ROOT_PASSWORD=miniominio

# MINIO_VOLUMES sets the storage volume or path to use for the MinIO server.

MINIO_VOLUMES="http://$${node_name}-{1...$${host_count}}:9000/mnt/data{1...$${disk_count}}/minio"

# MINIO_OPTS sets any additional commandline options to pass to the MinIO server.
# For example, '--console-address :9001' sets the MinIO Console listen port
MINIO_OPTS="--address 0.0.0.0:9000 --console-address 0.0.0.0:9001"

# MINIO_SERVER_URL sets the hostname of the local machine for use with the MinIO Server
# MinIO assumes your network control plane can correctly resolve this hostname to the local machine

# Uncomment the following line and replace the value with the correct hostname for the local machine and port for the MinIO server (9000 by default).

MINIO_SERVER_URL="http://0.0.0.0:9000"
EOF

sudo tee /usr/lib/systemd/system/minio.service > /dev/null << 'EOF'
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/local/bin/minio
AssertFileNotEmpty=/etc/default/minio

[Service]
Type=notify
WorkingDirectory=/usr/local/

User=minio
Group=minio
ProtectProc=invisible

EnvironmentFile=/etc/default/minio
ExecStartPre=/bin/bash -c "if [ -z \"$${MINIO_VOLUMES}\" ]; then echo 'Variable MINIO_VOLUMES not set in /etc/default/minio'; exit 1; fi"
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES

# Let systemd restart this service always
Restart=always

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=1048576

# Specifies the maximum number of threads this process can create
TasksMax=infinity

# Disable timeout logic and wait until process is stopped
TimeoutSec=infinity

SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

  # Update /etc/hosts file with private ips
  for host in ${hosts}; do
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    PRIVATE_IP=$(aws ec2 describe-instances   --region $REGION   --filters "Name=tag:Name,Values=$host"   --query 'Reservations[*].Instances[*].PrivateIpAddress'   --output text)
    echo -e "$PRIVATE_IP $host" | sudo tee -a /etc/hosts
  done

  # Enable and start minio service
  sudo systemctl enable minio
  sudo systemctl start minio
}

############
### MAIN ###
############

main() {
  install_custom_dependencies $package_manager
  base_os_configuration $package_manager
  minio_installation
  minio_configuration
}

main

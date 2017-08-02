#!/bin/bash
# Last Modified : 2016-05-26

rhn_username=$1
rhn_pass=$2
rhn_pool=$3


# subscription-manager register --username=${rhn_username} --password=${rhn_pass} --force
# subscription-manager attach --pool=${rhn_pool}

# subscription-manager repos --disable="*"
# subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-server-ose-3.5-rpms" --enable="rhel-7-fast-datapath-rpms"

# sed -i -e 's/sslverify=1/sslverify=0/' /etc/yum.repos.d/rh-cloud.repo
# sed -i -e 's/sslverify=1/sslverify=0/' /etc/yum.repos.d/rhui-load-balancers

# Install base packages
yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion docker
yum -y install atomic-openshift-utils
yum -y update

# Configure Docker

## Disable certificate for Docker registry
sed -i '/OPTIONS=.*/c\OPTIONS="--selinux-enabled --insecure-registry 172.30.0.0/16"' /etc/sysconfig/docker

## Configure Docker storage
cat <<EOF > /etc/sysconfig/docker-storage-setup
DEVS=/dev/sdc
VG=docker-vg
EOF

docker-storage-setup
systemctl enable docker
systemctl start docker

# Setup NFS 
yum -y install nfs-utils rpcbind
systemctl enable rpcbind
systemctl start rpcbind
setsebool -P virt_sandbox_use_nfs 1
setsebool -P virt_use_nfs 1

# Disable firewall
systemctl stop firewalld
systemctl disable firewalld

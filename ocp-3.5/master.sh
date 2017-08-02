#!/bin/bash
# Last Modified : 2016-08-29

USERNAME=$1
PASSWORD=$2
HOSTNAME=$3
NODECOUNT=$4
ROUTEREXTIP=$5
rhn_username=$6
rhn_pass=$7
rhn_pool=$8


subscription-manager register --username=${rhn_username} --password=${rhn_pass} --force
subscription-manager attach --pool=${rhn_pool}

subscription-manager repos --disable="*"
subscription-manager repos --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms" --enable="rhel-7-server-ose-3.5-rpms" --enable="rhel-7-fast-datapath-rpms"

sed -i -e 's/sslverify=1/sslverify=0/' /etc/yum.repos.d/rh-cloud.repo
sed -i -e 's/sslverify=1/sslverify=0/' /etc/yum.repos.d/rhui-load-balancers

yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion docker
yum -y install atomic-openshift-utils
yum -y update

sed -i '/OPTIONS=.*/c\OPTIONS="--selinux-enabled --insecure-registry 172.30.0.0/16"' /etc/sysconfig/docker

cat <<EOF > /etc/sysconfig/docker-storage-setup
DEVS=/dev/sdc
VG=docker-vg
EOF

docker-storage-setup
systemctl enable docker
systemctl start docker

yum -y install nfs-utils rpcbind
systemctl enable rpcbind
systemctl start rpcbind
setsebool -P virt_sandbox_use_nfs 1
setsebool -P virt_use_nfs 1

cat <<EOF > /etc/ansible/hosts
[OSEv3:children]
masters
nodes

[OSEv3:vars]
ansible_ssh_user=${USERNAME}
ansible_become=true
debug_level=2
deployment_type=openshift-enterprise

openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]

openshift_master_default_subdomain=${ROUTEREXTIP}.nip.io
openshift_use_dnsmasq=False

# Install the openshift examples
openshift_install_examples=true

# Enable cluster metrics
use_cluster_metrics=true

# Configure metricsPublicURL in the master config for cluster metrics
openshift_master_metrics_public_url=https://metrics.${ROUTEREXTIP}.nip.io/hawkular/metrics

# Configure loggingPublicURL in the master config for aggregate logging
openshift_master_logging_public_url=https://kibana.${ROUTEREXTIP}.nip.io

# Defining htpasswd users (password is redhat123)
openshift_master_htpasswd_users={'admin': '\$apr1\$bdqbl2eo\$Na6mZ6SG7Vfo3YPyp1vJP.', 'demo': '\$apr1\$ouJ9QtwY\$Z2WZ9yvm1.tNzipdR.4Wp1'}

# Enable cockpit
osm_use_cockpit=true
osm_cockpit_plugins=['cockpit-kubernetes']

# default project node selector
osm_default_node_selector='region=primary'

openshift_router_selector='region=infra'
openshift_registry_selector='region=infra'

# Confifgure router
# Force to 1 otherwise Ansible compute 2 replicas cause master and infranode are region=infra
# but Ansible does not take into account that master is not schedulable. So it fails...
openshift_hosted_router_replicas=1

# Configure an internal regitry
openshift_hosted_registry_selector='region=infra'
openshift_hosted_registry_replicas=1
openshift_hosted_registry_storage_kind=nfs
openshift_hosted_registry_storage_access_modes=['ReadWriteMany']
openshift_hosted_registry_storage_host=infranode
openshift_hosted_registry_storage_nfs_directory=/exports
openshift_hosted_registry_storage_volume_name=registry
openshift_hosted_registry_storage_volume_size=15Gi

# Enable metrics
openshift_metrics_install_metrics=true
openshift_metrics_hawkular_hostname=metrics.${ROUTEREXTIP}.nip.io
openshift_metrics_storage_kind=nfs
openshift_metrics_storage_access_modes=['ReadWriteOnce']
openshift_metrics_storage_host=infranode
openshift_metrics_storage_nfs_directory=/exports
openshift_metrics_storage_volume_name=metrics
openshift_metrics_storage_volume_size=5Gi

# Enable logging
openshift_logging_install_logging=true
openshift_logging_namespace=logging
openshift_logging_use_ops=false
openshift_logging_master_public_url=https://${HOSTNAME}:8443
openshift_logging_es_cluster_size=1
openshift_logging_es_pvc_size=5G
openshift_logging_es_memory_limit=2G
openshift_logging_es_nodeselector={"region":"infra"}
openshift_logging_kibana_hostname=kibana.${ROUTEREXTIP}.nip.io
openshift_logging_kibana_nodeselector={"region":"infra"}
openshift_logging_curator_nodeselector={"region":"infra"}
openshift_logging_storage_kind=nfs
openshift_logging_storage_access_modes=['ReadWriteOnce']
openshift_logging_storage_host=infranode
openshift_logging_storage_nfs_directory=/exports
openshift_logging_storage_volume_name=logging-es
openshift_logging_storage_volume_size=10Gi

[masters]
master openshift_node_labels="{'region': 'infra', 'zone': 'default'}"  openshift_public_hostname=${HOSTNAME}

[nodes]
master
infranode openshift_node_labels="{'region': 'infra', 'zone': 'default'}"
node[01:${NODECOUNT}] openshift_node_labels="{'region': 'primary', 'zone': 'default'}"

EOF

cat <<EOF > /home/${USERNAME}/openshift-install.sh
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml
oc annotate namespace default openshift.io/node-selector='region=infra' --overwrite
oadm policy add-cluster-role-to-user cluster-admin admin
EOF

chmod 755 /home/${USERNAME}/openshift-install.sh

n=1
while [ $n -le 4 ]
do
cat <<EOF > /home/${USERNAME}/pv000$n.json
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "pv000$n"
  },
  "spec": {
    "capacity": {
        "storage": "1Gi"
    },
    "accessModes": [ "ReadWriteOnce", "ReadWriteMany" ],
    "nfs": {
        "path": "/exports/pv000$n",
        "server": "infranode"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
(( n++ ))
done

n=5
while [ $n -le 9 ]
do
cat <<EOF > /home/${USERNAME}/pv000$n.json
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "pv000$n"
  },
  "spec": {
    "capacity": {
        "storage": "5Gi"
    },
    "accessModes": [ "ReadWriteOnce", "ReadWriteMany" ],
    "nfs": {
        "path": "/exports/pv000$n",
        "server": "infranode"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
(( n++ ))
done

n=10
while [ $n -le 15 ]
do
cat <<EOF > /home/${USERNAME}/pv00$n.json
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "pv00$n"
  },
  "spec": {
    "capacity": {
        "storage": "10Gi"
    },
    "accessModes": [ "ReadWriteOnce", "ReadWriteMany" ],
    "nfs": {
        "path": "/exports/pv00$n",
        "server": "infranode"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
(( n++ ))
done

n=16
while [ $n -le 20 ]
do
cat <<EOF > /home/${USERNAME}/pv00$n.json
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "pv00$n"
  },
  "spec": {
    "capacity": {
        "storage": "25Gi"
    },
    "accessModes": [ "ReadWriteOnce", "ReadWriteMany" ],
    "nfs": {
        "path": "/exports/pv00$n",
        "server": "infranode"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
(( n++ ))
done

cat <<EOF > /home/${USERNAME}/create-pvs.sh
n=1
while [ \$n -le 9 ]
do
  oc create -f pv000\$n.json
  (( n++ ))
done
n=10
while [ \$n -le 20 ]
do
oc create -f pv00\$n.json
(( n++ ))
done
EOF

chmod 755 /home/${USERNAME}/create-pvs.sh

cat <<EOF > /home/${USERNAME}/openshift-services-deploy.sh

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/openshift-cluster/openshift-metrics.yml \
   -e openshift_metrics_install_metrics=True \
   -e openshift_metrics_hawkular_hostname=metrics.${ROUTEREXTIP}.nip.io \
   -e openshift_metrics_cassandra_storage_type=pv \
   -e openshift_metrics_cassandra_cpvc_size=5G


ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/openshift-cluster/openshift-logging.yml \
  -e openshift_logging_install_logging=true \
  -e openshift_logging_namespace=logging \
  -e openshift_logging_use_ops=false \
  -e openshift_logging_master_public_url=https://${HOSTNAME}:8443 \
  -e openshift_logging_es_cluster_size=1 \
  -e openshift_logging_es_pvc_size=5G \
  -e openshift_logging_es_memory_limit=2G \
  -e openshift_logging_kibana_hostname=kibana.${ROUTEREXTIP}.nip.io

oc label nodes --selector='region=primary' logging-infra-fluentd=true
EOF

chmod 755 /home/${USERNAME}/openshift-services-deploy.sh

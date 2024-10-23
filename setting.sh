# k8sの環境構築を行うためのシェル
#!/bin/bash

# Common
OSNAME="$(. /etc/os-release && echo "${ID}" | tr '[:upper:]' '[:lower:]')"
ARCH="amd64"
if [ $(uname -m) == "aarch64" ]; then
    ARCH="arm64"
fi

# Kubernetes
VERSION="1.28"

# CNI Plugin
CNI_PLUGINS_VERSION="v1.3.0"
CNI_DEST="/opt/cni/bin"

# Containerd
NERDCTL_VERSION="1.7.0"

# Forwarding IPv4 and letting iptables see bridged traffic
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#forwarding-ipv4-and-letting-iptables-see-bridged-traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# Update
sudo apt-get update -y
sudo install -m 0755 -d /etc/apt/keyrings

# Install requirements
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    nfs-common

# Add Kubernetes Repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Add Docker Repository (for Containerd)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OSNAME} \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Kubernetes and lock the version
sudo apt update
sudo apt install -y kubectl kubelet kubeadm
sudo apt-mark hold kubelet kubeadm kubectl

# Install containerd
sudo apt install containerd.io -y
sudo systemctl start containerd
sudo systemctl enable containerd
sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.orig
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# Install CNI Plugin
sudo mkdir -p "${CNI_DEST}"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "${CNI_DEST}" -xz

# Install nerdctl
wget https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz
sudo tar Cxzvf /usr/local/bin nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz
rm nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Swap Off
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable cgroup memory for Ubuntu Server
if [ $(uname -m) == "aarch64" ]; then
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& cgroup_enable=memory cgroup_memory=1/' /etc/default/grub
  sudo update-grub
fi

echo "Finished."

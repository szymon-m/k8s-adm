#!/bin/bash

apt-get update -y
apt-get upgrade -y

apt-get install vim -y
apt install curl apt-transport-https git wget software-properties-common ca-certificates etcd-client -y

echo "[TASK 1] Create module configuration file for containerd"
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# load modules
modprobe overlay >/dev/null 2>&1
modprobe br_netfilter >/dev/null 2>&1

echo "[TASK 2] Set system configurations for Kubernetes networking"
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# apply new settings
sysctl --system >/dev/null 2>&1

echo "[TASK 3] Install containerd runtime"
apt-get update >/dev/null 2>&1
apt-get install -y containerd >/dev/null 2>&1

echo "[TASK 4] Generate default containerd configuration and save to the newly created default file"
mkdir -p /etc/containerd >/dev/null 2>&1
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

echo "[TASK 5] Update containerd option for System Cgroup"
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml >/dev/null 2>&1

# apply new settings
systemctl restart containerd >/dev/null 2>&1

echo "[TASK 6] Disable SWAP"
swapoff -a >/dev/null 2>&1
sed -i 's/.* none.* swap.* sw.*/#&/g' /etc/fstab >/dev/null 2>&1

echo "[TASK 7] Install depencdency packages"
apt-get update >/dev/null 2>&1
apt-get install -y apt-transport-https curl >/dev/null 2>&1

echo "[TASK 8] Add GPG key for K8s repo"
mkdir -p /etc/apt/keyrings
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
 >/dev/null 2>&1

echo "[TASK 9] Add K8s repository"
if [[ $# -gt 3 ]]; then
        curl -x $4 -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg >/dev/null 2>&1
else
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg >/dev/null 2>&1
fi

echo "[TASK 10] Add K8s binaries"
apt-get install -y kubelet=1.29.1-1.1 kubeadm=1.29.1-1.1 kubectl=1.29.1-1.1
apt-mark hold kubelet kubeadm kubectl

echo "[TASK 11] Init K8s cluster"
kubeadm init --pod-network-cidr 192.168.0.0/16 --kubernetes-version 1.29.1

echo "[TASK 12] Install Cilium k8s's network plugin"
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
cilium install

echo "[TASK 13] Enable kubectl bash completion"
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

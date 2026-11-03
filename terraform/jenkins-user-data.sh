#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl docker.io unzip

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
  -o /etc/apt/keyrings/adoptium.asc
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb jammy main" \
  > /etc/apt/sources.list.d/adoptium.list

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt-get update
apt-get install -y temurin-21-jre fontconfig jenkins

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) AWS_ARCH=x86_64 ;;
  arm64) AWS_ARCH=aarch64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

KUBERNETES_VERSION="${kubernetes_version}"
KUBECTL_VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable-$${KUBERNETES_VERSION}.txt")
case "$ARCH" in
  amd64) KUBECTL_ARCH=amd64 ;;
  arm64) KUBECTL_ARCH=arm64 ;;
esac
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/$${KUBECTL_ARCH}/kubectl"
chmod 0755 /usr/local/bin/kubectl

usermod -aG docker jenkins
systemctl enable --now docker
systemctl restart jenkins

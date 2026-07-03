#!/bin/bash
# Bootstrap des instances Frontend.
# S'exécute une seule fois au premier démarrage de chaque instance ASG.
# Objectif : monter l'EFS et préparer le terrain pour Ansible.

set -euo pipefail

apt-get update -y
apt-get upgrade -y

# Outil de montage EFS d'Amazon : gère le chiffrement en transit (TLS)
# et les retries automatiques au démarrage.
apt-get install -y amazon-efs-utils

# Création du point de montage pour les segments HLS/DASH
mkdir -p /mnt/efs/hls

# Montage EFS via le helper amazon-efs-utils.
# _netdev : attend que le réseau soit disponible avant de monter.
# tls      : chiffre le trafic NFS entre l'instance et l'EFS (en transit).
# Le DNS du Mount Target est résolu automatiquement vers l'AZ locale.
echo "${efs_id}:/ /mnt/efs/hls efs _netdev,tls 0 0" >> /etc/fstab
mount -a

# SSM agent (pré-installé sur Ubuntu 22.04 AMI AWS)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# CloudWatch agent (configuré par Ansible - playbook cloudwatch-agent.yml)
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

echo "Bootstrap Frontend terminé - $(date)" >> /var/log/bootstrap.log

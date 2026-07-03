#!/bin/bash
# Bootstrap minimal de l'instance Streamer.
# Ce script s'exécute UNE SEULE FOIS au premier démarrage de l'instance.
# Il prépare le terrain pour Ansible, qui fera l'installation complète de FFmpeg.

set -euo pipefail

# Mise à jour du système avant toute installation
apt-get update -y
apt-get upgrade -y

# L'agent SSM est pré-installé sur Ubuntu 22.04 AMI AWS.
# On s'assure juste qu'il est démarré et activé au boot.
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Installation de l'agent CloudWatch
# Il sera configuré par Ansible (playbook cloudwatch-agent.yml).
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Tag dans les logs système pour tracer le bootstrap
echo "Bootstrap Streamer terminé - $(date)" >> /var/log/bootstrap.log

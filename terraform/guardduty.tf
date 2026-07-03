# ============================================================
# GuardDuty - Détection de menaces
# ============================================================
# GuardDuty est un service de détection d'intrusion managé (IDS-as-a-Service).
# Il analyse en continu 3 sources de données pour détecter des comportements
# malveillants ou anormaux :
#   1. VPC Flow Logs   : trafic réseau suspect (scan de ports, exfiltration...)
#   2. CloudTrail      : appels API inhabituels (credential stuffing, escalade de privs...)
#   3. DNS Logs        : requêtes vers des domaines malveillants connus
#
# Avantage clé : GuardDuty utilise les threat intelligence feeds d'AWS
# (IP malveillantes, domaines C&C) + machine learning pour détecter
# des anomalies comportementales, sans aucune configuration de règles.

resource "aws_guardduty_detector" "main" {
  enable = true

  # Fréquence de publication des findings vers CloudWatch Events / EventBridge.
  # SIX_HOURS : suffisant pour un projet étudiant.
  # En prod sur un système critique, on utiliserait FIFTEEN_MINUTES.
  finding_publishing_frequency = "SIX_HOURS"

  # Sources de données activées (toutes activées par défaut, on les rend explicites)
  datasources {
    s3_logs {
      enable = true # Surveille les accès S3 suspects (ex: lecture massive de données)
    }
    kubernetes {
      audit_logs {
        enable = false # Pas de Kubernetes dans cette architecture
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true # Scan malware des volumes EBS si un finding EC2 est détecté
        }
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-guardduty"
  }
}

# ============================================================
# EFS - Elastic File System
# ============================================================

resource "aws_efs_file_system" "main" {
  # Chiffrement au repos
  # AWS gère la clé KMS par défaut
  encrypted = true

  # generalPurpose : latence la plus basse, adapté aux lectures fréquentes
  # de petits fichiers (segments HLS de quelques secondes).
  performance_mode = "generalPurpose"

  # bursting : le débit suit l'usage
  throughput_mode = "bursting"

  # Les segments HLS/DASH sont des fichiers temporaires.
  # Après 30 jours sans accès, ils basculent vers le stockage IA (moins cher).
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${local.name_prefix}-efs"
  }
}

# ============================================================
# Mount Targets (un par AZ)
# ============================================================
# 
# Règle EFS : un seul Mount Target par AZ.
# On en crée 2 : un dans public_az_a, un dans public_az_b.
# Chaque instance Frontend monte l'EFS depuis le MT de SON AZ
# (latence minimale, pas de trafic inter-AZ facturé).

resource "aws_efs_mount_target" "az_a" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.public_az_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "az_b" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.public_az_b.id
  security_groups = [aws_security_group.efs.id]
}

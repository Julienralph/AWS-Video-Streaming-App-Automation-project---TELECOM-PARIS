# ============================================================
# IAM - Rôles et profils d'instance pour les EC2
# ============================================================
# DESACTIVE : le compte SSO Telecom Paris n'autorise pas iam:CreateRole.
# Les instances EC2 tournent sans instance profile (SSM non disponible).
# A re-activer si les permissions IAM sont accordees par l'administrateur.
# ============================================================

/*
# ============================================================
# RÔLE FRONTEND (NGINX + RTMP)
# ============================================================

resource "aws_iam_role" "frontend" {
  name        = "${local.name_prefix}-frontend-role"
  description = "Rôle IAM pour les instances Frontend (SSM + CloudWatch)"

  # Trust policy : déclare QUI peut assumer ce rôle.
  # Ici on autorise uniquement le service EC2.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AmazonSSMManagedInstanceCore : donne à l'instance les droits
# pour s'enregistrer auprès de SSM et recevoir des sessions.
# C'est ce qui remplace SSH dans notre architecture.
resource "aws_iam_role_policy_attachment" "frontend_ssm" {
  role       = aws_iam_role.frontend.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatchAgentServerPolicy : permet à l'agent CloudWatch sur l'instance
# de pousser des métriques et des logs vers CloudWatch.
resource "aws_iam_role_policy_attachment" "frontend_cloudwatch" {
  role       = aws_iam_role.frontend.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# L'instance profile est l'enveloppe que l'on attache à une EC2.
# Une EC2 ne peut pas porter un rôle directement, seulement un instance profile.
resource "aws_iam_instance_profile" "frontend" {
  name = "${local.name_prefix}-frontend-profile"
  role = aws_iam_role.frontend.name
}

# ============================================================
# RÔLE STREAMER (FFmpeg)
# ============================================================

resource "aws_iam_role" "streamer" {
  name        = "${local.name_prefix}-streamer-role"
  description = "Rôle IAM pour l'instance Streamer FFmpeg (SSM + CloudWatch)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "streamer_ssm" {
  role       = aws_iam_role.streamer.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "streamer_cloudwatch" {
  role       = aws_iam_role.streamer.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "streamer" {
  name = "${local.name_prefix}-streamer-profile"
  role = aws_iam_role.streamer.name
}
*/

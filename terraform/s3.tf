# ============================================================
# S3 - Bucket pour le player HTML
# ============================================================
# Ce bucket contient uniquement le fichier index.html du player vidéo.
# Il n'est PAS accessible publiquement en direct. CloudFront s'y connecte
# via OAC (Origin Access Control) et le sert aux utilisateurs.
#
# Architecture :
#   Utilisateur → CloudFront → S3 (player HTML)
#                           → ALB → Frontend (segments HLS)

# Data source pour récupérer l'ID du compte AWS courant.
# Utilisé pour garantir l'unicité du nom du bucket (globalement unique dans AWS).
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "player" {
  # Les noms de bucket S3 sont globalement uniques dans AWS.
  # On suffixe avec l'account ID pour éviter les conflits avec d'autres étudiants.
  bucket = "${local.name_prefix}-player-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-player"
  }
}

# Versioning : garde un historique des versions du player.
# Utile pour rollback rapide si une mise à jour du player casse l'affichage.
resource "aws_s3_bucket_versioning" "player" {
  bucket = aws_s3_bucket.player.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement au repos : AES-256 géré par AWS (SSE-S3).
# Toutes les données écrites dans le bucket sont chiffrées automatiquement.
resource "aws_s3_bucket_server_side_encryption_configuration" "player" {
  bucket = aws_s3_bucket.player.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Blocage de tout accès public direct au bucket.
# Le seul accès autorisé est celui de CloudFront via OAC (défini dans cloudfront.tf).
# Sans ce bloc, une mauvaise manipulation pourrait exposer le bucket publiquement.
resource "aws_s3_bucket_public_access_block" "player" {
  bucket = aws_s3_bucket.player.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload du player HTML dans le bucket.
# Ce fichier sera créé manuellement ou lors d'une étape de déploiement séparée.
# On dépose ici un placeholder minimal pour que CloudFront ait quelque chose à servir.
resource "aws_s3_object" "player_html" {
  bucket       = aws_s3_bucket.player.id
  key          = "index.html"
  content_type = "text/html"

  content = <<-HTML
    <!DOCTYPE html>
    <html lang="fr">
    <head>
      <meta charset="UTF-8">
      <title>GIN208 - Video Streaming</title>
    </head>
    <body>
      <h1>Player en cours de déploiement</h1>
      <p>Le player HLS sera configuré ici après déploiement Ansible.</p>
    </body>
    </html>
  HTML

  tags = {
    Name = "${local.name_prefix}-player-html"
  }
}

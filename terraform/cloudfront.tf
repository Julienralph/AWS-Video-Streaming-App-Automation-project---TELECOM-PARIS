# ============================================================
# CloudFront - Distribution CDN
# ============================================================
# CloudFront est le CDN (Content Delivery Network) d'AWS.
# Il a 2 origines dans cette architecture :
#   1. S3     : sert le player HTML (index.html)
#   2. ALB    : sert les segments HLS/DASH générés par le Frontend
#
# Routing par chemin :
#   julienralph-pod-1.devops.intuitivelabs.net/       → S3 (player)
#   julienralph-pod-1.devops.intuitivelabs.net/hls/*  → ALB → Frontend

# ============================================================
# OAC - Origin Access Control (pour S3)
# ============================================================
# L'OAC remplace l'ancien OAI (déprécié depuis 2022).
# Il permet à CloudFront de s'authentifier auprès de S3 avec SigV4.
# Sans OAC, le bucket S3 (privé) refuserait les requêtes de CloudFront.

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.name_prefix}-oac-s3"
  description                       = "OAC pour accès CloudFront → S3 player"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============================================================
# Distribution CloudFront
# ============================================================

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "GIN208 Video Streaming - ${var.domain_name}"
  default_root_object = "index.html"

  # Domaine personnalisé (Route53 pointera un ALIAS vers ce domaine CF)
  aliases = [var.domain_name]

  # ----------------------------------------------------------
  # Origine 1 : S3 (player HTML)
  # ----------------------------------------------------------
  origin {
    origin_id                = "s3-player"
    domain_name              = aws_s3_bucket.player.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ----------------------------------------------------------
  # Origine 2 : ALB (segments HLS/DASH)
  # ----------------------------------------------------------
  # CloudFront → ALB en HTTP (port 80).
  # Justification : le trafic CF → ALB reste dans l'infrastructure AWS.
  # Le TLS utilisateur est géré par CloudFront (HTTPS vers le client).
  # L'ALB est protégé par son Security Group (sg_alb).
  origin {
    origin_id   = "alb-frontend"
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ----------------------------------------------------------
  # Comportement par défaut : S3 (player HTML)
  # ----------------------------------------------------------
  # Toutes les requêtes vont vers S3 sauf /hls/* (voir ci-dessous).
  # Politique de cache "Optimized" : CloudFront met en cache le HTML
  # et le sert depuis ses edge locations mondiales.

  default_cache_behavior {
    target_origin_id       = "s3-player"
    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS automatique

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # Managed policy "CachingOptimized" : TTL par défaut 24h, compressé
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # ----------------------------------------------------------
  # Comportement /hls/* : ALB (segments HLS en temps réel)
  # ----------------------------------------------------------
  # Les segments HLS sont des fichiers courts (2-6 secondes).
  # La playlist .m3u8 se met à jour toutes les quelques secondes.
  # On désactive le cache pour garantir que le player reçoit toujours
  # les segments les plus récents.

  ordered_cache_behavior {
    path_pattern           = "/hls/*"
    target_origin_id       = "alb-frontend"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # Managed policy "CachingDisabled" : aucun cache, requête transmise telle quelle
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  # ----------------------------------------------------------
  # Certificat TLS (ACM)
  # ----------------------------------------------------------
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"    # SNI : standard moderne, pas de surcoût
    minimum_protocol_version = "TLSv1.2_2021" # Désactive TLS 1.0 et 1.1
  }

  # Pas de restrictions géographiques (accessible depuis le monde entier)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}

# ============================================================
# Politique du bucket S3 : autorise CloudFront via OAC
# ============================================================
# Cette policy est ici (et non dans s3.tf) parce qu'elle référence
# l'ARN de la distribution CloudFront, créée juste au-dessus.

resource "aws_s3_bucket_policy" "player" {
  bucket = aws_s3_bucket.player.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.player.arn}/*"
      Condition = {
        StringEquals = {
          # Limite l'accès à CETTE distribution uniquement
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

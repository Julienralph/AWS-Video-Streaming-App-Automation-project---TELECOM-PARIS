# ============================================================
# ACM - Certificate Manager
# ============================================================
# ACM émet et renouvelle automatiquement des certificats TLS/SSL gratuits.
# Dans ce projet, UN SEUL certificat couvre les deux usages :
#   - Le listener HTTPS de l'ALB (alb.tf)
#   - La distribution CloudFront (cloudfront.tf)
# C'est possible car ALB et CloudFront sont tous les deux en us-east-1.
# (Si l'ALB était dans une autre région, il faudrait un 2e certificat.)

data "aws_route53_zone" "main" {
  name         = var.route53_zone_name # "devops.intuitivelabs.net"
  private_zone = false
}

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name # "julienralph-pod-1.devops.intuitivelabs.net"
  validation_method = "DNS"

  # create_before_destroy : si le certificat doit être recréé (ex: changement de domaine),
  # Terraform crée le nouveau AVANT de détruire l'ancien.
  # Sans ça, l'ALB et CloudFront auraient quelques secondes sans certificat valide.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cert"
  }
}

# ============================================================
# Enregistrements DNS de validation
# ============================================================
# ACM génère un ou plusieurs enregistrements CNAME à créer dans la zone DNS
# pour prouver qu'on contrôle le domaine. On les crée ici automatiquement.
#
# Le for_each sur domain_validation_options gère le cas où le certificat
# couvre plusieurs domaines (SAN). Ici on n'en a qu'un, mais le pattern
# est le même et c'est la bonne pratique.

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# ============================================================
# Validation du certificat
# ============================================================
# Cette ressource attend qu'ACM confirme la validation DNS.
# Terraform est bloqué ici jusqu'à ce qu'AWS vérifie le CNAME
# (peut prendre quelques minutes).
# Toutes les ressources qui utilisent le certificat (ALB, CloudFront)
# dépendent implicitement de cette validation via aws_acm_certificate.main.arn.

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation : record.fqdn
  ]
}

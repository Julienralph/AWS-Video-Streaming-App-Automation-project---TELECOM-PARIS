# ============================================================
# Route53 - Enregistrement DNS
# ============================================================
# Route53 fait le lien entre le domaine lisible par l'humain
# (julienralph-pod-1.devops.intuitivelabs.net) et CloudFront.
#
# La zone "devops.intuitivelabs.net" est déjà déclarée comme
# data source dans acm.tf. On la réutilise directement ici.

# Enregistrement ALIAS : julienralph-pod-1.devops.intuitivelabs.net → CloudFront
#
# Pourquoi ALIAS et pas CNAME ?
# 1. Performance : l'ALIAS est résolu par Route53 lui-même, sans requête DNS
#    supplémentaire vers CloudFront. Le CNAME nécessite 2 résolutions.
# 2. Coût : les requêtes vers un enregistrement ALIAS AWS sont gratuites.
#    Un CNAME facture chaque requête DNS normalement.
# 3. Apex : l'ALIAS fonctionne à la racine d'une zone (ex: example.com),
#    le CNAME est interdit à la racine par la spec DNS (RFC 1912).

resource "aws_route53_record" "app" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = var.domain_name # "julienralph-pod-1.devops.intuitivelabs.net"
  type            = "A"
  allow_overwrite = true # L'enregistrement existe deja dans la zone, on le remplace

  alias {
    name    = aws_cloudfront_distribution.main.domain_name
    # Z2FDTNDATAQYW2 est l'ID de zone Route53 de CloudFront.
    # Cette valeur est fixe pour TOUTES les distributions CloudFront dans AWS.
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

# Enregistrement IPv6 (AAAA) : CloudFront supporte IPv6 nativement.
# On a activé is_ipv6_enabled = true dans cloudfront.tf.
# Sans cet enregistrement, les clients IPv6 purs ne pourraient pas résoudre le domaine.
resource "aws_route53_record" "app_ipv6" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = var.domain_name
  type            = "AAAA"
  allow_overwrite = true # L'enregistrement existe deja dans la zone, on le remplace

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

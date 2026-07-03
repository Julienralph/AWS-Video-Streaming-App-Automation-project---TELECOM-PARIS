# ============================================================
# NACLs - Network Access Control Lists
# ============================================================
#
# Fonctionnement des règles :
#   - Évaluées dans l'ordre croissant des numéros (100, 110, 120...)
#   - La PREMIÈRE règle qui correspond gagne (allow ou deny)
#   - Si aucune règle ne correspond → DENY implicite (règle 32767)
#   - On laisse des écarts (100, 110, 120) pour insérer des règles plus tard

# ============================================================
# NACL PUBLIC (subnets public_az_a et public_az_b)
# ============================================================
# Ces subnets hébergent : ALB, Frontend EC2 (NGINX+RTMP), EFS Mount Targets,
# NAT Gateway.

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id
  subnet_ids = [
    aws_subnet.public_az_a.id,
    aws_subnet.public_az_b.id,
  ]

  # ----------------------------------------------------------
  # RÈGLES ENTRANTES (inbound)
  # ----------------------------------------------------------

  # SSH temporaire pour Ansible (en attendant SSM/IAM)
  # Priorité 90 : évaluée avant les règles HTTP/HTTPS.
  # NACL stateless : sans cette règle, les paquets SSH sont droppes
  # silencieusement meme si le Security Group l'autorise.
  ingress {
    rule_no    = 90
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # Utilisateurs → ALB : HTTPS
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Utilisateurs → ALB : HTTP (l'ALB redirige vers HTTPS)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Streamer (subnet public AZ-a) → Frontend : RTMP
  # Le Streamer est dans public_az_a depuis le deplacement du subnet prive.
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.public_az_a_cidr
    from_port  = 1935
    to_port    = 1935
  }

  # Ports éphémères : indispensable pour le NACL stateless.
  # Quand un client (navigateur, NAT GW...) établit une connexion,
  # le système choisit un port de retour aléatoire entre 1024 et 65535.
  # Sans cette règle, aucun paquet de retour n'entrerait dans le subnet.
  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # ----------------------------------------------------------
  # RÈGLES SORTANTES (egress)
  # ----------------------------------------------------------

  # Frontend → Internet : HTTPS (mises à jour apt, appels API AWS pour SSM)
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Frontend → Internet : HTTP
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Retour des connexions entrantes (réponses aux clients, retour RTMP, etc.)
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${local.name_prefix}-nacl-public"
  }
}

# ============================================================
# NACL PRIVÉ (subnets private_az_a et private_az_b)
# ============================================================
# Ces subnets hébergent : Streamer EC2 (FFmpeg).
# Le Streamer a besoin :
#   - D'accéder à Internet en sortie (via NAT GW) pour mises à jour
#   - De pousser le flux RTMP vers le Frontend en 10.0.1.0/24

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id
  subnet_ids = [
    aws_subnet.private_az_a.id,
    aws_subnet.private_az_b.id,
  ]

  # ----------------------------------------------------------
  # RÈGLES ENTRANTES (inbound)
  # ----------------------------------------------------------

  # Retour du trafic Internet (réponses aux requêtes sortantes via NAT GW).
  # Ex : apt-get update → serveurs Ubuntu → retour via NAT GW → ici.
  # Ce trafic arrive sur des ports éphémères (1024-65535).
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Retour des connexions RTMP depuis le Frontend (ACK TCP, etc.)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.public_az_a_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # ----------------------------------------------------------
  # RÈGLES SORTANTES (egress)
  # ----------------------------------------------------------

  # Streamer → Internet : HTTPS (mises à jour, téléchargements via NAT GW)
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Streamer → Internet : HTTP
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Streamer → Frontend : RTMP (push du flux vidéo)
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.public_az_a_cidr
    from_port  = 1935
    to_port    = 1935
  }

  tags = {
    Name = "${local.name_prefix}-nacl-private"
  }
}

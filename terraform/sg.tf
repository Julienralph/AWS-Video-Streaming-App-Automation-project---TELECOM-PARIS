# ============================================================
# Security Groups
# ============================================================
# Pattern anti-cycle : SGs crees vides, regles ajoutees separement
# via aws_security_group_rule. Casse le cycle de dependances circulaires.
#
# Note: les descriptions de regles n'acceptent que [A-Za-z0-9 _.:/()#,@+=&;{}!$*-]
# Pas d'apostrophes ni de caracteres accentues.

# ============================================================
# Creation des SGs (vides)
# ============================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "SG ALB - accepte HTTPS et HTTP depuis Internet"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-alb" }
}

resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-sg-frontend"
  description = "SG Frontend - trafic ALB et RTMP Streamer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-frontend" }
}

resource "aws_security_group" "streamer" {
  name        = "${local.name_prefix}-sg-streamer"
  description = "SG Streamer FFmpeg - aucun inbound externe"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-streamer" }
}

resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-sg-efs"
  description = "SG EFS Mount Targets - NFS depuis Frontend uniquement"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-efs" }
}

# ============================================================
# Regles ALB
# ============================================================

resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "HTTPS depuis Internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_ingress_http" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  description       = "HTTP depuis Internet - redirection vers HTTPS"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_frontend" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  description              = "Forward HTTP vers les instances Frontend"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
}

# ============================================================
# Regles Frontend
# ============================================================

resource "aws_security_group_rule" "frontend_ingress_alb" {
  security_group_id        = aws_security_group.frontend.id
  type                     = "ingress"
  description              = "HTTP depuis ALB uniquement"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "frontend_ingress_rtmp" {
  security_group_id        = aws_security_group.frontend.id
  type                     = "ingress"
  description              = "RTMP depuis le Streamer"
  from_port                = 1935
  to_port                  = 1935
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.streamer.id
}

resource "aws_security_group_rule" "frontend_egress_efs" {
  security_group_id        = aws_security_group.frontend.id
  type                     = "egress"
  description              = "NFS vers EFS"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.efs.id
}

resource "aws_security_group_rule" "frontend_egress_https" {
  security_group_id = aws_security_group.frontend.id
  type              = "egress"
  description       = "HTTPS vers Internet - SSM apt AWS APIs"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "frontend_egress_http" {
  security_group_id = aws_security_group.frontend.id
  type              = "egress"
  description       = "HTTP vers Internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ============================================================
# Regles Streamer
# ============================================================

resource "aws_security_group_rule" "streamer_egress_rtmp" {
  security_group_id        = aws_security_group.streamer.id
  type                     = "egress"
  description              = "RTMP vers le Frontend"
  from_port                = 1935
  to_port                  = 1935
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
}

resource "aws_security_group_rule" "streamer_egress_https" {
  security_group_id = aws_security_group.streamer.id
  type              = "egress"
  description       = "HTTPS vers Internet via NAT GW"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "streamer_egress_http" {
  security_group_id = aws_security_group.streamer.id
  type              = "egress"
  description       = "HTTP vers Internet via NAT GW"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ============================================================
# Regles EFS
# ============================================================

resource "aws_security_group_rule" "efs_ingress_frontend" {
  security_group_id        = aws_security_group.efs.id
  type                     = "ingress"
  description              = "NFS depuis les instances Frontend"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
}

resource "aws_security_group_rule" "efs_egress_frontend" {
  security_group_id        = aws_security_group.efs.id
  type                     = "egress"
  description              = "NFS vers les instances Frontend"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
}

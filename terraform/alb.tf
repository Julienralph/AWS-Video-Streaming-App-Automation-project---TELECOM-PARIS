# ============================================================
# ALB - Application Load Balancer
# ============================================================
# L'ALB est le seul point d'entrée public de l'application.
# Il reçoit les connexions HTTPS des utilisateurs (via CloudFront),
# termine le SSL (ACM), et forward le trafic en HTTP vers les
# instances Frontend dans l'ASG.
#
# CloudFront → ALB (HTTPS) → Frontend EC2 (HTTP:80)

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false        # Exposé sur Internet (pas interne au VPC)
  load_balancer_type = "application" # ALB = couche 7 (HTTP/HTTPS), pas NLB (couche 4)

  security_groups = [aws_security_group.alb.id]

  # L'ALB doit être dans au moins 2 subnets dans des AZ différentes.
  # Il distribue automatiquement le trafic entre les instances de chaque AZ.
  subnets = [
    aws_subnet.public_az_a.id,
    aws_subnet.public_az_b.id,
  ]

  # Garde les logs d'accès ALB dans S3 si tu veux de l'audit.
  # Désactivé ici pour simplifier (pas de bucket de logs dédié dans l'archi).
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# ============================================================
# Target Group - groupe de destinations du trafic
# ============================================================
# Le Target Group contient les instances Frontend qui reçoivent le trafic.
# L'ASG (asg.tf) s'y enregistre automatiquement à chaque lancement d'instance.
#
# Le health check vérifie que l'instance répond correctement avant
# de lui envoyer du trafic. Une instance qui ne répond pas est
# automatiquement retirée de la rotation.

resource "aws_lb_target_group" "frontend" {
  name     = "${local.name_prefix}-tg-frontend"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port" # Même port que le trafic (80)
    healthy_threshold   = 2              # 2 checks OK → instance saine
    unhealthy_threshold = 3              # 3 checks KO → instance retirée
    timeout             = 5
    interval            = 30
    matcher             = "200-299"      # Codes HTTP acceptés comme "sain"
  }

  tags = {
    Name = "${local.name_prefix}-tg-frontend"
  }
}

# ============================================================
# Listener HTTPS (port 443)
# ============================================================
# Le listener écoute sur un port et applique des règles de routage.
# Ici : tout le trafic HTTPS → Target Group Frontend.
# Le certificat ACM est défini dans acm.tf. Terraform résout la dépendance
# automatiquement (peu importe l'ordre des fichiers).

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # Politique TLS moderne (TLS 1.2 min, TLS 1.3 préféré)
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ============================================================
# Listener HTTP (port 80) → forward vers Target Group
# ============================================================
# CloudFront contacte l'ALB en HTTP (origin_protocol_policy = "http-only").
# Ce listener forward le trafic vers NGINX au lieu de rediriger vers HTTPS.
# La sécurité TLS est assurée par CloudFront côté client (viewer_protocol_policy
# = "redirect-to-https"). Le trafic CloudFront → ALB reste dans le réseau AWS.

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

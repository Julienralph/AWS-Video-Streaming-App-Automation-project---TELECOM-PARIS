# ============================================================
# ASG - Auto Scaling Group Frontend (NGINX + RTMP)
# ============================================================
# L'ASG gère automatiquement le nombre d'instances Frontend.
# Il utilise un Launch Template pour savoir comment créer chaque instance,
# puis ajuste le nombre selon la charge (CPU > 70%).
#
# Flux : Launch Template → ASG → Target Group ALB

# ============================================================
# Launch Template
# ============================================================
# Le Launch Template remplace l'ancien "Launch Configuration".
# Il décrit tout ce qu'AWS a besoin de savoir pour créer une instance :
# AMI, type, SG, profil IAM, disque, user_data.

resource "aws_launch_template" "frontend" {
  name        = "${local.name_prefix}-lt-frontend"
  description = "Template de lancement pour les instances Frontend NGINX+RTMP"

  image_id      = var.ami_id
  instance_type = var.instance_type_frontend

  # Cle SSH temporaire : SSM desactive, Ansible utilise SSH sur instruction du prof.
  key_name = aws_key_pair.gin208.key_name

  vpc_security_group_ids = [aws_security_group.frontend.id]

  # iam_instance_profile {             # desactive : iam:CreateRole non autorise
  #   name = aws_iam_instance_profile.frontend.name
  # }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      delete_on_termination = true
      encrypted             = true
    }
  }

  # templatefile() lit le .tpl et substitue ${efs_id} par l'ID réel de l'EFS.
  # C'est pourquoi on a un fichier .tpl et pas un heredoc inline :
  # le script est lisible et maintenable séparément du code Terraform.
  user_data = base64encode(templatefile("${path.module}/templates/frontend_user_data.sh.tpl", {
    efs_id = aws_efs_file_system.main.id
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-frontend"
      Role = "frontend"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name_prefix}-frontend-vol"
    }
  }
}

# ============================================================
# Auto Scaling Group
# ============================================================
# L'ASG maintient le nombre d'instances entre min et max,
# et les enregistre automatiquement dans le Target Group de l'ALB.

resource "aws_autoscaling_group" "frontend" {
  name = "${local.name_prefix}-asg-frontend"

  # Subnets où lancer les instances : les 2 subnets publics.
  # L'ASG répartit automatiquement entre les AZ pour la haute dispo.
  vpc_zone_identifier = [
    aws_subnet.public_az_a.id,
    aws_subnet.public_az_b.id,
  ]

  desired_capacity = var.asg_desired # 1 par défaut
  min_size         = var.asg_min     # 1 minimum
  max_size         = var.asg_max     # 3 maximum

  # Enregistrement automatique des instances dans le Target Group ALB.
  # Quand une instance démarre → elle rejoint le TG → l'ALB lui envoie du trafic.
  # Quand elle s'arrête → elle quitte le TG → l'ALB arrête de lui envoyer du trafic.
  target_group_arns = [aws_lb_target_group.frontend.arn]

  # L'ASG attend que l'ALB valide le health check avant de considérer
  # une instance comme "saine". Plus fiable que le simple check EC2.
  health_check_type         = "ELB"
  health_check_grace_period = 120 # Secondes laissées à l'instance pour démarrer

  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest" # Toujours utiliser la dernière version du template
  }

  # Propagation des tags aux instances créées par l'ASG
  dynamic "tag" {
    for_each = {
      Name    = "${local.name_prefix}-frontend"
      Role    = "frontend"
      Owner   = "julien-ralph"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# ============================================================
# Politique de scaling : scale-out quand CPU > 70%
# ============================================================
# Cette politique dit à l'ASG de maintenir le CPU moyen des instances
# autour de 70%. Si la charge monte, il ajoute des instances.
# Si elle redescend, il en retire (jusqu'au minimum).
#
# Le seuil 70% est aussi celui de l'alarme CloudWatch (cloudwatch.tf).

resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "${local.name_prefix}-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0 # Maintenir le CPU moyen autour de 70%
  }
}

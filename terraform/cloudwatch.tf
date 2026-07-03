# ============================================================
# CloudWatch - Monitoring, Alarmes et Dashboard
# ============================================================
# CloudWatch est le service de monitoring central d'AWS.
# Dans ce projet, il joue 3 rôles :
#   1. Alarmes : alertes email quand un seuil est dépassé
#   2. Dashboard : vue d'ensemble en temps réel de l'infrastructure
#   3. Logs : déjà configuré dans vpc.tf (Flow Logs) et cloudtrail.tf

# ============================================================
# SNS - Canal de notification
# ============================================================
# SNS (Simple Notification Service) est le bus d'événements qui
# reçoit les alarmes CloudWatch et les envoie par email.

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  tags = {
    Name = "${local.name_prefix}-alerts"
  }
}

# Abonnement email : l'adresse recevra un email de confirmation à créer.
# AWS envoie un mail "Confirm subscription" qu'il faut valider manuellement.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # julien.sangongdjomo@telecom-paris.fr
}

# ============================================================
# Alarme 1 : CPU Frontend > 70%
# ============================================================
# Le scaling automatique (asg.tf) démarre à 70%, mais il faut aussi
# un humain dans la boucle. Cette alarme envoie un email pour indiquer
# que le système est sous pression et que le scaling est en cours.

resource "aws_cloudwatch_metric_alarm" "frontend_cpu_high" {
  alarm_name          = "${local.name_prefix}-frontend-cpu-high"
  alarm_description   = "CPU Frontend > 70% - scaling en cours"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2       # 2 périodes consécutives avant de déclencher
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120     # Période de 2 minutes
  statistic           = "Average"
  threshold           = 70.0
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.frontend.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn] # Notification aussi quand ça revient à la normale
}

# ============================================================
# Alarme 2 : Erreurs HTTP 5xx sur l'ALB
# ============================================================
# Les erreurs 5xx (500, 502, 503...) indiquent que le Frontend plante
# ou est surchargé. Une seule erreur 5xx peut arriver ; on alerte
# seulement si elles se cumulent (> 10 en 5 minutes).

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  alarm_description   = "Plus de 10 erreurs HTTP 5xx en 5 minutes sur l'ALB"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ============================================================
# Alarme 3 : Latence ALB > 1 seconde
# ============================================================
# Si le temps de réponse moyen dépasse 1 seconde, l'expérience
# de streaming devient dégradée (buffering, latence HLS visible).

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-latency-high"
  alarm_description   = "Latence ALB > 1s en moyenne sur 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1.0 # 1 seconde
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ============================================================
# Dashboard CloudWatch
# ============================================================
# Vue d'ensemble de l'infrastructure en un seul écran.
# Le dashboard utilise du JSON pour décrire la disposition des widgets.

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # CPU Frontend (ASG)
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "CPU Frontend (ASG)"
          region = var.aws_region
          metrics = [[
            "AWS/EC2", "CPUUtilization",
            "AutoScalingGroupName", aws_autoscaling_group.frontend.name,
            { stat = "Average", period = 60, color = "#ff7f0e" }
          ]]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ value = 70, color = "#d62728", label = "Seuil scaling" }]
          }
        }
      },
      # Erreurs 5xx ALB
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Erreurs HTTP 5xx (ALB)"
          region = var.aws_region
          metrics = [[
            "AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
            "LoadBalancer", aws_lb.main.arn_suffix,
            { stat = "Sum", period = 60, color = "#d62728" }
          ]]
        }
      },
      # Latence ALB
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Latence ALB (secondes)"
          region = var.aws_region
          metrics = [[
            "AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.main.arn_suffix,
            { stat = "Average", period = 60, color = "#1f77b4" }
          ]]
          annotations = {
            horizontal = [{ value = 1, color = "#d62728", label = "Seuil 1s" }]
          }
        }
      },
      # Nombre de requêtes ALB
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Requêtes ALB (total)"
          region = var.aws_region
          metrics = [[
            "AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", aws_lb.main.arn_suffix,
            { stat = "Sum", period = 60, color = "#2ca02c" }
          ]]
        }
      }
    ]
  })
}

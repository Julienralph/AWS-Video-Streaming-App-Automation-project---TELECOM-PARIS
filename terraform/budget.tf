# ============================================================
# AWS Budget - Alerte de coût à 20$
# ============================================================
# Un Budget surveille les dépenses réelles et prévisionnelles du compte.
# Ici on alerte à 80% du seuil (16$) ET à 100% (20$).
# Utile sur un compte partagé avec d'autres étudiants : évite les
# mauvaises surprises si une ressource tourne sans qu'on s'en rende compte.

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-budget-20usd"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY" # Remis à zéro le 1er de chaque mois

  # Alerte à 80% du budget (16$) : avertissement précoce
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"   # Coût réel, pas prévisionnel
    subscriber_email_addresses = [var.alert_email]
  }

  # Alerte à 100% du budget (20$) : seuil atteint
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # Alerte si la prévision de fin de mois dépasse 20$
  # Permet d'agir avant d'atteindre le seuil réel.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Apagado/encendido programado de los nodos (solo cuando está habilitado)
resource "aws_autoscaling_schedule" "shutdown" {
  for_each = var.enable_offhours_shutdown ? toset(var.node_group_asg_names) : toset([])

  scheduled_action_name  = "${var.name}-shutdown"
  autoscaling_group_name = each.value
  recurrence             = var.shutdown_cron_utc
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
}

resource "aws_autoscaling_schedule" "startup" {
  for_each = var.enable_offhours_shutdown ? toset(var.node_group_asg_names) : toset([])

  scheduled_action_name  = "${var.name}-startup"
  autoscaling_group_name = each.value
  recurrence             = var.startup_cron_utc
  min_size               = var.startup_min_size
  max_size               = var.startup_max_size
  desired_capacity       = var.startup_desired_size
}

# Alerta de presupuesto mensual
resource "aws_budgets_budget" "monthly" {
  count = length(var.budget_alert_emails) > 0 ? 1 : 0

  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [join("$", ["user:Environment", var.environment])]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}

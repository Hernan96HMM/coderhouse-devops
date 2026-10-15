variable "name" {
  type = string
}

variable "environment" {
  description = "Entorno, usado para filtrar costos por tag Environment"
  type        = string
}

variable "node_group_asg_names" {
  type = list(string)
}

variable "enable_offhours_shutdown" {
  type = bool
}

variable "shutdown_cron_utc" {
  type = string
}

variable "startup_cron_utc" {
  type = string
}

variable "startup_min_size" {
  type = number
}

variable "startup_desired_size" {
  type = number
}

variable "startup_max_size" {
  type = number
}

variable "monthly_budget_usd" {
  type = number
}

variable "budget_alert_emails" {
  type = list(string)
}

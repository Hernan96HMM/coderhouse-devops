variable "project" {
  description = "Nombre del proyecto (prefijo de recursos y tag)"
  type        = string
  default     = "pf-devops"
}

variable "environment" {
  description = "Entorno: dev o prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser dev o prod."
  }
}

variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Usar un único NAT Gateway (más barato, menos disponibilidad)"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes del cluster EKS"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Tipos de instancia del node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND o SPOT"
  type        = string
  default     = "SPOT"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs que pueden acceder al endpoint público del API. Restringir a tu IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------- FinOps ----------
variable "enable_offhours_shutdown" {
  description = "Escalar el node group a 0 fuera de horario (solo recomendado en dev)"
  type        = bool
  default     = false
}

variable "shutdown_cron_utc" {
  description = "Cron (UTC) de apagado. Por defecto 22:00 hora Argentina (01:00 UTC), lun-vie"
  type        = string
  default     = "0 1 * * 2-6"
}

variable "startup_cron_utc" {
  description = "Cron (UTC) de encendido. Por defecto 08:00 hora Argentina (11:00 UTC), lun-vie"
  type        = string
  default     = "0 11 * * 1-5"
}

variable "monthly_budget_usd" {
  description = "Presupuesto mensual en USD para alertas de costo"
  type        = number
  default     = 50
}

variable "budget_alert_emails" {
  description = "Emails que reciben alertas de presupuesto"
  type        = list(string)
  default     = []
}

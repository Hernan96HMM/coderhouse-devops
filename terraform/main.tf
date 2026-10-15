provider "aws" {
  region = var.region

  # Tags de FinOps aplicados a TODOS los recursos
  default_tags {
    tags = local.tags
  }
}

locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = "pf-devops"
  }
}

module "network" {
  source = "./modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "cluster" {
  source = "./modules/cluster"

  name                        = local.name
  kubernetes_version          = var.kubernetes_version
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  node_instance_types         = var.node_instance_types
  node_capacity_type          = var.node_capacity_type
  node_min_size               = var.node_min_size
  node_desired_size           = var.node_desired_size
  node_max_size               = var.node_max_size
  cluster_public_access_cidrs = var.cluster_public_access_cidrs
}

module "finops" {
  source = "./modules/finops"

  name                     = local.name
  environment              = var.environment
  node_group_asg_names     = module.cluster.node_group_asg_names
  enable_offhours_shutdown = var.enable_offhours_shutdown
  shutdown_cron_utc        = var.shutdown_cron_utc
  startup_cron_utc         = var.startup_cron_utc
  startup_min_size         = var.node_min_size
  startup_desired_size     = var.node_desired_size
  startup_max_size         = var.node_max_size
  monthly_budget_usd       = var.monthly_budget_usd
  budget_alert_emails      = var.budget_alert_emails
}

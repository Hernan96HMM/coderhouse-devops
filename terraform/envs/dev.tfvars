environment = "dev"
region      = "us-east-1"

# Costos: spot + un solo NAT + apagado fuera de horario
node_capacity_type       = "SPOT"
node_instance_types      = ["t3.medium", "t3a.medium"]
node_min_size            = 1
node_desired_size        = 2
node_max_size            = 3
single_nat_gateway       = true
enable_offhours_shutdown = true
monthly_budget_usd       = 40

# Reemplazar por tu IP pública (curl ifconfig.me) + /32
cluster_public_access_cidrs = ["0.0.0.0/0"]

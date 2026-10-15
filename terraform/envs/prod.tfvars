environment = "prod"
region      = "us-east-1"

node_capacity_type       = "ON_DEMAND"
node_instance_types      = ["t3.medium"]
node_min_size            = 2
node_desired_size        = 2
node_max_size            = 6
single_nat_gateway       = false
enable_offhours_shutdown = false
monthly_budget_usd       = 150

cluster_public_access_cidrs = ["0.0.0.0/0"]

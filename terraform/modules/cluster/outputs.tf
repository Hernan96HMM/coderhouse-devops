output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "node_group_asg_names" {
  description = "Nombres de los Auto Scaling Groups de los node groups"
  value = flatten([
    for ng in module.eks.eks_managed_node_groups : ng.node_group_autoscaling_group_names
  ])
}

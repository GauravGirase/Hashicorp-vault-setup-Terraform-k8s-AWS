output "cluster_id" {
  value = aws_eks_cluster.vault.id
}

output "node_group_id" {
  value = aws_eks_node_group.vault.id
}

output "vpc_id" {
  value = aws_vpc.vault_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.vault_subnet[*].id
}

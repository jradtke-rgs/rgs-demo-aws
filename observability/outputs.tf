output "instance_id" {
  description = "ID of the Observability node EC2 instance"
  value       = aws_instance.observability.id
}

output "public_ip" {
  description = "Public IP address of the Observability node"
  value       = var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip
}

output "observability_hostname" {
  description = "Hostname reserved for the Observability node/cluster"
  value       = local.observability_fqdn
}

output "observability_url" {
  description = "URL for RGS Observability (not live until the cluster is registered via 'rgsctl register' and the product Helm chart is installed - see README.md)"
  value       = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "https://${var.hostname_observability}.${var.subdomain}.${var.root_domain}" : "https://${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to the node"
  value       = var.ssh_public_key != "" ? "ssh -i ~/.ssh/rgs-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip}" : "Use AWS Systems Manager Session Manager to connect"
}

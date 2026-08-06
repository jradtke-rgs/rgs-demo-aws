output "instance_id" {
  description = "ID of the user-apps node EC2 instance"
  value       = aws_instance.security.id
}

output "public_ip" {
  description = "Public IP address of the user-apps node"
  value       = var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip
}

output "userapps_hostname" {
  description = "Hostname reserved for the user-apps node/cluster"
  value       = local.userapps_fqdn
}

output "userapps_url" {
  description = "URL for the user-apps cluster hosting the RGS Security demo (not live until the cluster is registered via 'rgsctl register' and workloads/RGS Security are deployed - see README.md)"
  value       = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "https://${var.hostname_userapps}.${var.subdomain}.${var.root_domain}" : "https://${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to the node"
  value       = var.ssh_public_key != "" ? "ssh -i ~/.ssh/rgs-demo-aws.pem ec2-user@${var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip}" : "Use AWS Systems Manager Session Manager to connect"
}

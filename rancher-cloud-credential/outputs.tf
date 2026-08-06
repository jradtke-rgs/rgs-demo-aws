output "access_key_id" {
  description = "AWS access key ID - paste into Rancher's Cloud Credential form (Cluster Management -> Cloud Credentials -> Create -> Amazon)"
  value       = aws_iam_access_key.rancher_cloud_credential.id
}

output "secret_access_key" {
  description = "AWS secret access key - paste into Rancher's Cloud Credential form alongside access_key_id"
  value       = aws_iam_access_key.rancher_cloud_credential.secret
  sensitive   = true
}

output "iam_user_name" {
  description = "Name of the IAM user this credential belongs to"
  value       = aws_iam_user.rancher_cloud_credential.name
}

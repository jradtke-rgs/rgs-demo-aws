output "eks_driver_role_arn" {
  description = "ARN of the IAM role with permissions for the Rancher EKS driver"
  value       = aws_iam_role.eks_driver.arn
}

output "eks_driver_policy_arn" {
  description = "ARN of the IAM policy attached to the EKS driver role"
  value       = aws_iam_policy.eks_driver.arn
}

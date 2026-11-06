output "jenkins_public_ip" {
  description = "Static public IPv4 address of the Jenkins server."
  value       = aws_eip.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins UI URL; accessible only from admin_cidrs."
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "eks_cluster_name" {
  description = "EKS cluster name for Jenkins and kubectl."
  value       = aws_eks_cluster.main.name
}

output "ecr_repository_name" {
  description = "ECR repository name used by the pipeline."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "Full ECR repository URI."
  value       = aws_ecr_repository.app.repository_url
}

output "artifact_bucket_name" {
  description = "Private S3 bucket used to store Jenkins build metadata."
  value       = aws_s3_bucket.artifacts.bucket
}

output "aws_region" {
  description = "Region containing this deployment."
  value       = var.aws_region
}

output "jenkins_ssh_command" {
  description = "SSH command template for accessing the Jenkins EC2 instance."
  value       = "ssh -i <path-to-private-key> ubuntu@${aws_eip.jenkins.public_ip}"
}

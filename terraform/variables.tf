variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short prefix for resources created by this project."
  type        = string
  default     = "ai-automation"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Use 3-20 lowercase letters, digits, or hyphens; start with a letter."
  }
}

variable "domain_name" {
  description = "Root domain hosted in the public Route 53 zone used for the portfolio application."
  type        = string
  default     = "ishaqkohire.site"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in aws_region, used for Jenkins SSH access."
  type        = string
  default     = "terraform.keys"
}

variable "admin_cidrs" {
  description = "Trusted public IPv4 CIDRs allowed to SSH to Jenkins, open Jenkins, and access the public EKS API."
  type        = list(string)

  validation {
    condition = length(var.admin_cidrs) > 0 && alltrue([
      for cidr in var.admin_cidrs :
      can(cidrhost(cidr, 0)) &&
      can(tonumber(split("/", cidr)[1])) &&
      tonumber(split("/", cidr)[1]) >= 16
    ])
    error_message = "Provide at least one valid IPv4 CIDR with a /16 or narrower range, such as your public IP/32."
  }
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins controller."
  type        = string
  default     = "t3.small"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for the EKS managed node group."
  type        = string
  default     = "t3.small"
}

variable "eks_cluster_version" {
  description = "Kubernetes version supported by EKS in the selected region."
  type        = string
  default     = "1.35"
}

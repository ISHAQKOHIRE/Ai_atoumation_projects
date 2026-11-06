# AI Automation Portfolio on AWS

A Flask portfolio site built as a Docker image, stored in Amazon ECR, and deployed to Amazon EKS by a Jenkins pipeline. Terraform provisions the AWS infrastructure and Jenkins EC2 controller.

This project currently serves the site over **HTTP using the Kubernetes LoadBalancer hostname**. ACM certificates, HTTPS, and custom-domain DNS updates are intentionally not part of this deployment.

## Architecture

- Terraform provisions a VPC, public/private subnets, internet and NAT gateways, security groups, and an EKS cluster with a managed node group.
- Terraform provisions a Jenkins EC2 instance with an Elastic IP, IAM instance profile, and access to the EKS API.
- Jenkins checks out this repository, builds the Docker image, pushes a unique immutable tag to ECR, deploys it to EKS, and archives build metadata in a private S3 bucket.
- Kubernetes exposes the web app with a `LoadBalancer` service on port 80. The application health endpoint is `/health`.

## Costs and security

**This is not a free-tier deployment.** EKS, EC2, EBS, NAT Gateway, public IPv4 addresses, load balancers, storage, and data transfer can incur ongoing charges. Check current AWS pricing and set a budget before provisioning. Delete the Kubernetes LoadBalancer service and run Terraform destroy when you are finished.

Jenkins is served over HTTP on port 8080 and is reachable only from the CIDRs in `admin_cidrs`. Use your trusted public IP as a `/32`; do not use `0.0.0.0/0`. The EKS public API is also restricted to those CIDRs. The Jenkins instance uses its IAM role instead of stored AWS access keys. That role has cluster-admin access in this learning setup; do not copy this design into production without replacing it with narrowly scoped permissions and hardening Jenkins.

Never commit `terraform.tfvars`, Terraform state, AWS credentials, private SSH keys, Jenkins secrets, or generated logs. The Terraform directory's `.gitignore` excludes local state and variable files.

## Prerequisites

- An AWS account and an identity authorized to create the resources defined in `terraform/`
- AWS CLI v2, Terraform 1.5+, and Git
- An EC2 key pair already created in the target AWS region
- A trusted public IPv4 address/CIDR for administrative access
- A GitHub repository accessible by the Jenkins controller
- Docker Desktop is only needed if you want to build/test the image locally; Jenkins builds it on the EC2 instance

## 1. Configure and provision AWS

From the repository root, create the local Terraform variables file:

```powershell
Set-Location .\terraform
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit `terraform.tfvars`:

- Set `key_name` to your existing EC2 key pair name.
- Replace `admin_cidrs` with your current trusted IP, such as `["203.0.113.10/32"]`. The example address is reserved for documentation and will not work.
- Keep this file local; it is ignored by Git.

Select the AWS profile you intend to use and confirm the account:

```powershell
$env:AWS_PROFILE = "terraform"
aws sts get-caller-identity
```

Initialize and review the infrastructure:

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Review the full plan, especially resource deletions or replacements, before applying:

```powershell
terraform apply
```

This HTTP-only version no longer manages ACM certificates or Route 53 records. If upgrading a workspace that previously managed those resources, Terraform may propose deleting them; inspect the plan carefully and proceed only if that is intended.

## 2. Open and initialize Jenkins

Get the Jenkins URL and instance IP from Terraform:

```powershell
terraform output -raw jenkins_url
terraform output -raw jenkins_public_ip
```

Open the Jenkins URL from a network whose public IP is included in `admin_cidrs`. Allow a few minutes after the first apply for the Jenkins instance bootstrap to finish.

If Jenkins requests its initial unlock password, connect to the instance using the matching private key:

```powershell
ssh -i C:\path\to\your-private-key ubuntu@<jenkins-public-ip>
```

Then retrieve the password on the instance:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Complete Jenkins' setup wizard and install the suggested plugins, including Pipeline and Git. Do not put AWS access keys in Jenkins; the EC2 instance profile provides AWS credentials.

## 3. Create a Jenkins pipeline job

1. In Jenkins, select **New Item**, enter a job name, choose **Pipeline**, and create the job.
2. In the job configuration, set **Definition** to **Pipeline script from SCM** and choose **Git**.
3. Enter this repository URL: `https://github.com/ISHAQKOHIRE/Ai_atoumation_projects.git`.
4. Set the branch to `*/master` and the script path to `Jenkinsfile`. If the repository is private, configure a GitHub access credential in Jenkins; never put a token in the `Jenkinsfile`.
5. Save the job. The Jenkinsfile defines the build parameters. If needed, run the job once to load the Jenkinsfile and then choose **Build with Parameters**.

Get the parameter values in another PowerShell window from the Terraform directory:

```powershell
terraform output -raw aws_region
terraform output -raw eks_cluster_name
terraform output -raw ecr_repository_name
terraform output -raw artifact_bucket_name
```

Provide those values as `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY`, and `S3_BUCKET` when starting the build.

## 4. Deploy and verify the site

The pipeline builds and pushes a uniquely tagged image, applies the namespace, deployment, and HTTP LoadBalancer service, waits for the rollout and `/health` endpoint, then stores build metadata in S3 and Jenkins artifacts.

The pipeline log and archived `deployment-url.txt` show the HTTP URL. You can also inspect the deployment from your computer:

```powershell
aws eks update-kubeconfig --region ap-south-1 --name ai-automation-eks
kubectl get nodes
kubectl get pods --namespace portfolio
kubectl get service ai-automation-web --namespace portfolio
```

Wait for the service's `EXTERNAL-IP` to show an AWS load-balancer hostname, then visit `http://<load-balancer-hostname>`. To test the health endpoint:

```powershell
Invoke-WebRequest "http://<load-balancer-hostname>/health" -UseBasicParsing
```

The load balancer hostname is the active website address. `ishaqkohire.site` is not configured by this Terraform setup; custom-domain routing and HTTPS require additional DNS and certificate configuration.

## Troubleshooting

- **Jenkins URL times out:** Confirm Jenkins finished installing and the current public IP is listed in `admin_cidrs`. After changing `terraform.tfvars`, review and apply the Terraform plan.
- **Jenkins cannot connect to EKS:** Check that the EKS public API CIDR includes the current trusted IP, that Jenkins can reach the cluster, and that the Jenkins IAM role's EKS access entry exists.
- **ECR `AccessDenied`:** Verify Jenkins uses its EC2 instance profile and that the Terraform-managed ECR push policy is attached.
- **Pod is `ImagePullBackOff`:** Inspect `kubectl describe pod` and verify the image tag exists in ECR. The EKS node role needs ECR pull access.
- **LoadBalancer has no hostname:** Check `kubectl describe service ai-automation-web -n portfolio` and recent Kubernetes events. Provisioning can take several minutes.
- **Deployment health check fails:** Inspect `kubectl logs deployment/ai-automation-web -n portfolio` and verify the `/health` readiness probe.

## Local development

From the repository root:

```powershell
python -m pip install -r .\app\requirements.txt
python .\app\app.py
```

Visit `http://localhost:5000/`. The health endpoint is `http://localhost:5000/health`.

To build and run the container locally:

```powershell
docker build -t ai-automation-web .
docker run --rm -p 5000:5000 ai-automation-web
```

## Tear down

Delete the Kubernetes LoadBalancer service first so AWS can clean up its load balancer:

```powershell
kubectl delete service ai-automation-web --namespace portfolio
```

Then, from `terraform/`, review and destroy the Terraform-managed infrastructure:

```powershell
terraform plan -destroy
terraform destroy
```

The S3 bucket has versioning enabled. If it contains build metadata, Terraform may refuse to delete it until all object versions are deliberately removed. Review its contents before cleanup; do not delete Terraform state unless you no longer need it.

## Repository layout

```text
app/                 Flask application and HTML template
k8s/                 Namespace, deployment, and HTTP service manifests
terraform/           AWS infrastructure and local Terraform configuration
Dockerfile           Container image definition
Jenkinsfile          Build, push, deploy, health-check, and archive pipeline
```

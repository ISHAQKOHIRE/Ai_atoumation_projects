# AI Automation Projects - AWS DevOps Portfolio

A portfolio-ready starter project that builds a small web application into a Docker image and deploys it to Amazon EKS with Jenkins.

## What this project provisions

- A dedicated VPC with public and private subnets across availability zones
- An EC2 Jenkins server with an Elastic IP, reachable only from the CIDRs you allow
- An Amazon EKS cluster with a small managed node group
- A single NAT Gateway for private-node outbound access
- An ACM DNS-validated certificate for the root domain and `www` subdomain, used for HTTPS at the Kubernetes load balancer
- An Amazon ECR repository for application images
- A private, encrypted, versioned S3 bucket for build metadata
- A Flask portfolio page, Docker image, Kubernetes manifests, and Jenkins pipeline

After a successful Jenkins deployment, the pipeline updates the Route 53 apex (`ishaqkohire.site`) and `www` records to point to the Kubernetes load balancer.

## Important: cost and security

**This is not a free-tier architecture.** EKS cluster-hours, EC2, EBS, NAT Gateway hours and data processing, public IPv4 addresses, load balancers, data transfer, and S3 can incur ongoing charges. A running EKS cluster alone has a substantial hourly charge. Review current AWS pricing, set an AWS Budget, and run `terraform destroy` when you no longer want the environment. Nothing is deployed until you run Terraform.

The worker nodes run in private subnets and use one NAT Gateway for outbound access. A single NAT keeps this learning setup simpler and cheaper than one per availability zone, but it is a single point of failure; production systems should use resilient networking, VPC endpoints where appropriate, HTTPS with a domain, least-privilege Kubernetes access, and a hardened Jenkins design.

SSH, Jenkins, and the EKS public API are limited to `admin_cidrs`. Supply your trusted public IP range as a `/32` (or your office/VPN CIDR); do not use `0.0.0.0/0`. Jenkins reaches the private EKS API through a dedicated security group attached to the control plane. Jenkins has cluster-admin access in this learning template so the pipeline can deploy Kubernetes resources. Restrict that access before using this design for production.

## Prerequisites

- An AWS account and credentials with permission to create the resources in `terraform/`
- Terraform 1.5 or later
- An SSH key pair already created in the chosen AWS region
- A trusted public IPv4 CIDR for administration
- The domain `ishaqkohire.site` and access to change its nameservers at the registrar
- Git and Docker are useful for local development; Jenkins builds the image in AWS

## 1. Configure and provision AWS

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `key_name` to your existing AWS EC2 key pair name and replace the example `admin_cidrs` entry with your public IP in CIDR notation, for example `198.51.100.25/32`. The example address is reserved for documentation and will not grant access.

The current project defaults are configured for the Mumbai region (`ap-south-1`) and the existing EC2 key pair name `terraform.keys`. Confirm that this key pair exists in your AWS account in Mumbai. Keep `terraform.tfvars` local; it is excluded from Git so your trusted IP range is not published.

Terraform uses the existing public Route 53 hosted zone for `ishaqkohire.site`; it does not create another hosted zone. The zone must be authoritative for the domain and available to Terraform so it can create ACM DNS validation records. After a successful deployment, Jenkins UPSERTs apex and `www` A-alias records to the EKS load balancer, replacing any existing records at those names. ACM terminates HTTPS at the load balancer; the load balancer forwards HTTP to the application. HTTP remains available and is not automatically redirected to HTTPS.

The AWS account ID is detected from the credentials used by Terraform and does not need to be added to the configuration. Verify that your AWS CLI is using the intended account before provisioning:

```powershell
aws sts get-caller-identity
```

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Terraform outputs the Jenkins URL and initial SSH connection details, cluster name, ECR repository, S3 bucket, and validated ACM certificate ARN. Keep the Terraform state private: it contains infrastructure details and may contain sensitive values.

## 2. Finish Jenkins setup

1. Open the `jenkins_url` Terraform output from a network included in `admin_cidrs`.
2. SSH to `ubuntu@<jenkins_public_ip>` using the matching private key.
3. Read the initial Jenkins password with:

   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

4. Complete Jenkins' setup wizard and install the suggested plugins, including **Pipeline**.
5. Create a Pipeline job pointing at this repository and set its script path to `Jenkinsfile`.
6. Add the Jenkins EC2 instance profile's IAM role as the job's AWS identity; **do not** add long-lived AWS access keys. The instance profile, ECR, and EKS access are created by Terraform.
7. When running the job, provide the `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY`, `S3_BUCKET`, `DOMAIN_NAME`, `ROUTE53_ZONE_ID`, and `ACM_CERTIFICATE_ARN` parameters from Terraform outputs.

The EC2 user-data script installs Jenkins, Java, Docker, AWS CLI v2, and a `kubectl` version matching the configured EKS Kubernetes minor version. Allow a few minutes after `terraform apply` for first-boot installation to finish. Jenkins is reachable at `http://<jenkins_public_ip>:8080` only from a CIDR in `admin_cidrs`. If that URL does not open, check that your current public IP is included in `terraform/terraform.tfvars`, then run `terraform plan` and `terraform apply` to update the Jenkins security group.

## 3. Deploy the application

Run the Jenkins job. It builds and tags the image with the Jenkins build number, pushes it to ECR, applies the Kubernetes manifests, waits for rollout, and uploads build metadata to S3.

The Jenkins pipeline waits for the Kubernetes load balancer, then updates Route 53 A-alias records for the root domain and `www` to point to it. Open `https://ishaqkohire.site` or `https://www.ishaqkohire.site` after the pipeline succeeds. HTTP is also available without a redirect. DNS changes can take time to propagate. To inspect the service and its hostname:

```bash
aws eks update-kubeconfig --region <aws-region> --name <eks-cluster-name>
kubectl get service ai-automation-web --namespace portfolio
```

Provisioning the load balancer can take several minutes. The domain points to the app only after the Jenkins pipeline succeeds; the Jenkins EC2 IP is not the website address. The endpoint remains available only while the AWS resources are running and billable.

## Troubleshooting

- **`kubectl` TLS handshake timeout:** The EKS public API and Jenkins security group are restricted to `admin_cidrs`. Set it to the public IP of the network you are currently using as a `/32`, then review and apply the Terraform plan. Do not open access to `0.0.0.0/0`.
- **Jenkins page times out:** Check the EC2 console output or SSH to the instance and inspect `sudo tail -n 100 /var/log/cloud-init-output.log`. The bootstrap installs the current Jenkins repository signing key and Java 21. Updating EC2 user data does not automatically rerun cloud-init on an already-created instance; repair that host over SSH or deliberately replace it after reviewing the Terraform plan.

## Local application development

```bash
python -m pip install -r app/requirements.txt
python app/app.py
```

Visit `http://localhost:5000/`; the health check is at `/health`.

Build and run the container locally:

```bash
docker build -t ai-automation-web .
docker run --rm -p 5000:5000 ai-automation-web
```

## Tear down

Delete the Kubernetes `LoadBalancer` service before destroying the cluster, to let AWS clean up its load balancer:

```bash
kubectl delete service ai-automation-web --namespace portfolio
```

Then, from `terraform/`, run:

```powershell
terraform destroy
```

The S3 bucket intentionally has versioning enabled. If it contains build metadata, Terraform may report that the bucket is not empty during destroy. Review and remove its objects and versions deliberately, then retry. Do not delete the bucket or Terraform state without confirming you no longer need its contents.

## Repository layout

```text
app/                 Flask application
k8s/                 Namespace, deployment, and service manifests
terraform/           AWS infrastructure
Dockerfile           Container image definition
Jenkinsfile          Build, push, deploy, and archive pipeline
```

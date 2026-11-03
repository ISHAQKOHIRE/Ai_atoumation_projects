pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'AWS_REGION', defaultValue: '', description: 'Terraform aws_region output')
        string(name: 'EKS_CLUSTER_NAME', defaultValue: '', description: 'Terraform eks_cluster_name output')
        string(name: 'ECR_REPOSITORY', defaultValue: '', description: 'Terraform ecr_repository_name output')
        string(name: 'S3_BUCKET', defaultValue: '', description: 'Terraform artifact_bucket_name output')
        string(name: 'DOMAIN_NAME', defaultValue: 'ishaqkohire.site', description: 'Terraform domain_name output')
        string(name: 'ROUTE53_ZONE_ID', defaultValue: '', description: 'Terraform route53_zone_id output')
    }

    environment {
        K8S_NAMESPACE = 'portfolio'
        K8S_DEPLOYMENT = 'ai-automation-web'
    }

    stages {
        stage('Validate inputs') {
            steps {
                script {
                    if (!params.AWS_REGION?.trim() ||
                        !params.EKS_CLUSTER_NAME?.trim() ||
                        !params.ECR_REPOSITORY?.trim() ||
                        !params.S3_BUCKET?.trim() ||
                        !params.DOMAIN_NAME?.trim() ||
                        !params.ROUTE53_ZONE_ID?.trim()) {
                        error('Set AWS_REGION, EKS_CLUSTER_NAME, ECR_REPOSITORY, S3_BUCKET, DOMAIN_NAME, and ROUTE53_ZONE_ID from Terraform outputs.')
                    }
                }
            }
        }

        stage('Build and push image') {
            steps {
                sh '''
                    set -eu
                    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                    REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${BUILD_NUMBER}"
                    trap 'docker logout "$REGISTRY" >/dev/null 2>&1 || true' EXIT
                    aws ecr get-login-password --region "$AWS_REGION" |
                      docker login --username AWS --password-stdin "$REGISTRY"
                    docker build --pull --tag "$IMAGE_URI" .
                    docker push "$IMAGE_URI"
                    printf '%s' "$IMAGE_URI" > image-uri.txt
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    set -eu
                    IMAGE_URI=$(cat image-uri.txt)
                    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
                    kubectl apply -f k8s/namespace.yaml
                    sed "s|IMAGE_PLACEHOLDER|${IMAGE_URI}|g" k8s/deployment.yaml |
                      kubectl apply -f -
                    kubectl apply -f k8s/service.yaml
                    kubectl rollout status "deployment/${K8S_DEPLOYMENT}" \
                      --namespace "$K8S_NAMESPACE" --timeout=5m
                '''
            }
        }

        stage('Point domain to application') {
            steps {
                sh '''
                    set -eu
                    LB_DNS=""
                    for attempt in $(seq 1 60); do
                      LB_DNS=$(kubectl get service ai-automation-web \
                        --namespace "$K8S_NAMESPACE" \
                        --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
                      if [ -n "$LB_DNS" ]; then
                        break
                      fi
                      echo "Waiting for the Kubernetes load balancer (${attempt}/60)..."
                      sleep 10
                    done
                    if [ -z "$LB_DNS" ]; then
                      echo "The service has no load-balancer hostname yet." >&2
                      kubectl describe service ai-automation-web --namespace "$K8S_NAMESPACE"
                      exit 1
                    fi

                    LB_ZONE_ID=$(aws elbv2 describe-load-balancers \
                      --query "LoadBalancers[?DNSName=='${LB_DNS}'].CanonicalHostedZoneId | [0]" \
                      --output text 2>/dev/null || true)
                    if [ -z "$LB_ZONE_ID" ] || [ "$LB_ZONE_ID" = "None" ]; then
                      LB_ZONE_ID=$(aws elb describe-load-balancers \
                        --query "LoadBalancerDescriptions[?DNSName=='${LB_DNS}'].CanonicalHostedZoneNameID | [0]" \
                        --output text)
                    fi
                    if [ -z "$LB_ZONE_ID" ] || [ "$LB_ZONE_ID" = "None" ]; then
                      echo "Could not find the AWS hosted-zone ID for load balancer ${LB_DNS}." >&2
                      exit 1
                    fi

                    cat > route53-change.json <<EOF
{
  "Comment": "Point ${DOMAIN_NAME} portfolio records to the EKS service",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN_NAME}.",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LB_ZONE_ID}",
          "DNSName": "dualstack.${LB_DNS}",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.${DOMAIN_NAME}.",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LB_ZONE_ID}",
          "DNSName": "dualstack.${LB_DNS}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
                    aws route53 change-resource-record-sets \
                      --hosted-zone-id "$ROUTE53_ZONE_ID" \
                      --change-batch file://route53-change.json
                    echo "Configured ${DOMAIN_NAME} and www.${DOMAIN_NAME} to ${LB_DNS}"
                '''
            }
        }

        stage('Archive build metadata') {
            steps {
                sh '''
                    set -eu
                    IMAGE_URI=$(cat image-uri.txt)
                    printf 'build=%s\\ncommit=%s\\nimage=%s\\n' \
                      "$BUILD_NUMBER" "$GIT_COMMIT" "$IMAGE_URI" > build-info.txt
                    aws s3 cp build-info.txt \
                      "s3://${S3_BUCKET}/builds/${JOB_NAME}/${BUILD_NUMBER}/build-info.txt"
                '''
                archiveArtifacts artifacts: 'build-info.txt', fingerprint: true
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}

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
                        !params.S3_BUCKET?.trim()) {
                        error('Set AWS_REGION, EKS_CLUSTER_NAME, ECR_REPOSITORY, and S3_BUCKET from Terraform outputs.')
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
                    IMAGE_TAG="${BUILD_NUMBER}-${BUILD_ID}-$(git rev-parse --short=12 HEAD)"
                    IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
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
                    printf 'http://%s\n' "$LB_DNS" > deployment-url.txt
                    for attempt in $(seq 1 12); do
                      if curl --fail --silent --show-error "http://${LB_DNS}/health"; then
                        break
                      fi
                      if [ "$attempt" -eq 12 ]; then
                        echo "Application health check did not succeed at http://${LB_DNS}/health." >&2
                        exit 1
                      fi
                      sleep 10
                    done
                    cat deployment-url.txt
                '''
            }
        }

        stage('Archive build metadata') {
            steps {
                sh '''
                    set -eu
                    IMAGE_URI=$(cat image-uri.txt)
                    COMMIT_SHA=$(git rev-parse HEAD)
                    printf 'build=%s\\ncommit=%s\\nimage=%s\\n' \
                      "$BUILD_NUMBER" "$COMMIT_SHA" "$IMAGE_URI" > build-info.txt
                    aws s3 cp build-info.txt \
                      "s3://${S3_BUCKET}/builds/${JOB_NAME}/${BUILD_NUMBER}/build-info.txt"
                '''
                archiveArtifacts artifacts: 'build-info.txt,deployment-url.txt', fingerprint: true
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}

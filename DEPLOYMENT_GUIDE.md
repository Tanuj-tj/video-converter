# ECS Fargate Deployment Guide

## Prerequisites

1. **AWS CLI configured**
2. **Docker installed**
3. **GitLab repository setup**

## Quick Deployment

### Option 1: Automated Script
```bash
./deploy-ecs.sh
```

### Option 2: Manual Steps

#### 1. Create ECR Repository
```bash
aws ecr create-repository --repository-name video-converter
```

#### 2. Build and Push Image
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

docker build -t video-converter .
docker tag video-converter:latest $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/video-converter:latest
docker push $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/video-converter:latest
```

#### 3. Create ECS Cluster
```bash
aws ecs create-cluster --cluster-name video-converter-cluster --capacity-providers FARGATE
```

#### 4. Register Task Definition
```bash
# Update ecs-task-definition.json with your account ID
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json
```

#### 5. Create ECS Service
```bash
# Update ecs-service.json with your VPC/subnet/security group IDs
aws ecs create-service --cli-input-json file://ecs-service.json
```

## GitLab CI/CD Setup

### 1. Set GitLab Variables
Go to GitLab Project → Settings → CI/CD → Variables:

- `AWS_ACCESS_KEY_ID`: Your AWS access key
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
- `AWS_ACCOUNT_ID`: Your AWS account ID

### 2. Push to GitLab
```bash
git add .
git commit -m "Add ECS deployment"
git push origin main
```

### 3. Pipeline Stages
- **Build**: Creates Docker image and pushes to ECR
- **Deploy**: Updates ECS service with new image

## Architecture

```
Internet → ALB → ECS Fargate Tasks → S3/SQS/Lambda
```

## Components Created

### AWS Resources
- **ECR Repository**: Container registry
- **ECS Cluster**: Fargate cluster
- **ECS Service**: Auto-scaling service (2 tasks)
- **Application Load Balancer**: Traffic distribution
- **Target Group**: Health checks
- **Security Group**: Network access
- **IAM Roles**: Task execution and permissions
- **CloudWatch Logs**: Application logging
- **Parameter Store**: Environment secrets

### Configuration Files
- `Dockerfile`: Container definition
- `.gitlab-ci.yml`: CI/CD pipeline
- `ecs-task-definition.json`: Task configuration
- `ecs-service.json`: Service configuration
- `deploy-ecs.sh`: Automated deployment

## Scaling Configuration

### Auto Scaling
```bash
# Create auto scaling target
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id service/video-converter-cluster/video-converter-service \
    --min-capacity 1 \
    --max-capacity 10

# Create scaling policy
aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id service/video-converter-cluster/video-converter-service \
    --policy-name cpu-scaling \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

## Monitoring

### CloudWatch Metrics
- CPU utilization
- Memory utilization
- Request count
- Response time

### Logs
```bash
aws logs tail /ecs/video-converter --follow
```

## Cost Optimization

### Fargate Pricing
- **CPU**: $0.04048 per vCPU per hour
- **Memory**: $0.004445 per GB per hour

### Example Cost (2 tasks, 0.5 vCPU, 1GB RAM)
- Monthly: ~$60
- With auto-scaling: $30-120/month

## Security

### Network Security
- ALB in public subnets
- ECS tasks in private subnets (if using NAT Gateway)
- Security groups restrict access

### IAM Security
- Least privilege roles
- Separate execution and task roles
- Parameter Store for secrets

## Troubleshooting

### Common Issues

#### Task Fails to Start
```bash
aws ecs describe-tasks --cluster video-converter-cluster --tasks TASK_ID
```

#### Health Check Failures
- Check `/health` endpoint
- Verify security group allows port 8000
- Check CloudWatch logs

#### Image Pull Errors
- Verify ECR permissions
- Check image exists in ECR

### Useful Commands
```bash
# Check service status
aws ecs describe-services --cluster video-converter-cluster --services video-converter-service

# View task logs
aws logs tail /ecs/video-converter --follow

# Scale service
aws ecs update-service --cluster video-converter-cluster --service video-converter-service --desired-count 3

# Force new deployment
aws ecs update-service --cluster video-converter-cluster --service video-converter-service --force-new-deployment
```

## Cleanup

```bash
# Delete service
aws ecs update-service --cluster video-converter-cluster --service video-converter-service --desired-count 0
aws ecs delete-service --cluster video-converter-cluster --service video-converter-service

# Delete cluster
aws ecs delete-cluster --cluster video-converter-cluster

# Delete load balancer
aws elbv2 delete-load-balancer --load-balancer-arn ALB_ARN

# Delete ECR repository
aws ecr delete-repository --repository-name video-converter --force
```
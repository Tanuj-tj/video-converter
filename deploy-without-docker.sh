#!/bin/bash

# ECS Fargate Deployment Script (Without Docker Build)

set -e

# Configuration
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="video-converter"
ECS_CLUSTER="video-converter-cluster"
ECS_SERVICE="video-converter-service"
TASK_DEFINITION="video-converter-task"

echo "Deploying Video Converter to ECS Fargate (Infrastructure Only)..."
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"

# 1. Create ECR repository
echo "Creating ECR repository..."
aws ecr create-repository --repository-name $ECR_REPOSITORY --region $AWS_REGION || echo "Repository already exists"

# 2. Create ECS cluster
echo "Creating ECS cluster..."
aws ecs create-cluster --cluster-name $ECS_CLUSTER --capacity-providers FARGATE --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

# 3. Create CloudWatch log group
echo "Creating CloudWatch log group..."
aws logs create-log-group --log-group-name "/ecs/video-converter" --region $AWS_REGION || echo "Log group already exists"

# 4. Create IAM roles
echo "Creating IAM roles..."

# ECS Task Execution Role
cat > ecs-task-execution-role.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document file://ecs-task-execution-role.json || echo "Role already exists"
aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# ECS Task Role
cat > ecs-task-role.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name VideoConverterTaskRole --assume-role-policy-document file://ecs-task-role.json || echo "Role already exists"
aws iam attach-role-policy --role-name VideoConverterTaskRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name VideoConverterTaskRole --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess

# 5. Store secrets in Parameter Store
echo "Storing secrets in Parameter Store..."
aws ssm put-parameter --name "/video-converter/upload-bucket" --value "$(grep UPLOAD_BUCKET .env | cut -d'=' -f2)" --type "String" --overwrite
aws ssm put-parameter --name "/video-converter/converted-bucket" --value "$(grep CONVERTED_BUCKET .env | cut -d'=' -f2)" --type "String" --overwrite
aws ssm put-parameter --name "/video-converter/sqs-queue-url" --value "$(grep SQS_QUEUE_URL .env | cut -d'=' -f2)" --type "String" --overwrite

# 6. Get default VPC and subnets
echo "Getting VPC information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text)
SUBNET1=$(echo $SUBNET_IDS | cut -d' ' -f1)
SUBNET2=$(echo $SUBNET_IDS | cut -d' ' -f2)

# 7. Create security group
echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group --group-name video-converter-sg --description "Security group for video converter" --vpc-id $VPC_ID --query 'GroupId' --output text) || \
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=video-converter-sg" --query 'SecurityGroups[0].GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8000 --cidr 0.0.0.0/0 || echo "Rule already exists"

# 8. Create Application Load Balancer
echo "Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name video-converter-alb \
    --subnets $SUBNET1 $SUBNET2 \
    --security-groups $SG_ID \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text) || \
ALB_ARN=$(aws elbv2 describe-load-balancers --names video-converter-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# 9. Create target group
echo "Creating target group..."
TG_ARN=$(aws elbv2 create-target-group \
    --name video-converter-tg \
    --protocol HTTP \
    --port 8000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /health \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text) || \
TG_ARN=$(aws elbv2 describe-target-groups --names video-converter-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# 10. Create listener
echo "Creating ALB listener..."
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN || echo "Listener already exists"

# 11. Update task definition with actual values
echo "Updating task definition..."
sed -i.bak "s/ACCOUNT_ID/$ACCOUNT_ID/g" ecs-task-definition.json

# 12. Register task definition
echo "Registering task definition..."
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json

# 13. Update service configuration
echo "Updating service configuration..."
sed -i.bak "s/subnet-12345678/$SUBNET1/g; s/subnet-87654321/$SUBNET2/g; s/sg-12345678/$SG_ID/g; s|arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:targetgroup/video-converter-tg/1234567890123456|$TG_ARN|g; s/ACCOUNT_ID/$ACCOUNT_ID/g" ecs-service.json

# 14. Create ECS service
echo "Creating ECS service..."
aws ecs create-service --cli-input-json file://ecs-service.json || echo "Service already exists"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)

# Cleanup
rm -f ecs-task-execution-role.json ecs-task-role.json ecs-task-definition.json.bak ecs-service.json.bak

echo "Infrastructure deployment completed successfully!"
echo ""
echo "Resources created:"
echo "- ECR Repository: $ECR_REPOSITORY"
echo "- ECS Cluster: $ECS_CLUSTER"
echo "- ECS Service: $ECS_SERVICE"
echo "- Load Balancer DNS: $ALB_DNS"
echo ""
echo "Next steps:"
echo "1. Install Docker: https://docs.docker.com/desktop/install/mac-install/"
echo "2. Push code to GitHub to trigger automated build and deployment"
echo "3. Or manually build and push:"
echo "   docker build -t $ECR_REPOSITORY ."
echo "   aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
echo "   docker tag $ECR_REPOSITORY:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest"
echo "   docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest"
# GitHub Setup and Deployment Guide

## Step 1: Push Local Project to GitHub

### 1. Create GitHub Repository
1. Go to [GitHub](https://github.com)
2. Click "New repository"
3. Name: `video-converter`
4. Keep it public or private
5. Don't initialize with README (we have files already)
6. Click "Create repository"

### 2. Initialize Git and Push
```bash
cd /Users/tanujshrivastava/Desktop/AI/Video_conversion

# Initialize git repository
git init

# Add all files
git add .

# Commit files
git commit -m "Initial commit: Video converter with ECS deployment"

# Add GitHub remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/video-converter.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Step 2: Setup GitHub Actions Secrets

### 1. Go to Repository Settings
1. Navigate to your repository on GitHub
2. Click "Settings" tab
3. Click "Secrets and variables" → "Actions"

### 2. Add Required Secrets
Click "New repository secret" for each:

- **Name**: `AWS_ACCESS_KEY_ID`
  **Value**: Your AWS access key ID

- **Name**: `AWS_SECRET_ACCESS_KEY`
  **Value**: Your AWS secret access key

- **Name**: `AWS_ACCOUNT_ID` (optional)
  **Value**: Your 12-digit AWS account ID

## Step 3: Deploy Infrastructure

### Option 1: Run Deployment Script
```bash
./deploy-ecs.sh
```

### Option 2: Manual AWS Setup
```bash
# Create ECR repository
aws ecr create-repository --repository-name video-converter

# Create ECS cluster
aws ecs create-cluster --cluster-name video-converter-cluster --capacity-providers FARGATE

# Register task definition (update account ID first)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i.bak "s/ACCOUNT_ID/$ACCOUNT_ID/g" ecs-task-definition.json
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json

# Create service (update VPC/subnet/SG IDs first)
aws ecs create-service --cli-input-json file://ecs-service.json
```

## Step 4: Trigger Deployment

### Push Changes to Trigger Pipeline
```bash
# Make any change
echo "# Video Converter" > README.md
git add README.md
git commit -m "Add README"
git push origin main
```

### Monitor Deployment
1. Go to GitHub repository
2. Click "Actions" tab
3. Watch the deployment progress

## Step 5: Access Application

### Get Load Balancer URL
```bash
aws elbv2 describe-load-balancers --names video-converter-alb --query 'LoadBalancers[0].DNSName' --output text
```

### Test Application
Open the ALB DNS name in browser: `http://your-alb-dns-name`

## GitHub Actions Workflow

The workflow automatically:
1. **Builds** Docker image on every push to main
2. **Pushes** image to ECR
3. **Updates** ECS task definition
4. **Deploys** to ECS service
5. **Waits** for deployment stability

## Troubleshooting

### Common Issues

#### 1. AWS Credentials Error
- Verify secrets are set correctly in GitHub
- Check AWS permissions

#### 2. ECR Repository Not Found
```bash
aws ecr create-repository --repository-name video-converter
```

#### 3. ECS Service Not Found
Run the deployment script first:
```bash
./deploy-ecs.sh
```

#### 4. Task Definition Not Found
```bash
aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json
```

### Useful Commands
```bash
# Check workflow status
gh run list

# View logs
gh run view --log

# Check ECS service
aws ecs describe-services --cluster video-converter-cluster --services video-converter-service
```

## Next Steps

1. **Custom Domain**: Add Route 53 and SSL certificate
2. **Monitoring**: Setup CloudWatch alarms
3. **Auto Scaling**: Configure based on metrics
4. **Security**: Use private subnets with NAT Gateway
# Complete Setup Guide

## Quick Setup (Recommended)

1. **Configure AWS CLI**
```bash
aws configure
```

2. **Run automated setup**
```bash
./aws_setup.sh
./ffmpeg_layer_setup.sh
```

3. **Install and run**
```bash
pip install -r requirements.txt
python run.py
```

4. **Access application**
Open `http://localhost:8000`

## Manual Setup

### 1. Create AWS Resources

```bash
# S3 buckets
aws s3 mb s3://video-upload-bucket-$(date +%s)
aws s3 mb s3://video-converted-bucket-$(date +%s)

# SQS queue
aws sqs create-queue --queue-name video-conversion-queue
```

### 2. IAM Role

```bash
# Create trust policy
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role --role-name VideoConverterLambdaRole --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy --role-name VideoConverterLambdaRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name VideoConverterLambdaRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name VideoConverterLambdaRole --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
```

### 3. Lambda Function

```bash
# Create deployment package
zip lambda-function.zip lambda_function.py

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name VideoConverterLambdaRole --query 'Role.Arn' --output text)

# Create function
aws lambda create-function \
    --function-name video-converter \
    --runtime python3.9 \
    --role $ROLE_ARN \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda-function.zip \
    --timeout 300 \
    --memory-size 1024
```

### 4. FFmpeg Layer

```bash
# Create layer structure
mkdir -p ffmpeg-layer/bin
cd ffmpeg-layer/bin

# Download FFmpeg
wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
tar -xf ffmpeg-release-amd64-static.tar.xz --strip-components=1
rm ffmpeg-release-amd64-static.tar.xz

cd ../..

# Create and upload layer
cd ffmpeg-layer && zip -r ../ffmpeg-layer.zip . && cd ..
LAYER_ARN=$(aws lambda publish-layer-version --layer-name ffmpeg --zip-file fileb://ffmpeg-layer.zip --query 'LayerArn' --output text)

# Attach to function
aws lambda update-function-configuration --function-name video-converter --layers $LAYER_ARN
```

### 5. SQS Trigger

```bash
# Get queue ARN
QUEUE_URL=$(aws sqs get-queue-url --queue-name video-conversion-queue --query 'QueueUrl' --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

# Create trigger
aws lambda create-event-source-mapping \
    --event-source-arn $QUEUE_ARN \
    --function-name video-converter \
    --batch-size 1
```

### 6. Environment Configuration

```bash
# Copy and edit environment file
cp .env.example .env
# Update .env with your bucket names and queue URL
```

## Usage

1. **Start the server**
```bash
python run.py
```

2. **Access the web interface**
Open `http://localhost:8000`

3. **Upload and convert videos**
- Select video file
- Choose conversion formats (4K, 1080p, 720p, 480p)
- Click "Upload & Convert"
- Monitor status and download converted files

## API Endpoints

- `POST /upload` - Upload video and queue conversion jobs
- `GET /status/{job_id}` - Check conversion status  
- `GET /download/{job_id}/{format}` - Get presigned download URL

## Troubleshooting

### Lambda Timeout
- Increase timeout (max 15 minutes)
- Use smaller test videos

### FFmpeg Not Found
- Verify layer is attached to Lambda function
- Check FFmpeg path in lambda_function.py

### Permission Errors
- Ensure IAM role has all required policies
- Check S3 bucket permissions

### SQS Not Triggering
- Verify event source mapping is active
- Check Lambda logs in CloudWatch

## Cost Optimization

- Use appropriate Lambda memory allocation
- Set S3 lifecycle policies for old videos
- Monitor usage with AWS Cost Explorer
- Consider using S3 Intelligent Tiering

## Security Best Practices

- Use least privilege IAM policies
- Enable S3 bucket encryption
- Set up VPC endpoints for private communication
- Enable CloudTrail for audit logging
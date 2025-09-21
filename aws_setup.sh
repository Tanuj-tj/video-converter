#!/bin/bash

# AWS Video Processing Setup Script
# Make sure AWS CLI is configured with appropriate credentials

set -e

# Configuration
UPLOAD_BUCKET="video-upload-bucket-$(date +%s)"
CONVERTED_BUCKET="video-converted-bucket-$(date +%s)"
QUEUE_NAME="video-conversion-queue"
LAMBDA_FUNCTION_NAME="video-converter"
ROLE_NAME="VideoConverterLambdaRole"

echo "Setting up AWS resources for video processing..."

#1. Create S3 buckets
echo "Creating S3 buckets..."
REGION=$(aws configure get region)
if [ "$REGION" = "us-east-1" ]; then
    aws s3 mb s3://$UPLOAD_BUCKET
    aws s3 mb s3://$CONVERTED_BUCKET
else
    aws s3 mb s3://$UPLOAD_BUCKET --region $REGION
    aws s3 mb s3://$CONVERTED_BUCKET --region $REGION
fi

# 2. Create SQS queue
echo "Creating SQS queue..."
QUEUE_URL=$(aws sqs create-queue --queue-name $QUEUE_NAME --query 'QueueUrl' --output text)
echo "Queue URL: $QUEUE_URL"

# Set queue visibility timeout to match Lambda timeout
echo "Configuring queue visibility timeout..."
aws sqs set-queue-attributes --queue-url $QUEUE_URL --attributes VisibilityTimeoutSeconds=900

# 3. Create IAM role for Lambda
echo "Creating IAM role..."
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

aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json

# 4. Attach policies to role
echo "Attaching policies to role..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess

# 5. Get role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"

# 6. Create Lambda deployment package
echo "Creating Lambda deployment package..."
zip lambda-function.zip lambda_function.py

# Wait for role to be available
echo "Waiting for IAM role to be available..."
sleep 10

# 7. Create Lambda function
echo "Creating Lambda function..."
aws lambda create-function \
    --function-name $LAMBDA_FUNCTION_NAME \
    --runtime python3.9 \
    --role $ROLE_ARN \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda-function.zip \
    --timeout 300 \
    --memory-size 1024

# 8. Create SQS trigger for Lambda
echo "Creating SQS trigger for Lambda..."
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

aws lambda create-event-source-mapping \
    --event-source-arn $QUEUE_ARN \
    --function-name $LAMBDA_FUNCTION_NAME \
    --batch-size 1

# 9. Create .env file
echo "Creating .env file..."
cat > .env << EOF
AWS_REGION=$(aws configure get region)
UPLOAD_BUCKET=$UPLOAD_BUCKET
CONVERTED_BUCKET=$CONVERTED_BUCKET
SQS_QUEUE_URL=$QUEUE_URL
EOF

# Cleanup
rm trust-policy.json lambda-function.zip

echo "Setup completed successfully!"
echo ""
echo "Resources created:"
echo "- Upload bucket: $UPLOAD_BUCKET"
echo "- Converted bucket: $CONVERTED_BUCKET"
echo "- SQS queue: $QUEUE_URL"
echo "- Lambda function: $LAMBDA_FUNCTION_NAME"
echo "- IAM role: $ROLE_NAME"
echo ""
echo "Next steps:"
echo "1. Create FFmpeg Lambda layer (see README.md)"
echo "2. Attach the layer to your Lambda function"
echo "3. Install Python dependencies: pip install -r requirements.txt"
echo "4. Run the FastAPI server: python main.py"
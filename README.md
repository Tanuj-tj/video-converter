# Video Processing Application

## Project Architecture

```mermaid
graph TD
    A[User Browser] -->|1. Upload Video + Formats| B[Application Load Balancer]
    B -->|Route Traffic| C[ECS Fargate Tasks]
    C -->|2. Store Video| D[S3 Upload Bucket]
    C -->|3. Queue Jobs| E[SQS Queue]
    E -->|4. Trigger| F[Lambda Function]
    F -->|5. Download Video| D
    F -->|6. Convert with FFmpeg| G[FFmpeg Layer]
    F -->|7. Upload Converted| H[S3 Converted Bucket]
    C -->|8. Check Status| H
    C -->|9. Generate Download URL| H
    A -->|10. Download Videos| H
    
    subgraph "AWS Services"
        D
        E
        F
        G
        H
    end
    
    subgraph "ECS Fargate"
        C
    end
```

## Components Flow:
1. User uploads video via web UI and selects conversion formats
2. FastAPI receives upload, stores in S3, sends conversion job to SQS
3. SQS triggers Lambda function for each conversion format
4. Lambda downloads video, converts using FFmpeg, uploads back to S3
5. User can check conversion status via FastAPI endpoint

## UI
![alt text](image.png)

## Setup Instructions

### 1. AWS S3 Buckets
```bash
# Create buckets (replace with unique names)
aws s3 mb s3://video-upload-bucket-unique
aws s3 mb s3://video-converted-bucket-unique
```

### 2. AWS SQS Queue
```bash
aws sqs create-queue --queue-name video-conversion-queue
```

### 3. IAM Role for Lambda
Create role with policies:
- AmazonS3FullAccess
- AmazonSQSFullAccess
- AWSLambdaBasicExecutionRole

### 4. Lambda Layer for FFmpeg
Download FFmpeg static build and create layer:
```bash
mkdir ffmpeg-layer/bin
# Download FFmpeg static binary to ffmpeg-layer/bin/
zip -r ffmpeg-layer.zip ffmpeg-layer/
aws lambda publish-layer-version --layer-name ffmpeg --zip-file fileb://ffmpeg-layer.zip
```

### 5. Environment Variables
Set in Lambda and FastAPI:
- UPLOAD_BUCKET=video-upload-bucket-unique
- CONVERTED_BUCKET=video-converted-bucket-unique
- SQS_QUEUE_URL=your-sqs-queue-url
#!/bin/bash

# FFmpeg Lambda Layer Setup Script

set -e

echo "Setting up FFmpeg Lambda layer..."

# Create layer directory structure
mkdir -p ffmpeg-layer/bin

# Download FFmpeg static build
echo "Downloading FFmpeg static build..."
cd ffmpeg-layer/bin
curl -L -o ffmpeg-release-amd64-static.tar.xz https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
tar -xf ffmpeg-release-amd64-static.tar.xz --strip-components=1
rm ffmpeg-release-amd64-static.tar.xz

# Keep only ffmpeg binary
mv ffmpeg-*-amd64-static/ffmpeg .
mv ffmpeg-*-amd64-static/ffprobe .
rm -rf ffmpeg-*-amd64-static

cd ../..

# Create layer zip
echo "Creating layer zip file..."
cd ffmpeg-layer
zip -r ../ffmpeg-layer.zip .
cd ..

# Upload layer to AWS Lambda
echo "Uploading layer to AWS Lambda..."
LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name ffmpeg \
    --zip-file fileb://ffmpeg-layer.zip \
    --compatible-runtimes python3.9 \
    --query 'LayerArn' \
    --output text)

echo "Layer created with ARN: $LAYER_ARN"

# Get Lambda function name from environment or use default
LAMBDA_FUNCTION_NAME=${1:-"video-converter"}

# Attach layer to Lambda function
echo "Attaching layer to Lambda function..."
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --layers $LAYER_ARN

# Cleanup
rm -rf ffmpeg-layer ffmpeg-layer.zip

echo "FFmpeg layer setup completed successfully!"
echo "Layer ARN: $LAYER_ARN"
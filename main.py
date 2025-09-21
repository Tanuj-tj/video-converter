import os
import json
import uuid
from typing import List
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Video Conversion API")

# AWS Configuration
UPLOAD_BUCKET = os.getenv("UPLOAD_BUCKET", "video-upload-bucket-unique")
CONVERTED_BUCKET = os.getenv("CONVERTED_BUCKET", "video-converted-bucket-unique")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# AWS Clients
s3_client = boto3.client('s3', region_name=AWS_REGION)
sqs_client = boto3.client('sqs', region_name=AWS_REGION)

# Serve static files
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.get("/", response_class=HTMLResponse)
async def read_root():
    with open("static/index.html", "r") as f:
        return HTMLResponse(content=f.read())

@app.post("/upload")
async def upload_video(
    file: UploadFile = File(...),
    formats: str = Form(...)
):
    """Upload video and queue conversion jobs"""
    
    # Validate file type
    if not file.content_type.startswith('video/'):
        raise HTTPException(status_code=400, detail="File must be a video")
    
    # Generate unique job ID
    job_id = str(uuid.uuid4())
    file_key = f"{job_id}/{file.filename}"
    
    try:
        # Upload to S3
        file_content = await file.read()
        s3_client.put_object(
            Bucket=UPLOAD_BUCKET,
            Key=file_key,
            Body=file_content,
            ContentType=file.content_type
        )
        
        # Parse requested formats
        format_list = json.loads(formats)
        
        # Send conversion jobs to SQS
        for format_type in format_list:
            message = {
                "job_id": job_id,
                "input_bucket": UPLOAD_BUCKET,
                "input_key": file_key,
                "output_bucket": CONVERTED_BUCKET,
                "format": format_type,
                "filename": file.filename
            }
            
            sqs_client.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(message)
            )
        
        return {
            "job_id": job_id,
            "message": "Video uploaded and conversion jobs queued",
            "formats": format_list
        }
        
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"AWS error: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")

@app.get("/status/{job_id}")
async def check_status(job_id: str):
    """Check conversion status for a job"""
    
    try:
        # List objects in converted bucket with job_id prefix
        response = s3_client.list_objects_v2(
            Bucket=CONVERTED_BUCKET,
            Prefix=f"{job_id}/"
        )
        
        converted_files = []
        if 'Contents' in response:
            for obj in response['Contents']:
                # Extract format from filename
                key = obj['Key']
                if key.endswith('.mp4'):
                    format_type = key.split('_')[-1].replace('.mp4', '')
                    converted_files.append({
                        "format": format_type,
                        "key": key,
                        "size": obj['Size'],
                        "last_modified": obj['LastModified'].isoformat()
                    })
        
        return {
            "job_id": job_id,
            "converted_files": converted_files,
            "total_converted": len(converted_files)
        }
        
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"AWS error: {str(e)}")

@app.get("/download/{job_id}/{format_type}")
async def get_download_url(job_id: str, format_type: str):
    """Generate presigned URL for downloading converted video"""
    
    try:
        # Find the file key
        response = s3_client.list_objects_v2(
            Bucket=CONVERTED_BUCKET,
            Prefix=f"{job_id}/"
        )
        
        file_key = None
        if 'Contents' in response:
            for obj in response['Contents']:
                if f"_{format_type}.mp4" in obj['Key']:
                    file_key = obj['Key']
                    break
        
        if not file_key:
            raise HTTPException(status_code=404, detail="Converted file not found")
        
        # Generate presigned URL
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': CONVERTED_BUCKET, 'Key': file_key},
            ExpiresIn=3600  # 1 hour
        )
        
        return {"download_url": url}
        
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"AWS error: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
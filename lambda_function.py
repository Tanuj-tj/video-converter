import json
import boto3
import subprocess
import os
import tempfile
from urllib.parse import unquote_plus

# AWS clients
s3_client = boto3.client('s3')

# Resolution configurations
RESOLUTIONS = {
    '4k': '3840x2160',
    '1080p': '1920x1080',
    '720p': '1280x720',
    '480p': '854x480'
}

def lambda_handler(event, context):
    """Lambda function to process video conversion"""
    
    try:
        # Parse SQS message
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            job_id = message_body['job_id']
            input_bucket = message_body['input_bucket']
            input_key = message_body['input_key']
            output_bucket = message_body['output_bucket']
            format_type = message_body['format']
            filename = message_body['filename']
            
            print(f"Processing job {job_id} for format {format_type}")
            
            # Create temporary directories
            with tempfile.TemporaryDirectory() as temp_dir:
                input_path = os.path.join(temp_dir, 'input_video')
                output_path = os.path.join(temp_dir, f'output_{format_type}.mp4')
                
                # Download video from S3
                print(f"Downloading {input_key} from {input_bucket}")
                s3_client.download_file(input_bucket, input_key, input_path)
                
                # Convert video using FFmpeg
                resolution = RESOLUTIONS.get(format_type, '1280x720')
                convert_video(input_path, output_path, resolution)
                
                # Upload converted video to S3
                base_filename = os.path.splitext(filename)[0]
                output_key = f"{job_id}/{base_filename}_{format_type}.mp4"
                
                print(f"Uploading {output_key} to {output_bucket}")
                s3_client.upload_file(output_path, output_bucket, output_key)
                
                print(f"Successfully processed {job_id} for format {format_type}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Video conversion completed successfully')
        }
        
    except Exception as e:
        print(f"Error processing video: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def convert_video(input_path, output_path, resolution):
    """Convert video to specified resolution using FFmpeg"""
    
    # FFmpeg command for video conversion
    cmd = [
        '/opt/bin/ffmpeg',  # Path to FFmpeg in Lambda layer
        '-i', input_path,
        '-vf', f'scale={resolution}',
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        '-y',  # Overwrite output file
        output_path
    ]
    
    print(f"Running FFmpeg command: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )
        
        if result.returncode != 0:
            print(f"FFmpeg stderr: {result.stderr}")
            raise Exception(f"FFmpeg conversion failed: {result.stderr}")
        
        print("Video conversion completed successfully")
        
    except subprocess.TimeoutExpired:
        raise Exception("Video conversion timed out")
    except Exception as e:
        raise Exception(f"Video conversion failed: {str(e)}")
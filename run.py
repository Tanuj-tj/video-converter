#!/usr/bin/env python3

import uvicorn
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

if __name__ == "__main__":
    # Check if required environment variables are set
    required_vars = ["UPLOAD_BUCKET", "CONVERTED_BUCKET", "SQS_QUEUE_URL"]
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        print("Error: Missing required environment variables:")
        for var in missing_vars:
            print(f"  - {var}")
        print("\nPlease create a .env file with the required variables.")
        print("See .env.example for reference.")
        exit(1)
    
    print("Starting Video Conversion API server...")
    print(f"Upload bucket: {os.getenv('UPLOAD_BUCKET')}")
    print(f"Converted bucket: {os.getenv('CONVERTED_BUCKET')}")
    print("Server will be available at: http://localhost:8000")
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )
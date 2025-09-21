# Setup Issues Fix

## Issue 1: AWS Credentials

Configure AWS CLI with your credentials:

```bash
aws configure
```

Enter:
- AWS Access Key ID
- AWS Secret Access Key  
- Default region (e.g., us-east-1)
- Default output format (json)

Or set environment variables:
```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-east-1
```

## Issue 2: wget not found on macOS

Install wget using Homebrew:
```bash
brew install wget
```

Or use curl instead (already installed on macOS)
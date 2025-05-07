#!/bin/bash

# Exit on any error
set -e

# CONFIGURATION - change these!
APP_NAME="new-app"                              ##NEEDS TO BE CHANGED##
AWS_REGION="us-east-1"                          ##NEEDS TO BE CHANGED##

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
ECR_URI="$REGISTRY_URI/$APP_NAME"

echo "==> Installing Docker and AWS CLI (if needed)"
if ! command -v docker &> /dev/null; then
  sudo yum update -y
  sudo amazon-linux-extras install docker -y
  sudo service docker start
  sudo usermod -a -G docker ec2-user
  newgrp docker
fi

if ! command -v aws &> /dev/null; then
  sudo yum install -y aws-cli
fi

echo "==> Creating app directory"
mkdir -p ~/app && cd ~/app
mkdir application 
echo "==> Writing app.py"
cat <<EOF > app.py
from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello from ECR Docker Image!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

echo "==> Writing requirements.txt"
echo "flask" > requirements.txt

echo "==> Writing Dockerfile"
cat <<EOF > Dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 5000
CMD ["python", "app.py"]
EOF

echo "==> Building Docker image"
sudo docker build -t $APP_NAME .

echo "==> Authenticating Docker to ECR"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

echo "==> Creating ECR repository (if not exists)"
aws ecr describe-repositories --repository-names $APP_NAME --region $AWS_REGION 2>/dev/null || \
aws ecr create-repository --repository-name $APP_NAME --region $AWS_REGION

echo "==> Tagging Docker image"
sudo docker tag $APP_NAME:latest $ECR_URI:latest

echo "==> Pushing image to ECR"
sudo docker push $ECR_URI:latest

echo "==> Running container on port 5000"
sudo docker run -d -p 5000:5000 $ECR_URI:latest

echo "✅ Deployment complete!"
echo "Access your app via: http://<your-EC2-public-IP>:5000"


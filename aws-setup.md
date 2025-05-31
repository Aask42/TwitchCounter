# AWS Deployment Guide with AWS CLI

This guide will walk you through deploying the Twitch Word Counter on an AWS EC2 free tier instance using the AWS CLI and configuring a Namecheap domain with Dynamic DNS (DDNS).

## Prerequisites

- AWS account eligible for free tier
- Namecheap domain
- AWS CLI installed and configured on your local machine
- Git installed on your local machine

## Step 1: Install and Configure AWS CLI

If you haven't already installed the AWS CLI, follow these steps:

### For macOS:
```bash
brew install awscli
```

### For Linux:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### For Windows:
Download and run the installer from: https://aws.amazon.com/cli/

### Configure AWS CLI:
```bash
aws configure
```
Enter your AWS Access Key ID, Secret Access Key, default region (e.g., us-east-1), and output format (json).

## Step 2: Create Key Pair for SSH Access

```bash
aws ec2 create-key-pair --key-name TwitchCounterKey --query 'KeyMaterial' --output text > TwitchCounterKey.pem
chmod 400 TwitchCounterKey.pem
```

## Step 3: Create Security Group

```bash
# Create security group
aws ec2 create-security-group --group-name TwitchCounterSG --description "Security group for Twitch Counter application"

# Get your public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Add rules to security group
aws ec2 authorize-security-group-ingress --group-name TwitchCounterSG --protocol tcp --port 22 --cidr $MY_IP/32
aws ec2 authorize-security-group-ingress --group-name TwitchCounterSG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name TwitchCounterSG --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name TwitchCounterSG --protocol tcp --port 8080 --cidr 0.0.0.0/0
```

## Step 4: Launch EC2 Instance

```bash
# Get the latest Amazon Linux 2023 AMI ID
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --count 1 \
  --instance-type t2.micro \
  --key-name TwitchCounterKey \
  --security-groups TwitchCounterSG \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=TwitchCounter}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Launched instance: $INSTANCE_ID"

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public DNS name
PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "Instance is running at: $PUBLIC_DNS"
echo "Public IP: $PUBLIC_IP"
```

## Step 5: Create and Upload Setup Script

Create a file named `setup.sh` with the following content:

```bash
#!/bin/bash

# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Nginx
sudo yum install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Install ddclient for DDNS
sudo yum install -y ddclient

# Clone the repository
git clone https://github.com/Aask42/TwitchCounter.git
cd TwitchCounter

# Create .env file
cp .env.example .env

# Create Nginx configuration
sudo tee /etc/nginx/conf.d/twitch-counter.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Test and reload Nginx
sudo nginx -t
sudo systemctl reload nginx

echo "Setup completed!"
```

Upload the script to your EC2 instance:

```bash
# Wait a bit for the instance to initialize
sleep 30

# Upload setup script
scp -i TwitchCounterKey.pem setup.sh ec2-user@$PUBLIC_DNS:~/setup.sh

# Make the script executable
ssh -i TwitchCounterKey.pem ec2-user@$PUBLIC_DNS "chmod +x ~/setup.sh"

# Run the setup script
ssh -i TwitchCounterKey.pem ec2-user@$PUBLIC_DNS "~/setup.sh"
```

## Step 6: Configure the Application

Connect to your instance and configure the application:

```bash
ssh -i TwitchCounterKey.pem ec2-user@$PUBLIC_DNS
```

Once connected:

1. Edit the .env file:
   ```bash
   cd TwitchCounter
   nano .env
   ```

2. Update with your configuration:
   ```
   TWITCH_CHANNEL=skittishandbus
   TARGET_WORDS=fuck,shit,damn
   ```
   Save and exit (Ctrl+X, then Y, then Enter)

3. Update the Nginx configuration with your domain:
   ```bash
   sudo sed -i 's/DOMAIN_PLACEHOLDER/your-domain.com www.your-domain.com/g' /etc/nginx/conf.d/twitch-counter.conf
   sudo nginx -t
   sudo systemctl reload nginx
   ```
   Replace `your-domain.com` with your actual domain.

## Step 7: Configure Namecheap DDNS

1. Log in to your Namecheap account
2. Go to "Domain List" and select your domain
3. Click "Manage"
4. Navigate to "Advanced DNS"
5. Enable Dynamic DNS:
   - Toggle "Dynamic DNS" to ON
   - Note your Dynamic DNS Password

6. Configure ddclient on your EC2 instance:
   ```bash
   sudo nano /etc/ddclient.conf
   ```

7. Add the following configuration:
   ```
   daemon=600
   use=web, web=checkip.dyndns.org/, web-skip='IP Address'
   protocol=namecheap
   server=dynamicdns.park-your-domain.com
   login=your-domain.com
   password=your-dynamic-dns-password
   @,www
   ```
   Replace `your-domain.com` with your actual domain and `your-dynamic-dns-password` with the password from step 5.

8. Start and enable ddclient:
   ```bash
   sudo systemctl start ddclient
   sudo systemctl enable ddclient
   ```

## Step 8: Run the Application

Start the application using Docker Compose:

```bash
cd ~/TwitchCounter
docker-compose up -d
```

Your application should now be running and accessible at your domain!

## Step 9: Create a Deployment Script (Optional)

For future deployments, you can create a deployment script on your local machine:

```bash
#!/bin/bash

# Pull latest changes
ssh -i TwitchCounterKey.pem ec2-user@your-domain.com "cd ~/TwitchCounter && git pull"

# Rebuild and restart containers
ssh -i TwitchCounterKey.pem ec2-user@your-domain.com "cd ~/TwitchCounter && docker-compose down && docker-compose up -d"

echo "Deployment completed!"
```

Save this as `deploy.sh`, make it executable with `chmod +x deploy.sh`, and run it whenever you want to deploy updates.

## Monitoring and Maintenance

- Check application logs:
  ```bash
  ssh -i TwitchCounterKey.pem ec2-user@your-domain.com "cd ~/TwitchCounter && docker-compose logs -f"
  ```

- Restart the application:
  ```bash
  ssh -i TwitchCounterKey.pem ec2-user@your-domain.com "cd ~/TwitchCounter && docker-compose restart"
  ```

- Stop the application:
  ```bash
  ssh -i TwitchCounterKey.pem ec2-user@your-domain.com "cd ~/TwitchCounter && docker-compose down"
  ```

## Cleanup

If you want to remove all resources created for this project:

```bash
# Terminate the EC2 instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Delete the security group (after instance is terminated)
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
aws ec2 delete-security-group --group-name TwitchCounterSG

# Delete the key pair
aws ec2 delete-key-pair --key-name TwitchCounterKey
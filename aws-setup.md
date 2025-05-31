# AWS Deployment Guide

This guide provides multiple options for deploying the Twitch Word Counter to AWS:

1. **Automated Deployment with GitHub Actions** - Recommended for continuous deployment
2. **Manual Deployment with Setup Script** - Quick one-time setup
3. **Manual Deployment with AWS CLI** - For advanced users who want more control

## Option 1: Automated Deployment with GitHub Actions

This method uses GitHub Actions to automatically deploy your application to AWS whenever you push changes to the main branch.

### Prerequisites

- AWS account eligible for free tier
- Namecheap domain with Dynamic DNS enabled
- GitHub repository for your project

### Setup Steps

1. **Fork or clone the repository**:
   ```bash
   git clone https://github.com/Aask42/TwitchCounter.git
   cd TwitchCounter
   ```

2. **Add GitHub Secrets**:
   In your GitHub repository, go to Settings > Secrets and add the following secrets:
   
   - `AWS_ACCESS_KEY_ID`: Your AWS access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
   - `AWS_REGION`: Your preferred AWS region (e.g., us-east-1)
   - `NAMECHEAP_DOMAIN`: Your Namecheap domain (e.g., example.com)
   - `NAMECHEAP_DDNS_PASSWORD`: Your Namecheap Dynamic DNS password
   
   For detailed instructions on setting up GitHub secrets, see the [GitHub Secrets Guide](github-secrets-guide.md).

3. **Push to GitHub**:
   ```bash
   git push
   ```

4. **Monitor Deployment**:
   Go to the Actions tab in your GitHub repository to monitor the deployment progress.

5. **After First Deployment**:
   After the first successful deployment, GitHub Actions will output the instance ID and public DNS. Add these as secrets to your repository:
   
   - `INSTANCE_ID`: The EC2 instance ID
   - `PUBLIC_DNS`: The EC2 public DNS name
   - `EC2_SSH_KEY`: The contents of your TwitchCounterKey.pem file

6. **Cleaning Up Old Resources**:
   The workflow automatically cleans up instances older than 7 days. To manually trigger a cleanup:
   
   - Go to the Actions tab in your GitHub repository
   - Select the "Deploy to AWS" workflow
   - Click "Run workflow"
   - Select "cleanup" from the environment dropdown
   - Click "Run workflow"

### How It Works

The GitHub Actions workflow:
1. Creates an EC2 instance if one doesn't exist
2. Sets up Docker, Docker Compose, and Nginx
3. Configures DDNS with a custom script (no ddclient required)
4. Deploys the application
5. Updates your domain to point to the server

## Option 2: Manual Deployment with Setup Script

This method uses a single setup script to deploy the application to an existing EC2 instance.

### Prerequisites

- AWS account with an EC2 instance running Amazon Linux 2023
- Namecheap domain with Dynamic DNS enabled
- SSH access to your EC2 instance

### Setup Steps

1. **Connect to your EC2 instance**:
   ```bash
   ssh -i your-key.pem ec2-user@your-instance-public-dns
   ```

2. **Download the setup script**:
   ```bash
   curl -O https://raw.githubusercontent.com/Aask42/TwitchCounter/main/setup.sh
   chmod +x setup.sh
   ```

3. **Run the setup script as root**:
   ```bash
   sudo ./setup.sh
   ```

4. **Follow the prompts**:
   The script will ask for your AWS region, Namecheap domain, and DDNS password.

### What the Script Does

The setup script:
1. Updates the system
2. Installs Docker, Docker Compose, and Nginx
3. Creates a custom DDNS update script (no ddclient required)
4. Sets up a cron job to update DDNS every 10 minutes
5. Clones the repository and configures the application
6. Sets up Nginx as a reverse proxy
7. Starts the application

## Option 3: Manual Deployment with AWS CLI

For advanced users who want more control over the deployment process.

### Prerequisites

- AWS CLI installed and configured
- Namecheap domain with Dynamic DNS enabled

### Setup Steps

1. **Create a key pair**:
   ```bash
   aws ec2 create-key-pair --key-name TwitchCounterKey --query 'KeyMaterial' --output text > TwitchCounterKey.pem
   chmod 400 TwitchCounterKey.pem
   ```

2. **Create a security group**:
   ```bash
   SG_ID=$(aws ec2 create-security-group --group-name TwitchCounterSG --description "Security group for Twitch Counter" --query 'GroupId' --output text)
   
   aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr $(curl -s https://checkip.amazonaws.com)/32
   aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
   aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
   aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0
   ```

3. **Launch an EC2 instance**:
   ```bash
   AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)
   
   INSTANCE_ID=$(aws ec2 run-instances \
     --image-id $AMI_ID \
     --count 1 \
     --instance-type t2.micro \
     --key-name TwitchCounterKey \
     --security-group-ids $SG_ID \
     --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=TwitchCounter}]' \
     --query 'Instances[0].InstanceId' \
     --output text)
   
   aws ec2 wait instance-running --instance-ids $INSTANCE_ID
   
   PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
   ```

4. **Download and modify the setup script**:
   ```bash
   curl -O https://raw.githubusercontent.com/Aask42/TwitchCounter/main/setup.sh
   ```

5. **Upload and run the setup script**:
   ```bash
   scp -i TwitchCounterKey.pem setup.sh ec2-user@$PUBLIC_DNS:~/setup.sh
   ssh -i TwitchCounterKey.pem ec2-user@$PUBLIC_DNS "chmod +x ~/setup.sh && sudo ~/setup.sh"
   ```

## Troubleshooting

### DDNS Not Updating

If your domain is not updating correctly:

1. **Check the DDNS update script**:
   ```bash
   ssh -i your-key.pem ec2-user@your-instance-public-dns
   cat /home/ec2-user/update_ddns.sh
   ```

2. **Run the update script manually**:
   ```bash
   /home/ec2-user/update_ddns.sh
   ```

3. **Check the cron job**:
   ```bash
   crontab -l
   ```

### Application Not Starting

If the application doesn't start:

1. **Check Docker logs**:
   ```bash
   cd ~/TwitchCounter
   docker-compose logs
   ```

2. **Check if Docker is running**:
   ```bash
   sudo systemctl status docker
   ```

3. **Restart the application**:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Nginx Configuration Issues

If Nginx is not working correctly:

1. **Check Nginx configuration**:
   ```bash
   sudo nginx -t
   ```

2. **Check Nginx status**:
   ```bash
   sudo systemctl status nginx
   ```

3. **Check Nginx logs**:
   ```bash
   sudo tail -f /var/log/nginx/error.log
   ```

### Cleaning Up AWS Resources

If you need to clean up AWS resources manually:

1. **Using the cleanup script**:
  ```bash
  # Download the cleanup script
  curl -O https://raw.githubusercontent.com/Aask42/TwitchCounter/main/cleanup_aws.sh
  chmod +x cleanup_aws.sh
  
  # Run with AWS CLI configured
  ./cleanup_aws.sh
  ```

2. **Options for the cleanup script**:
  - `--dry-run`: Show what would be deleted without actually deleting
  - `--force`: Delete all instances regardless of age
  - `--days-old N`: Delete instances older than N days (default: 7)
  - `--tag-name NAME`: Delete instances with this tag name (default: TwitchCounter)
  - `--region REGION`: Specify the AWS region (default: us-east-1 or value of AWS_REGION environment variable)
  - `--delete-all-keys`: Delete all key pairs including the main TwitchCounterKey (by default, the main key is preserved)

3. **Example usage**:
   ```bash
   # Dry run to see what would be deleted
   ./cleanup_aws.sh --dry-run
   
   # Force delete all TwitchCounter instances
   ./cleanup_aws.sh --force
   
   # Delete instances older than 14 days
   ./cleanup_aws.sh --days-old 14
   
   # Specify a different AWS region
   ./cleanup_aws.sh --region us-west-2
   
   # Delete all key pairs including the main one
   ./cleanup_aws.sh --delete-all-keys
   ```

### Key Pair Issues

If you encounter key pair errors like "InvalidKeyPair.Duplicate: The keypair already exists":

1. **Using the AWS Console**:
   - Go to the AWS EC2 Console
   - Navigate to "Key Pairs" under "Network & Security"
   - Delete the existing key pair or use a different name

2. **Using the AWS CLI**:
   - Delete the existing key pair:
     ```bash
     aws ec2 delete-key-pair --key-name TwitchCounterKey
     ```
   - Or use the cleanup script with the --delete-all-keys option:
     ```bash
     ./cleanup_aws.sh --delete-all-keys
     ```

3. **In GitHub Actions**:
   - The workflow will automatically handle duplicate key pairs by:
     - Using the existing key pair if the key material is available in secrets
     - Creating a new key pair with a timestamp suffix if needed
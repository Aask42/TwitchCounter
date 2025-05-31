# SSH Troubleshooting Guide for AWS EC2

This guide provides detailed instructions for troubleshooting SSH connectivity issues with your AWS EC2 instances.

## Common SSH Issues

1. **Security Group Configuration**: Missing or incorrect inbound rules for port 22
2. **Key Pair Issues**: Missing, corrupted, or incorrect permissions on the key file
3. **Instance Initialization**: EC2 instance still in the initialization process
4. **Network Connectivity**: Network issues between your local machine and AWS
5. **SSH Service**: SSH service not running or misconfigured on the instance

## Using the SSH Troubleshooting Script

The `ssh_troubleshoot.sh` script provides comprehensive diagnostics and fixes for SSH connectivity issues.

### Basic Usage

```bash
# Download the script
curl -O https://raw.githubusercontent.com/Aask42/TwitchCounter/main/ssh_troubleshoot.sh
chmod +x ssh_troubleshoot.sh

# Run the script
./ssh_troubleshoot.sh
```

### Command Line Options

```bash
./ssh_troubleshoot.sh [--instance-id ID] [--key-file PATH] [--user USERNAME] [--region REGION] [--fix] [--verbose]
```

- `--instance-id ID`: Specify the EC2 instance ID to troubleshoot
- `--key-file PATH`: Path to the SSH key file (.pem)
- `--user USERNAME`: SSH username (default: ec2-user)
- `--region REGION`: AWS region (default: us-east-1 or AWS_REGION env var)
- `--fix`: Automatically fix common issues when possible
- `--verbose`: Show verbose output

### Examples

```bash
# Check all instances and interactively select one
./ssh_troubleshoot.sh

# Check a specific instance
./ssh_troubleshoot.sh --instance-id i-1234567890abcdef0

# Use a specific key file
./ssh_troubleshoot.sh --key-file ~/keys/TwitchCounterKey.pem

# Automatically fix common issues
./ssh_troubleshoot.sh --fix

# Show verbose output
./ssh_troubleshoot.sh --verbose
```

## What the Script Does

1. **AWS CLI Check**: Verifies AWS CLI installation and credentials
2. **Instance Discovery**: Finds and selects EC2 instances to troubleshoot
3. **Instance Details**: Retrieves detailed information about the instance
4. **Key File Check**: Locates and verifies the SSH key file
5. **Key Permissions**: Checks and fixes key file permissions
6. **Security Group Check**: Verifies security group rules for SSH access
7. **Network Connectivity**: Tests TCP connectivity to the instance
8. **Instance Status**: Checks instance system status and console output
9. **SSH Connection Test**: Attempts an SSH connection with diagnostics

## Manual Troubleshooting Steps

If the script doesn't resolve your issues, try these manual steps:

### 1. Check Security Group Rules

```bash
# Get security group IDs for your instance
aws ec2 describe-instances --instance-ids i-1234567890abcdef0 --query 'Reservations[0].Instances[0].SecurityGroups[*].[GroupId,GroupName]' --output table

# Check inbound rules for SSH
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=sg-1234567890abcdef0" --query 'SecurityGroupRules[?IpProtocol==`tcp` && FromPort==`22`].[CidrIpv4,ToPort]' --output table

# Add SSH rule if missing
aws ec2 authorize-security-group-ingress --group-id sg-1234567890abcdef0 --protocol tcp --port 22 --cidr 0.0.0.0/0
```

### 2. Check Instance Status

```bash
# Check instance status
aws ec2 describe-instance-status --instance-ids i-1234567890abcdef0

# Get console output
aws ec2 get-console-output --instance-id i-1234567890abcdef0 --latest
```

### 3. Verify Key File

```bash
# Check key file permissions
ls -l TwitchCounterKey.pem

# Fix permissions if needed
chmod 400 TwitchCounterKey.pem

# Verify key format
ssh-keygen -l -f TwitchCounterKey.pem
```

### 4. Test SSH Connection

```bash
# Basic connection test
nc -zv your-instance-public-dns 22

# Verbose SSH connection
ssh -v -i TwitchCounterKey.pem ec2-user@your-instance-public-dns
```

## Getting a New SSH Key

If you've lost your SSH key or it's corrupted, you have several options:

1. **GitHub Actions Workflow**: Run the deployment workflow again, which will output the SSH key at the end
2. **GitHub Secrets**: If you saved the key as a GitHub secret (EC2_SSH_KEY), you can retrieve it from there
3. **Create a New Key Pair**: Create a new key pair and associate it with your instance:
   ```bash
   # Create a new key pair
   aws ec2 create-key-pair --key-name NewTwitchCounterKey --query 'KeyMaterial' --output text > NewTwitchCounterKey.pem
   chmod 400 NewTwitchCounterKey.pem
   
   # Stop the instance
   aws ec2 stop-instances --instance-ids i-1234567890abcdef0
   
   # Wait for the instance to stop
   aws ec2 wait instance-stopped --instance-ids i-1234567890abcdef0
   
   # Modify the instance to use the new key pair
   aws ec2 modify-instance-attribute --instance-id i-1234567890abcdef0 --key-name NewTwitchCounterKey
   
   # Start the instance
   aws ec2 start-instances --instance-ids i-1234567890abcdef0
   ```

## Typical EC2 Initialization Times

- Amazon Linux 2023 instances typically take 1-5 minutes to fully initialize
- Factors affecting initialization time:
  - Instance type (t2.micro may be slower than larger instances)
  - AMI size and initialization scripts
  - Region and availability zone load
  - First-time boot vs subsequent boots
- SSH may not be available until initialization is complete

## Additional Resources

- [AWS EC2 Troubleshooting Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/TroubleshootingInstancesConnecting.html)
- [SSH Connection Issues](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/TroubleshootingInstancesConnecting.html#TroubleshootingInstancesConnectingSSH)
- [Key Pair Issues](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#replacing-lost-key-pair)
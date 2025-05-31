#!/bin/bash
# SSH Troubleshooting Script for AWS EC2
# This script helps diagnose and fix common SSH connectivity issues with EC2 instances

# Set default values
INSTANCE_ID=""
KEY_FILE=""
USER="ec2-user"
AWS_REGION=${AWS_REGION:-"us-east-1"}
FIX_ISSUES=false
VERBOSE=false

# Set AWS region
export AWS_DEFAULT_REGION=$AWS_REGION

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance-id)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --key-file)
      KEY_FILE="$2"
      shift 2
      ;;
    --user)
      USER="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      export AWS_DEFAULT_REGION="$2"
      shift 2
      ;;
    --fix)
      FIX_ISSUES=true
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--instance-id ID] [--key-file PATH] [--user USERNAME] [--region REGION] [--fix] [--verbose]"
      echo ""
      echo "Options:"
      echo "  --instance-id ID    EC2 instance ID to troubleshoot"
      echo "  --key-file PATH     Path to the SSH key file (.pem)"
      echo "  --user USERNAME     SSH username (default: ec2-user)"
      echo "  --region REGION     AWS region (default: us-east-1 or AWS_REGION env var)"
      echo "  --fix               Automatically fix common issues when possible"
      echo "  --verbose, -v       Show verbose output"
      exit 1
      ;;
  esac
done

# Function to log verbose messages
log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "$@"
  fi
}

# Function to check AWS CLI availability
check_aws_cli() {
  log_verbose "Checking AWS CLI installation..."
  if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed or not in PATH"
    echo "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
  fi
  
  log_verbose "Checking AWS credentials..."
  if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured or insufficient permissions"
    echo "Please run 'aws configure' to set up your credentials"
    exit 1
  fi
}

# Function to find instance if not provided
find_instance() {
  if [ -z "$INSTANCE_ID" ]; then
    echo "No instance ID provided. Looking for instances with tag Name=TwitchCounter..."
    INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=TwitchCounter" \
      --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value | [0]]' \
      --output text)
    
    if [ -z "$INSTANCES" ]; then
      echo "No instances found with tag Name=TwitchCounter"
      echo "Please specify an instance ID with --instance-id"
      exit 1
    fi
    
    # Display found instances and let user select one
    echo "Found instances:"
    echo "----------------"
    i=1
    declare -a INSTANCE_IDS
    declare -a INSTANCE_STATES
    declare -a INSTANCE_NAMES
    
    while read -r ID STATE NAME; do
      echo "$i) Instance $ID (Name: $NAME, State: $STATE)"
      INSTANCE_IDS[$i]=$ID
      INSTANCE_STATES[$i]=$STATE
      INSTANCE_NAMES[$i]=$NAME
      i=$((i+1))
    done <<< "$INSTANCES"
    
    # If only one instance found, use it automatically
    if [ ${#INSTANCE_IDS[@]} -eq 1 ]; then
      INSTANCE_ID=${INSTANCE_IDS[1]}
      echo "Using the only instance found: $INSTANCE_ID"
    else
      read -p "Enter the number of the instance to troubleshoot (1-$((i-1))): " SELECTION
      if [[ ! $SELECTION =~ ^[0-9]+$ ]] || [ $SELECTION -lt 1 ] || [ $SELECTION -ge $i ]; then
        echo "Invalid selection"
        exit 1
      fi
      INSTANCE_ID=${INSTANCE_IDS[$SELECTION]}
    fi
  fi
}

# Function to get instance details
get_instance_details() {
  echo "Fetching instance details for $INSTANCE_ID..."
  INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error: Instance $INSTANCE_ID not found or you don't have permission to access it."
    exit 1
  fi
  
  # Extract instance information
  INSTANCE_STATE=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].State.Name')
  PUBLIC_DNS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicDnsName')
  PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
  KEY_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].KeyName')
  SG_IDS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].SecurityGroups[].GroupId')
  
  echo "Instance State: $INSTANCE_STATE"
  echo "Public DNS:     $PUBLIC_DNS"
  echo "Public IP:      $PUBLIC_IP"
  echo "Key Name:       $KEY_NAME"
  
  # If instance is not running, we can't SSH to it
  if [ "$INSTANCE_STATE" != "running" ]; then
    echo "Error: Instance is not in 'running' state. Current state: $INSTANCE_STATE"
    echo "Please start the instance before troubleshooting SSH connectivity."
    exit 1
  fi
  
  # If no public DNS or IP, we can't SSH to it
  if [ -z "$PUBLIC_DNS" ] && [ -z "$PUBLIC_IP" ]; then
    echo "Error: Instance does not have a public DNS name or IP address."
    echo "This could be because the instance is in a private subnet or doesn't have a public IP assigned."
    exit 1
  fi
  
  # Use IP if DNS is not available
  if [ -z "$PUBLIC_DNS" ]; then
    PUBLIC_DNS=$PUBLIC_IP
    echo "Using Public IP as connection target: $PUBLIC_IP"
  fi
}

# Function to find key file if not provided
find_key_file() {
  if [ -z "$KEY_FILE" ]; then
    # Check if key file exists in current directory
    if [ -f "${KEY_NAME}.pem" ]; then
      KEY_FILE="${KEY_NAME}.pem"
      echo "Found key file in current directory: $KEY_FILE"
    else
      # Look for key file in common locations
      COMMON_LOCATIONS=("." "~" "~/Downloads" "~/keys" "~/.ssh")
      for LOCATION in "${COMMON_LOCATIONS[@]}"; do
        EXPANDED_PATH=$(eval echo "$LOCATION/${KEY_NAME}.pem")
        if [ -f "$EXPANDED_PATH" ]; then
          KEY_FILE="$EXPANDED_PATH"
          echo "Found key file: $KEY_FILE"
          break
        fi
      done
      
      if [ -z "$KEY_FILE" ]; then
        echo "Warning: Could not find key file for key pair '$KEY_NAME'"
        echo "Please specify the key file path with --key-file"
        read -p "Do you want to continue without a key file? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
          exit 1
        fi
      fi
    fi
  else
    # Check if provided key file exists
    if [ ! -f "$KEY_FILE" ]; then
      echo "Error: Key file '$KEY_FILE' not found"
      exit 1
    fi
  fi
}

# Function to check key file permissions
check_key_permissions() {
  if [ -n "$KEY_FILE" ]; then
    KEY_PERMS=$(stat -c "%a" "$KEY_FILE" 2>/dev/null || stat -f "%Lp" "$KEY_FILE")
    echo "Key file permissions: $KEY_PERMS"
    
    if [ "$KEY_PERMS" != "400" ]; then
      echo "Warning: Key file permissions should be 400 (current: $KEY_PERMS)"
      if [ "$FIX_ISSUES" = true ]; then
        echo "Fixing key file permissions..."
        chmod 400 "$KEY_FILE"
        echo "Permissions updated to 400"
      else
        read -p "Would you like to fix the key file permissions? (y/n): " FIX_PERMS
        if [[ "$FIX_PERMS" =~ ^[Yy]$ ]]; then
          chmod 400 "$KEY_FILE"
          echo "Permissions updated to 400"
        fi
      fi
    fi
  fi
}

# Function to check security group rules
check_security_groups() {
  echo "Checking security group rules for SSH access..."
  SSH_ALLOWED=false
  
  for SG_ID in $SG_IDS; do
    SG_RULES=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ID" --query 'SecurityGroupRules[?IpProtocol==`tcp` && FromPort==`22`].[CidrIpv4,ToPort]' --output text)
    if [ -n "$SG_RULES" ]; then
      SSH_ALLOWED=true
      echo "SSH (port 22) is allowed in security group $SG_ID"
      echo "Allowed CIDR ranges:"
      while read -r CIDR PORT; do
        echo "  $CIDR"
      done <<< "$SG_RULES"
    fi
  done
  
  if [ "$SSH_ALLOWED" = false ]; then
    echo "Warning: SSH (port 22) is not explicitly allowed in any security group!"
    
    if [ "$FIX_ISSUES" = true ]; then
      echo "Automatically adding SSH rule to security group..."
      SG_ID=$(echo $SG_IDS | awk '{print $1}')  # Use the first security group
      aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
      if [ $? -eq 0 ]; then
        echo "SSH rule added successfully to security group $SG_ID"
        SSH_ALLOWED=true
      else
        echo "Failed to add SSH rule. You may need to check your AWS permissions."
      fi
    else
      read -p "Would you like to add an SSH rule to allow access from anywhere (0.0.0.0/0)? (y/n): " ADD_SSH_RULE
      if [[ "$ADD_SSH_RULE" =~ ^[Yy]$ ]]; then
        SG_ID=$(echo $SG_IDS | awk '{print $1}')  # Use the first security group
        aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
        if [ $? -eq 0 ]; then
          echo "SSH rule added successfully to security group $SG_ID"
          SSH_ALLOWED=true
        else
          echo "Failed to add SSH rule. You may need to check your AWS permissions."
        fi
      fi
    fi
  fi
}

# Function to check network connectivity
check_network() {
  echo "Checking network connectivity to $PUBLIC_DNS:22..."
  
  # Check if we can reach the instance on port 22
  if nc -z -w 5 $PUBLIC_DNS 22 2>/dev/null; then
    echo "TCP connection to port 22 successful"
  else
    echo "Warning: Cannot establish TCP connection to $PUBLIC_DNS:22"
    echo "This could be due to:"
    echo "  - Security group rules not allowing SSH access"
    echo "  - Instance firewall blocking SSH"
    echo "  - Network connectivity issues"
    echo "  - Instance still initializing"
  fi
}

# Function to check instance system status
check_instance_status() {
  echo "Checking instance system status..."
  STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID)
  INSTANCE_STATUS=$(echo "$STATUS" | jq -r '.InstanceStatuses[0].InstanceStatus.Status // "not-available"')
  SYSTEM_STATUS=$(echo "$STATUS" | jq -r '.InstanceStatuses[0].SystemStatus.Status // "not-available"')
  
  echo "Instance Status: $INSTANCE_STATUS"
  echo "System Status:   $SYSTEM_STATUS"
  
  if [ "$INSTANCE_STATUS" != "ok" ] || [ "$SYSTEM_STATUS" != "ok" ]; then
    echo "Warning: Instance status checks are not passing"
    echo "This could indicate that the instance is still initializing or has system issues"
    
    # Get console output for troubleshooting
    echo "Retrieving console output (last 10 lines)..."
    CONSOLE_OUTPUT=$(aws ec2 get-console-output --instance-id $INSTANCE_ID --latest --query 'Output' --output text)
    if [ -n "$CONSOLE_OUTPUT" ]; then
      echo "Console Output (last 10 lines):"
      echo "$CONSOLE_OUTPUT" | tail -10
    else
      echo "No console output available yet."
    fi
  fi
}

# Function to attempt SSH connection
attempt_ssh() {
  if [ -n "$KEY_FILE" ]; then
    echo "Attempting SSH connection to $PUBLIC_DNS..."
    
    # Try a basic connection first
    if [ "$VERBOSE" = true ]; then
      ssh -v -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $USER@$PUBLIC_DNS "echo SSH connection successful"
    else
      ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $USER@$PUBLIC_DNS "echo SSH connection successful"
    fi
    
    if [ $? -eq 0 ]; then
      echo "SSH connection successful!"
    else
      echo "SSH connection failed."
      echo "Trying with verbose output to diagnose issues..."
      ssh -v -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 $USER@$PUBLIC_DNS "echo SSH test"
    fi
  else
    echo "Cannot attempt SSH connection without a key file."
  fi
}

# Main function
main() {
  echo "SSH Troubleshooting for AWS EC2"
  echo "=============================="
  
  check_aws_cli
  find_instance
  get_instance_details
  find_key_file
  check_key_permissions
  check_security_groups
  check_network
  check_instance_status
  
  echo ""
  echo "Troubleshooting Summary:"
  echo "----------------------"
  echo "Instance ID:   $INSTANCE_ID"
  echo "Instance State: $INSTANCE_STATE"
  echo "Public DNS:    $PUBLIC_DNS"
  echo "Key File:      $KEY_FILE"
  echo "SSH User:      $USER"
  echo "SSH Allowed:   $SSH_ALLOWED"
  
  echo ""
  echo "SSH Command:"
  if [ -n "$KEY_FILE" ]; then
    echo "ssh -i \"$KEY_FILE\" $USER@$PUBLIC_DNS"
  else
    echo "ssh $USER@$PUBLIC_DNS  # Key file not specified"
  fi
  
  # Attempt SSH connection if requested
  echo ""
  read -p "Would you like to attempt an SSH connection now? (y/n): " ATTEMPT
  if [[ "$ATTEMPT" =~ ^[Yy]$ ]]; then
    attempt_ssh
  fi
  
  echo ""
  echo "Common SSH Troubleshooting Steps:"
  echo "1. Ensure the instance is fully initialized (can take 3-5 minutes)"
  echo "2. Verify security groups allow SSH access from your IP"
  echo "3. Check that your key file has correct permissions (chmod 400)"
  echo "4. If using a bastion host or VPN, ensure proper network routing"
  echo "5. Try connecting with verbose output: ssh -v -i \"$KEY_FILE\" $USER@$PUBLIC_DNS"
}

# Run the main function
main
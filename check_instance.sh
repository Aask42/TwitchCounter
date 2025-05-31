#!/bin/bash
# EC2 Instance Status Check Script
# This script checks the status of EC2 instances and provides detailed information

# Set default values
INSTANCE_ID=""
WAIT_FOR_SSH=false
TIMEOUT=300
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Set AWS region
export AWS_DEFAULT_REGION=$AWS_REGION

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance-id)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --wait-for-ssh)
      WAIT_FOR_SSH=true
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      export AWS_DEFAULT_REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--instance-id ID] [--wait-for-ssh] [--timeout SECONDS] [--region REGION]"
      exit 1
      ;;
  esac
done

# If no instance ID is provided, look for instances with the TwitchCounter tag
if [ -z "$INSTANCE_ID" ]; then
  echo "No instance ID provided. Looking for instances with tag Name=TwitchCounter..."
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=TwitchCounter" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
    --output text)
  
  if [ -z "$INSTANCES" ]; then
    echo "No instances found with tag Name=TwitchCounter"
    exit 1
  fi
  
  # Display found instances and let user select one
  echo "Found instances:"
  echo "----------------"
  i=1
  declare -a INSTANCE_IDS
  declare -a INSTANCE_STATES
  
  while read -r ID STATE; do
    echo "$i) Instance $ID (State: $STATE)"
    INSTANCE_IDS[$i]=$ID
    INSTANCE_STATES[$i]=$STATE
    i=$((i+1))
  done <<< "$INSTANCES"
  
  # If only one instance found, use it automatically
  if [ ${#INSTANCE_IDS[@]} -eq 1 ]; then
    INSTANCE_ID=${INSTANCE_IDS[1]}
    echo "Using the only instance found: $INSTANCE_ID"
  else
    read -p "Enter the number of the instance to check (1-$((i-1))): " SELECTION
    if [[ ! $SELECTION =~ ^[0-9]+$ ]] || [ $SELECTION -lt 1 ] || [ $SELECTION -ge $i ]; then
      echo "Invalid selection"
      exit 1
    fi
    INSTANCE_ID=${INSTANCE_IDS[$SELECTION]}
  fi
fi

echo "EC2 Instance Status Check"
echo "========================="
echo "Checking instance: $INSTANCE_ID"

# Get detailed instance information
echo "Fetching instance details..."
INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Error: Instance $INSTANCE_ID not found or you don't have permission to access it."
  exit 1
fi

# Extract and display instance information
INSTANCE_STATE=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].State.Name')
LAUNCH_TIME=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].LaunchTime')
INSTANCE_TYPE=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].InstanceType')
PUBLIC_DNS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicDnsName')
PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
PRIVATE_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
AVAILABILITY_ZONE=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')
SECURITY_GROUPS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].SecurityGroups[] | .GroupId + " (" + .GroupName + ")"')
KEY_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].KeyName')

# Calculate uptime
LAUNCH_TIMESTAMP=$(date -d "$LAUNCH_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$LAUNCH_TIME" +%s)
CURRENT_TIMESTAMP=$(date +%s)
UPTIME_SECONDS=$((CURRENT_TIMESTAMP - LAUNCH_TIMESTAMP))
UPTIME_MINUTES=$((UPTIME_SECONDS / 60))
UPTIME_HOURS=$((UPTIME_SECONDS / 3600))

echo "Instance Details:"
echo "----------------"
echo "Instance ID:       $INSTANCE_ID"
echo "State:             $INSTANCE_STATE"
echo "Instance Type:     $INSTANCE_TYPE"
echo "Launch Time:       $LAUNCH_TIME"
echo "Uptime:            ${UPTIME_HOURS}h ${UPTIME_MINUTES}m"
echo "Public DNS:        $PUBLIC_DNS"
echo "Public IP:         $PUBLIC_IP"
echo "Private IP:        $PRIVATE_IP"
echo "Availability Zone: $AVAILABILITY_ZONE"
echo "Key Pair:          $KEY_NAME"
echo "Security Groups:"
for SG in $SECURITY_GROUPS; do
  echo "  $SG"
done

# Check if SSH port is open in security groups
echo "Checking security group rules for SSH access..."
SG_IDS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].SecurityGroups[].GroupId')
SSH_ALLOWED=false

for SG_ID in $SG_IDS; do
  SG_RULES=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ID" --query 'SecurityGroupRules[?IpProtocol==`tcp` && FromPort==`22`].[CidrIpv4,ToPort]' --output text)
  if [ -n "$SG_RULES" ]; then
    SSH_ALLOWED=true
    echo "  SSH (port 22) is allowed in security group $SG_ID"
    echo "  Allowed CIDR ranges:"
    while read -r CIDR PORT; do
      echo "    $CIDR"
    done <<< "$SG_RULES"
  fi
done

if [ "$SSH_ALLOWED" = false ]; then
  echo "  Warning: SSH (port 22) is not explicitly allowed in any security group!"
  
  # Ask if user wants to add SSH rule
  if [ "$INSTANCE_STATE" = "running" ]; then
    read -p "Would you like to add an SSH rule to allow access from anywhere (0.0.0.0/0)? (y/n): " ADD_SSH_RULE
    if [[ "$ADD_SSH_RULE" =~ ^[Yy]$ ]]; then
      for SG_ID in $SG_IDS; do
        echo "Adding SSH rule to security group $SG_ID..."
        aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
        if [ $? -eq 0 ]; then
          echo "  SSH rule added successfully!"
          SSH_ALLOWED=true
          break
        else
          echo "  Failed to add SSH rule. You may need to check your AWS permissions."
        fi
      done
    fi
  fi
fi

# Check instance status
echo "Checking instance status..."
STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID)
INSTANCE_STATUS=$(echo "$STATUS" | jq -r '.InstanceStatuses[0].InstanceStatus.Status // "not-available"')
SYSTEM_STATUS=$(echo "$STATUS" | jq -r '.InstanceStatuses[0].SystemStatus.Status // "not-available"')

echo "Instance Status:   $INSTANCE_STATUS"
echo "System Status:     $SYSTEM_STATUS"

# Get console output
echo "Retrieving console output (last 10 lines)..."
CONSOLE_OUTPUT=$(aws ec2 get-console-output --instance-id $INSTANCE_ID --latest --query 'Output' --output text)
if [ -n "$CONSOLE_OUTPUT" ]; then
  echo "Console Output (last 10 lines):"
  echo "$CONSOLE_OUTPUT" | tail -10
else
  echo "No console output available yet."
fi

# Wait for SSH if requested
if [ "$WAIT_FOR_SSH" = true ] && [ -n "$PUBLIC_DNS" ]; then
  echo "Waiting for SSH to become available (timeout: $TIMEOUT seconds)..."
  START_TIME=$(date +%s)
  
  while true; do
    # Check if SSH is available
    if nc -z -w 5 $PUBLIC_DNS 22 2>/dev/null; then
      echo "SSH is now available!"
      break
    fi
    
    # Check if we've timed out
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
      echo "Timed out waiting for SSH to become available after $TIMEOUT seconds."
      echo "This could be due to security group rules, instance initialization, or network issues."
      break
    fi
    
    # Print status update every 30 seconds
    if [ $((ELAPSED_TIME % 30)) -eq 0 ]; then
      echo "Still waiting for SSH... ($ELAPSED_TIME seconds elapsed, timeout at $TIMEOUT seconds)"
      # Check instance status again
      CURRENT_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)
      echo "Current instance state: $CURRENT_STATE"
    fi
    
    sleep 5
  done
fi

# Add detailed SSH troubleshooting
if [ "$INSTANCE_STATE" = "running" ] && [ -n "$PUBLIC_DNS" ]; then
  echo "Performing detailed SSH troubleshooting..."
  
  # Check if we can reach the instance on port 22
  echo "Testing TCP connectivity to port 22..."
  nc -zv -w 5 $PUBLIC_DNS 22 2>&1 || echo "  TCP connection to port 22 failed"
  
  # Check if the key file exists locally
  echo "Checking for local key file..."
  if [ -f "${KEY_NAME}.pem" ]; then
    echo "  Found local key file: ${KEY_NAME}.pem"
    
    # Check key file permissions
    KEY_PERMS=$(stat -c "%a" "${KEY_NAME}.pem" 2>/dev/null || stat -f "%Lp" "${KEY_NAME}.pem")
    echo "  Key file permissions: $KEY_PERMS"
    if [ "$KEY_PERMS" != "400" ]; then
      echo "  Warning: Key file permissions should be 400 (current: $KEY_PERMS)"
      read -p "  Would you like to fix the key file permissions? (y/n): " FIX_PERMS
      if [[ "$FIX_PERMS" =~ ^[Yy]$ ]]; then
        chmod 400 "${KEY_NAME}.pem"
        echo "  Permissions updated to 400"
      fi
    fi
  else
    echo "  Warning: Key file ${KEY_NAME}.pem not found in current directory"
    echo "  You may need to download the key file from AWS or use a different key"
  fi
  
  # Try a verbose SSH connection
  if [ -f "${KEY_NAME}.pem" ]; then
    echo "Attempting SSH connection with verbose output (timeout: 10s)..."
    timeout 10 ssh -v -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$PUBLIC_DNS "echo SSH test" 2>&1 || echo "  SSH connection failed"
  fi
fi

echo "========================="
echo "Check completed!"
echo "To SSH into this instance (if it's running and SSH is allowed):"
echo "ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_DNS"
echo ""
echo "Common SSH troubleshooting steps:"
echo "1. Ensure the instance is fully initialized (can take 3-5 minutes)"
echo "2. Verify security groups allow SSH access from your IP"
echo "3. Check that your key file has correct permissions (chmod 400)"
echo "4. If using a bastion host or VPN, ensure proper network routing"
echo "5. Try connecting with verbose output: ssh -v -i ${KEY_NAME}.pem ec2-user@$PUBLIC_DNS"
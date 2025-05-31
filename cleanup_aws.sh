#!/bin/bash
# AWS Cleanup Script
# This script identifies and terminates old EC2 instances and cleans up associated resources

# Set default values
DRY_RUN=false
FORCE=false
DAYS_OLD=7
TAG_NAME="TwitchCounter"
KEEP_MAIN_KEY=true
KEEP_MAIN_SG=true
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Set AWS region
export AWS_DEFAULT_REGION=$AWS_REGION

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --days-old)
      DAYS_OLD="$2"
      shift 2
      ;;
    --tag-name)
      TAG_NAME="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      export AWS_DEFAULT_REGION="$2"
      shift 2
      ;;
    --delete-all-keys)
      KEEP_MAIN_KEY=false
      shift
      ;;
    --delete-all-sg)
      KEEP_MAIN_SG=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--force] [--days-old N] [--tag-name NAME] [--region REGION] [--delete-all-keys] [--delete-all-sg]"
      exit 1
      ;;
  esac
done

echo "AWS Cleanup Script"
echo "==================="
echo "Looking for EC2 instances with tag Name=$TAG_NAME older than $DAYS_OLD days"
if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: No resources will be deleted"
fi

# Calculate the cutoff date
CUTOFF_DATE=$(date -d "$DAYS_OLD days ago" +%Y-%m-%d 2>/dev/null || date -v-${DAYS_OLD}d +%Y-%m-%d)
echo "Cutoff date: $CUTOFF_DATE"

# Get all instances with the specified tag
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$TAG_NAME" "Name=instance-state-name,Values=running,stopped,pending,stopping,shutting-down" \
  --query 'Reservations[*].Instances[*].[InstanceId,LaunchTime,Tags[?Key==`Name`].Value | [0],State.Name]' \
  --output text)

if [ -z "$INSTANCES" ]; then
  echo "No instances found with tag Name=$TAG_NAME"
  exit 0
fi

# Process each instance
echo "Found instances:"
echo "----------------"
INSTANCE_IDS_TO_TERMINATE=()

# Get all instances with detailed information
echo "Fetching detailed instance information..."
DETAILED_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$TAG_NAME" \
  --query 'Reservations[*].Instances[*].[InstanceId,LaunchTime,State.Name,PublicDnsName,PublicIpAddress]' \
  --output table)

echo "$DETAILED_INSTANCES"
echo "----------------"

while read -r INSTANCE_ID LAUNCH_TIME NAME STATE; do
  # Convert launch time to date only for comparison
  LAUNCH_DATE=$(echo $LAUNCH_TIME | cut -d'T' -f1)
  
  # Get additional instance details
  UPTIME_SECONDS=$(( $(date +%s) - $(date -d "$LAUNCH_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$LAUNCH_TIME" +%s) ))
  UPTIME_HOURS=$(( UPTIME_SECONDS / 3600 ))
  
  # Check if the instance is older than the cutoff date
  if [[ "$LAUNCH_DATE" < "$CUTOFF_DATE" || "$FORCE" = true ]]; then
    echo "Instance $INSTANCE_ID ($NAME) - Launch date: $LAUNCH_DATE, State: $STATE, Uptime: ~${UPTIME_HOURS}h - WILL BE TERMINATED"
    INSTANCE_IDS_TO_TERMINATE+=("$INSTANCE_ID")
  else
    echo "Instance $INSTANCE_ID ($NAME) - Launch date: $LAUNCH_DATE, State: $STATE, Uptime: ~${UPTIME_HOURS}h - KEEPING"
  fi
  
  # If instance is in pending state, provide additional information
  if [[ "$STATE" == "pending" ]]; then
    echo "  Note: This instance is still initializing. Typical initialization time is 3-5 minutes."
    echo "  If it's been pending for more than 10 minutes, there might be an issue with the instance."
  fi
done <<< "$INSTANCES"

# If no instances to terminate, exit
if [ ${#INSTANCE_IDS_TO_TERMINATE[@]} -eq 0 ]; then
  echo "No instances to terminate"
  exit 0
fi

# Terminate instances if not a dry run
if [ "$DRY_RUN" = false ]; then
  echo "Terminating instances..."
  for INSTANCE_ID in "${INSTANCE_IDS_TO_TERMINATE[@]}"; do
    # Check current instance state
    CURRENT_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
    echo "Terminating $INSTANCE_ID (current state: $CURRENT_STATE)..."
    
    # If instance is in pending state, provide additional information
    if [[ "$CURRENT_STATE" == "pending" ]]; then
      echo "  Note: This instance is still initializing. Terminating a pending instance is allowed but may take longer."
    fi
    
    # Attempt to terminate the instance
    TERMINATION_RESULT=$(aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" 2>&1)
    if [[ $? -eq 0 ]]; then
      echo "  Termination initiated successfully"
    else
      echo "  Error initiating termination: $TERMINATION_RESULT"
      echo "  Will continue with other cleanup tasks"
    fi
  done
  
  # Wait for instances to terminate with timeout
  echo "Waiting for instances to terminate (timeout: 5 minutes)..."
  for INSTANCE_ID in "${INSTANCE_IDS_TO_TERMINATE[@]}"; do
    echo "Waiting for $INSTANCE_ID to terminate..."
    
    # Use a timeout for the wait command
    timeout 300 aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
    if [[ $? -eq 0 ]]; then
      echo "  $INSTANCE_ID terminated successfully"
    else
      FINAL_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
      echo "  Timed out waiting for $INSTANCE_ID to terminate. Current state: $FINAL_STATE"
      echo "  The instance may still be in the process of terminating."
    fi
  done
  
  # Clean up security groups
  echo "Cleaning up security groups..."
  SG_IDS=$(aws ec2 describe-security-groups \
    --query "SecurityGroups[?starts_with(GroupName, 'TwitchCounterSG')].{Id:GroupId,Name:GroupName}" \
    --output text)
  
  if [ -z "$SG_IDS" ]; then
    echo "No security groups found matching TwitchCounterSG*"
  else
    while read -r SG_ID SG_NAME; do
      # Skip the main security group if KEEP_MAIN_SG is true
      if [ "$KEEP_MAIN_SG" = true ] && [ "$SG_NAME" = "TwitchCounterSG" ]; then
        echo "Keeping main security group $SG_NAME ($SG_ID)"
        continue
      fi
      
      echo "Deleting security group $SG_NAME ($SG_ID)..."
      aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || echo "Could not delete security group $SG_ID (it may be in use)"
    done <<< "$SG_IDS"
  fi
  
  # Clean up key pairs
  echo "Cleaning up key pairs..."
  # Use a more reliable way to get key pairs
  KEY_PAIRS=$(aws ec2 describe-key-pairs \
    --query "KeyPairs[?starts_with(KeyName, 'TwitchCounterKey')].KeyName" \
    --output text)
  
  if [ -z "$KEY_PAIRS" ]; then
    echo "No key pairs found matching TwitchCounterKey*"
  else
    for KEY_NAME in $KEY_PAIRS; do
      # Skip the main key pair if KEEP_MAIN_KEY is true
      if [ "$KEEP_MAIN_KEY" = true ] && [ "$KEY_NAME" = "TwitchCounterKey" ]; then
        echo "Keeping main key pair $KEY_NAME"
        continue
      fi
      
      echo "Deleting key pair $KEY_NAME..."
      aws ec2 delete-key-pair --key-name "$KEY_NAME"
    done
  fi
  
  echo "Cleanup completed!"
else
  echo "DRY RUN: Would have terminated these instances:"
  for INSTANCE_ID in "${INSTANCE_IDS_TO_TERMINATE[@]}"; do
    echo "  $INSTANCE_ID"
  done
fi
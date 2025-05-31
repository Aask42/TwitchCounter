#!/bin/bash
# Local Setup Script for Twitch Counter AWS Deployment
# This script helps set up your local environment for connecting to the EC2 instance

# Set default values
SSH_KEY_FILE="TwitchCounterKey.pem"
SSH_KEY_SECRET=""
INSTANCE_ID=""
AWS_REGION=${AWS_REGION:-"us-east-1"}
GITHUB_REPO="Aask42/TwitchCounter"
CREATE_NEW_KEY=false
ADD_TO_GITHUB=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --key-file)
      SSH_KEY_FILE="$2"
      shift 2
      ;;
    --key-secret)
      SSH_KEY_SECRET="$2"
      shift 2
      ;;
    --instance-id)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --create-key)
      CREATE_NEW_KEY=true
      shift
      ;;
    --add-to-github)
      ADD_TO_GITHUB=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --key-file FILE     Path to save the SSH key file (default: TwitchCounterKey.pem)"
      echo "  --key-secret SECRET SSH key content (if not provided, will prompt for input)"
      echo "  --create-key        Create a new AWS key pair instead of using existing one"
      echo "  --add-to-github     Add the SSH key to GitHub Actions secrets"
      echo "  --instance-id ID    EC2 instance ID (if not provided, will try to find it)"
      echo "  --region REGION     AWS region (default: us-east-1 or AWS_REGION env var)"
      echo "  --repo REPO         GitHub repository (default: Aask42/TwitchCounter)"
      echo "  --help, -h          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
echo "Checking for required tools..."
MISSING_TOOLS=()

if ! command_exists aws; then
  MISSING_TOOLS+=("aws")
fi

if ! command_exists ssh; then
  MISSING_TOOLS+=("ssh")
fi

if ! command_exists jq; then
  MISSING_TOOLS+=("jq")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  echo "The following required tools are missing:"
  for TOOL in "${MISSING_TOOLS[@]}"; do
    echo "  - $TOOL"
  done
  
  echo ""
  echo "Please install the missing tools and try again."
  echo "Installation instructions:"
  echo "  - AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  echo "  - SSH: Should be pre-installed on most systems"
  echo "  - jq: https://stedolan.github.io/jq/download/"
  
  read -p "Do you want to continue anyway? (y/n): " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check AWS CLI configuration
if command_exists aws; then
  echo "Checking AWS CLI configuration..."
  if ! aws sts get-caller-identity &>/dev/null; then
    echo "AWS CLI is not configured or credentials are invalid."
    echo "Please run 'aws configure' to set up your AWS credentials."
    
    read -p "Do you want to configure AWS CLI now? (y/n): " CONFIGURE_AWS
    if [[ "$CONFIGURE_AWS" =~ ^[Yy]$ ]]; then
      aws configure
    else
      echo "Skipping AWS CLI configuration."
    fi
  else
    echo "AWS CLI is properly configured."
    
    # Set AWS region
    export AWS_DEFAULT_REGION=$AWS_REGION
    echo "Using AWS region: $AWS_REGION"
  fi
fi

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
  echo "Creating .env file..."
  cat > .env << EOF
# AWS Configuration
AWS_REGION=$AWS_REGION
INSTANCE_ID=$INSTANCE_ID

# Twitch Configuration
TWITCH_CHANNEL=skittishandbus
TARGET_WORDS=fuck,shit,damn

# GitHub Configuration
GITHUB_REPO=$GITHUB_REPO
EOF
  echo ".env file created."
else
  echo ".env file already exists."
fi

# Handle SSH key
echo "Setting up SSH key..."

# Function to add key to GitHub secrets
add_to_github_secrets() {
  local KEY_CONTENT="$1"
  local REPO_PATH="$2"
  
  echo ""
  echo "To add this key to GitHub Actions secrets:"
  echo "----------------------------------------"
  echo "1. Go to your GitHub repository: https://github.com/$GITHUB_REPO"
  echo "2. Navigate to Settings > Secrets and variables > Actions"
  echo "3. Click 'New repository secret'"
  echo "4. Name: EC2_SSH_KEY"
  echo "5. Value: Copy and paste the entire content of $SSH_KEY_FILE"
  echo ""
  
  # Check if GitHub CLI is installed
  if command_exists gh; then
    echo "GitHub CLI detected. You can add the secret with this command:"
    echo ""
    echo "gh secret set EC2_SSH_KEY -b\"$(cat $SSH_KEY_FILE)\" --repo $GITHUB_REPO"
    echo ""
    
    read -p "Would you like to add the secret using GitHub CLI now? (y/n): " ADD_SECRET
    if [[ "$ADD_SECRET" =~ ^[Yy]$ ]]; then
      # Check if logged in to GitHub CLI
      if ! gh auth status &>/dev/null; then
        echo "You need to log in to GitHub CLI first."
        gh auth login
      fi
      
      # Add the secret
      if gh secret set EC2_SSH_KEY -b"$(cat $SSH_KEY_FILE)" --repo $GITHUB_REPO; then
        echo "Secret added successfully!"
      else
        echo "Failed to add secret. Please add it manually using the steps above."
      fi
    fi
  else
    echo "For automated addition, install GitHub CLI (gh) from: https://cli.github.com/"
    echo "Then run: gh secret set EC2_SSH_KEY -b\"$(cat $SSH_KEY_FILE)\" --repo $GITHUB_REPO"
  fi
}

# Function to create a new key pair
create_new_key_pair() {
  local KEY_NAME="TwitchCounterKey-$(date +%s)"
  echo "Creating new key pair: $KEY_NAME"
  
  if command_exists aws; then
    # Create new key pair using AWS CLI
    KEY_MATERIAL=$(aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$KEY_MATERIAL" ]; then
      echo "$KEY_MATERIAL" > "$SSH_KEY_FILE"
      chmod 400 "$SSH_KEY_FILE"
      echo "New SSH key created and saved to $SSH_KEY_FILE with proper permissions."
      
      # Add to GitHub if requested or prompt
      if [ "$ADD_TO_GITHUB" = true ]; then
        add_to_github_secrets "$KEY_MATERIAL" "$GITHUB_REPO"
      else
        read -p "Would you like to add this key to GitHub Actions secrets? (y/n): " ADD_TO_GH
        if [[ "$ADD_TO_GH" =~ ^[Yy]$ ]]; then
          add_to_github_secrets "$KEY_MATERIAL" "$GITHUB_REPO"
        fi
      fi
      
      # If we have an instance ID, update it to use the new key
      if [ -n "$INSTANCE_ID" ]; then
        echo "Updating instance to use the new key pair..."
        echo "Note: This requires stopping the instance temporarily."
        
        read -p "Do you want to stop the instance and update its key pair? (y/n): " UPDATE_KEY
        if [[ "$UPDATE_KEY" =~ ^[Yy]$ ]]; then
          # Stop the instance
          echo "Stopping instance $INSTANCE_ID..."
          aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
          
          # Wait for the instance to stop
          echo "Waiting for instance to stop..."
          aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
          
          # Update the key pair
          echo "Updating instance key pair..."
          aws ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --key-name "$KEY_NAME"
          
          # Start the instance
          echo "Starting instance $INSTANCE_ID..."
          aws ec2 start-instances --instance-ids "$INSTANCE_ID"
          
          # Wait for the instance to start
          echo "Waiting for instance to start..."
          aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
          
          # Get the new public DNS
          PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
          echo "Instance restarted with new key pair. Public DNS: $PUBLIC_DNS"
        else
          echo "Skipping instance key pair update."
          echo "Note: You won't be able to connect to the instance with this new key until you update the instance."
        fi
      fi
      
      return 0
    else
      echo "Failed to create new key pair using AWS CLI."
      return 1
    fi
  else
    echo "AWS CLI not available. Cannot create new key pair."
    return 1
  fi
}

# Check if we should use existing key or create a new one
if [ "$CREATE_NEW_KEY" = true ]; then
  # Create new key pair
  create_new_key_pair
elif [ -n "$SSH_KEY_SECRET" ]; then
  # Use provided key
  echo "$SSH_KEY_SECRET" > "$SSH_KEY_FILE"
  chmod 400 "$SSH_KEY_FILE"
  echo "SSH key saved to $SSH_KEY_FILE with proper permissions."
  
  # Add to GitHub if requested
  if [ "$ADD_TO_GITHUB" = true ]; then
    add_to_github_secrets "$SSH_KEY_SECRET" "$GITHUB_REPO"
  fi
elif [ -f "$SSH_KEY_FILE" ]; then
  # Key file exists
  echo "SSH key file already exists at $SSH_KEY_FILE."
  read -p "Do you want to create a new key pair instead? (y/n): " CREATE_NEW
  if [[ "$CREATE_NEW" =~ ^[Yy]$ ]]; then
    create_new_key_pair
  else
    echo "Keeping existing SSH key file."
    
    # Add to GitHub if requested
    if [ "$ADD_TO_GITHUB" = true ]; then
      add_to_github_secrets "$(cat $SSH_KEY_FILE)" "$GITHUB_REPO"
    fi
  fi
else
  # No key file exists
  echo "No SSH key file found."
  read -p "Do you want to create a new key pair? (y/n): " CREATE_NEW
  if [[ "$CREATE_NEW" =~ ^[Yy]$ ]]; then
    create_new_key_pair
  else
    echo "Please paste your existing SSH key content below (Ctrl+D when finished):"
    SSH_KEY_CONTENT=$(cat)
    echo "$SSH_KEY_CONTENT" > "$SSH_KEY_FILE"
    chmod 400 "$SSH_KEY_FILE"
    echo "SSH key saved to $SSH_KEY_FILE with proper permissions."
    
    # Add to GitHub if requested
    if [ "$ADD_TO_GITHUB" = true ]; then
      add_to_github_secrets "$SSH_KEY_CONTENT" "$GITHUB_REPO"
    fi
  fi
fi

# Find instance if not provided
if command_exists aws && [ -z "$INSTANCE_ID" ]; then
  echo "No instance ID provided. Looking for instances with tag Name=TwitchCounter..."
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=TwitchCounter" "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicDnsName]' \
    --output text 2>/dev/null)
  
  if [ -n "$INSTANCES" ]; then
    echo "Found instances:"
    echo "----------------"
    i=1
    declare -a INSTANCE_IDS
    declare -a INSTANCE_STATES
    declare -a INSTANCE_DNS
    
    while read -r ID STATE DNS; do
      echo "$i) Instance $ID (State: $STATE, DNS: $DNS)"
      INSTANCE_IDS[$i]=$ID
      INSTANCE_STATES[$i]=$STATE
      INSTANCE_DNS[$i]=$DNS
      i=$((i+1))
    done <<< "$INSTANCES"
    
    # If only one instance found, use it automatically
    if [ ${#INSTANCE_IDS[@]} -eq 1 ]; then
      INSTANCE_ID=${INSTANCE_IDS[1]}
      PUBLIC_DNS=${INSTANCE_DNS[1]}
      echo "Using the only instance found: $INSTANCE_ID"
    else
      read -p "Enter the number of the instance to use (1-$((i-1))): " SELECTION
      if [[ ! $SELECTION =~ ^[0-9]+$ ]] || [ $SELECTION -lt 1 ] || [ $SELECTION -ge $i ]; then
        echo "Invalid selection"
      else
        INSTANCE_ID=${INSTANCE_IDS[$SELECTION]}
        PUBLIC_DNS=${INSTANCE_DNS[$SELECTION]}
        echo "Selected instance: $INSTANCE_ID"
      fi
    fi
    
    # Update .env file with instance ID
    if [ -n "$INSTANCE_ID" ]; then
      sed -i.bak "s/INSTANCE_ID=.*/INSTANCE_ID=$INSTANCE_ID/" .env 2>/dev/null || sed -i "" "s/INSTANCE_ID=.*/INSTANCE_ID=$INSTANCE_ID/" .env
      rm -f .env.bak 2>/dev/null
    fi
  else
    echo "No instances found with tag Name=TwitchCounter"
  fi
fi

# Create SSH config file
if [ -n "$INSTANCE_ID" ] && command_exists aws; then
  echo "Setting up SSH config..."
  
  if [ -z "$PUBLIC_DNS" ]; then
    PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicDnsName' --output text 2>/dev/null)
  fi
  
  if [ -n "$PUBLIC_DNS" ] && [ "$PUBLIC_DNS" != "None" ]; then
    mkdir -p ~/.ssh
    
    # Check if config already has an entry for this host
    if grep -q "Host twitch-counter" ~/.ssh/config 2>/dev/null; then
      echo "SSH config already has an entry for twitch-counter."
      read -p "Do you want to update it? (y/n): " UPDATE_CONFIG
      if [[ "$UPDATE_CONFIG" =~ ^[Yy]$ ]]; then
        # Remove existing entry
        sed -i.bak '/Host twitch-counter/,/^$/d' ~/.ssh/config 2>/dev/null || sed -i "" '/Host twitch-counter/,/^$/d' ~/.ssh/config
        rm -f ~/.ssh/config.bak 2>/dev/null
        
        # Add new entry
        cat >> ~/.ssh/config << EOF

Host twitch-counter
    HostName $PUBLIC_DNS
    User ec2-user
    IdentityFile $(pwd)/$SSH_KEY_FILE
    StrictHostKeyChecking no
    ServerAliveInterval 60

EOF
        echo "SSH config updated."
      fi
    else
      # Add new entry
      cat >> ~/.ssh/config << EOF

Host twitch-counter
    HostName $PUBLIC_DNS
    User ec2-user
    IdentityFile $(pwd)/$SSH_KEY_FILE
    StrictHostKeyChecking no
    ServerAliveInterval 60

EOF
      echo "SSH config created."
    fi
    
    echo "You can now connect to your instance using: ssh twitch-counter"
  else
    echo "Could not determine public DNS for instance $INSTANCE_ID"
    echo "You can connect using: ssh -i $SSH_KEY_FILE ec2-user@<public-dns>"
  fi
fi

# Download troubleshooting scripts if they don't exist
echo "Checking for troubleshooting scripts..."

if [ ! -f "check_instance.sh" ]; then
  echo "Downloading check_instance.sh..."
  curl -s -O https://raw.githubusercontent.com/$GITHUB_REPO/main/check_instance.sh
  chmod +x check_instance.sh
fi

if [ ! -f "ssh_troubleshoot.sh" ]; then
  echo "Downloading ssh_troubleshoot.sh..."
  curl -s -O https://raw.githubusercontent.com/$GITHUB_REPO/main/ssh_troubleshoot.sh
  chmod +x ssh_troubleshoot.sh
fi

echo ""
echo "Local setup completed!"
echo "======================="
echo ""
if [ -n "$INSTANCE_ID" ] && [ -n "$PUBLIC_DNS" ] && [ "$PUBLIC_DNS" != "None" ]; then
  echo "Your instance is ready to connect:"
  echo "  Instance ID: $INSTANCE_ID"
  echo "  Public DNS:  $PUBLIC_DNS"
  echo ""
  echo "Connect using: ssh twitch-counter"
  echo "Or:            ssh -i $SSH_KEY_FILE ec2-user@$PUBLIC_DNS"
  echo ""
  echo "Application URL: http://$PUBLIC_DNS:8080"
else
  echo "Instance information is incomplete."
  echo "You may need to run the deployment workflow first."
  echo ""
  echo "For troubleshooting:"
  echo "  ./check_instance.sh     - Check instance status"
  echo "  ./ssh_troubleshoot.sh   - Diagnose SSH connectivity issues"
fi
echo ""
echo "For more information, see the documentation:"
echo "  - AWS Setup Guide: aws-setup.md"
echo "  - SSH Troubleshooting Guide: ssh_troubleshooting.md"
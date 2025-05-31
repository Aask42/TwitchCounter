#!/bin/bash

# Twitch Counter AWS Setup Script
# This script sets up the Twitch Word Counter on an AWS EC2 instance

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Prompt for AWS region, Namecheap domain and DDNS password
read -p "Enter your AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter your Namecheap domain (e.g., example.com): " DOMAIN
read -p "Enter your Namecheap DDNS password: " DDNS_PASSWORD

# Set AWS region
export AWS_REGION=$AWS_REGION

# Update system
echo "Updating system packages..."
yum update -y

# Install Docker
echo "Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Nginx
echo "Installing Nginx..."
yum install -y nginx
systemctl start nginx
systemctl enable nginx

# Create DDNS update script
echo "Creating DDNS update script..."
cat > /home/ec2-user/update_ddns.sh << EOF
#!/bin/bash

# Namecheap DDNS update script
DOMAIN="$DOMAIN"
PASSWORD="$DDNS_PASSWORD"
HOST="@"
IP=\$(curl -s https://checkip.amazonaws.com)

# Update DDNS record
curl -s "https://dynamicdns.park-your-domain.com/update?host=\$HOST&domain=\$DOMAIN&password=\$PASSWORD&ip=\$IP"

echo "DDNS updated for \$DOMAIN with IP \$IP"
EOF

chmod +x /home/ec2-user/update_ddns.sh
chown ec2-user:ec2-user /home/ec2-user/update_ddns.sh

# Set up cron job for DDNS updates
echo "Setting up DDNS update cron job..."
(crontab -u ec2-user -l 2>/dev/null; echo "*/10 * * * * /home/ec2-user/update_ddns.sh") | crontab -u ec2-user -

# Clone the repository
echo "Cloning the Twitch Counter repository..."
if [ -d "/home/ec2-user/TwitchCounter" ]; then
  cd /home/ec2-user/TwitchCounter
  git pull
else
  git clone https://github.com/Aask42/TwitchCounter.git /home/ec2-user/TwitchCounter
  cd /home/ec2-user/TwitchCounter
fi

# Create .env file
echo "Creating .env file..."
cat > /home/ec2-user/TwitchCounter/.env << EOF
TWITCH_CHANNEL=skittishandbus
TARGET_WORDS=fuck,shit,damn
EOF

chown ec2-user:ec2-user /home/ec2-user/TwitchCounter/.env

# Create Nginx configuration
echo "Configuring Nginx..."
cat > /etc/nginx/conf.d/twitch-counter.conf << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Test and reload Nginx
nginx -t
systemctl reload nginx

# Run DDNS update script
echo "Updating DDNS..."
/home/ec2-user/update_ddns.sh

# Start the application
echo "Starting the application..."
cd /home/ec2-user/TwitchCounter
docker-compose up -d

echo "Setup completed!"
echo "Your Twitch Word Counter is now running at http://$DOMAIN"
echo ""
echo "To view logs: docker-compose logs -f"
echo "To restart: docker-compose restart"
echo "To stop: docker-compose down"
# Twitch Word Counter

A Python tool that captures audio from a Twitch stream and counts occurrences of specific words (like "fuck") in real-time on the command line.

## Features

- Connect to any Twitch stream and capture audio
- Process audio using speech recognition
- Count occurrences of specified target words in real-time
- Colorful command-line interface
- Save statistics to a JSON file when the program exits
- Support for multiple target words

## Requirements

- Python 3.7+
- FFmpeg installed on your system

## Installation

1. Clone this repository or download the files
2. Install FFmpeg on your system:
   - **Ubuntu/Debian**: `sudo apt-get install ffmpeg`
   - **macOS**: `brew install ffmpeg`
   - **Windows**: Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to PATH
3. Install the required Python dependencies:

```bash
pip install -r requirements.txt
```

## Usage

Basic usage:

```bash
python twitch_word_counter.py CHANNEL_NAME
```

This will connect to the specified channel's stream and count occurrences of the default word "fuck" in the audio.

To count occurrences of different words:

```bash
python twitch_word_counter.py CHANNEL_NAME --words word1 word2 word3
```

To specify a different stream quality:

```bash
python twitch_word_counter.py CHANNEL_NAME --quality best
```

Example:

```bash
python twitch_word_counter.py ninja --words fuck damn shit
```

This will connect to Ninja's Twitch stream and count occurrences of "fuck", "damn", and "shit" in the audio.

## How It Works

1. The tool uses Streamlink to connect to the Twitch stream
2. FFmpeg extracts the audio from the stream
3. The audio is processed in chunks using PyAudio
4. Speech recognition (Google Speech Recognition API) is used to convert audio to text
5. The text is analyzed for occurrences of the target words
6. Counts are displayed in real-time on the command line

## Notes

- The accuracy depends on the quality of the stream audio and the speech recognition
- Background noise, music, or multiple people talking at once may reduce accuracy
- The program will save statistics to a JSON file named "word_count_stats.json" when you exit (Ctrl+C)
- The word matching is case-insensitive and matches whole words only
- Internet connection is required for the speech recognition API

## Docker and Ngrok Setup

You can run this application in Docker and expose it via ngrok for remote access:

### Prerequisites

- Docker and Docker Compose installed
- Ngrok account and authtoken

### Running with Docker

1. Clone the repository:
   ```bash
   git clone https://github.com/Aask42/TwitchCounter.git
   cd TwitchCounter
   ```

2. Create a `.env` file with your configuration:
   ```
   TWITCH_CHANNEL=skittishandbus
   TARGET_WORDS=fuck,shit,damn
   NGROK_AUTHTOKEN=your_ngrok_authtoken
   ```

3. Build and run the Docker containers:
   ```bash
   docker-compose up -d
   ```

4. Access the web interface:
   - Locally: http://localhost:8080
   - Ngrok URL: Check the ngrok dashboard at http://localhost:4040

### Stopping the Application

```bash
docker-compose down
```

## AWS Deployment

For instructions on deploying this application to an AWS free tier server with a custom domain, see the [AWS Setup Guide](aws-setup.md).

For help with setting up GitHub secrets and environment variables for automated deployment, see the [GitHub Secrets Guide](github-secrets-guide.md).

For troubleshooting SSH connectivity issues, see the [SSH Troubleshooting Guide](ssh_troubleshooting.md).

### Deployment and Setup Scripts

The repository includes several scripts to help with AWS deployment and management:

- **setup.sh**: Sets up the application on an EC2 instance, checking for existing deployments first
- **local_setup.sh**: Sets up your local environment for connecting to the EC2 instance
- **cleanup_aws.sh**: Cleans up AWS resources (instances, security groups, key pairs)
- **check_instance.sh**: Checks the status of EC2 instances and helps troubleshoot connectivity issues
- **ssh_troubleshoot.sh**: Provides comprehensive SSH connectivity diagnostics and fixes

#### Using local_setup.sh

The `local_setup.sh` script helps you set up your local environment for connecting to the EC2 instance:

```bash
# Run with interactive prompts
./local_setup.sh

# Create a new AWS key pair and add to GitHub secrets
./local_setup.sh --create-key --add-to-github

# Create a new AWS key pair (interactive prompts)
./local_setup.sh --create-key

# Add existing key to GitHub secrets
./local_setup.sh --add-to-github

# Provide existing SSH key content directly
./local_setup.sh --key-secret "$(cat path/to/your/key.pem)"

# Specify instance ID and region
./local_setup.sh --instance-id i-1234567890abcdef0 --region us-west-2
```

This script:
- Creates a new AWS key pair or uses an existing SSH key
- Can add the SSH key to GitHub Actions secrets automatically
- If creating a new key pair, can update your EC2 instance to use it
- Sets up SSH config for easy connection to your instance
- Creates a .env file with your configuration
- Downloads troubleshooting scripts if needed
- Provides connection instructions

#### Using check_instance.sh

The `check_instance.sh` script helps you check the status of your EC2 instances and troubleshoot connectivity issues:

```bash
# Check all instances with the TwitchCounter tag
./check_instance.sh

# Check a specific instance
./check_instance.sh --instance-id i-1234567890abcdef0

# Wait for SSH to become available (useful for new instances)
./check_instance.sh --wait-for-ssh --timeout 600
```

This script provides detailed information about your instance, including:
- Instance state and uptime
- Public and private IP addresses
- Security group rules (checking if SSH is allowed)
- Console output for troubleshooting
- SSH connection instructions

#### Using ssh_troubleshoot.sh

The `ssh_troubleshoot.sh` script provides comprehensive diagnostics and fixes for SSH connectivity issues:

```bash
# Run with interactive prompts
./ssh_troubleshoot.sh

# Check a specific instance with a specific key file
./ssh_troubleshoot.sh --instance-id i-1234567890abcdef0 --key-file TwitchCounterKey.pem

# Automatically fix common issues
./ssh_troubleshoot.sh --fix
```

This script helps diagnose and fix common SSH issues:
- Locates and verifies SSH key files
- Checks and fixes key file permissions
- Verifies security group rules for SSH access
- Tests network connectivity to the instance
- Provides detailed SSH connection diagnostics

## License

MIT
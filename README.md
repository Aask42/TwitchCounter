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

## License

MIT
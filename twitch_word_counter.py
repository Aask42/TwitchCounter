#!/usr/bin/env python3
"""
Twitch Word Counter
A tool that captures audio from a Twitch stream and counts occurrences of specified words in real-time.
"""

import argparse
import os
import sys
import time
import re
import threading
import queue
import json
import subprocess
import tempfile
from collections import Counter
from datetime import datetime

try:
    import speech_recognition as sr
    import streamlink
    import pyaudio
    import wave
    import ffmpeg
    from pydub import AudioSegment
    from pydub.silence import split_on_silence
    from dotenv import load_dotenv
    import colorama
    from colorama import Fore, Style
except ImportError:
    print("Required packages not found. Please run: pip install -r requirements.txt")
    sys.exit(1)

# Initialize colorama
colorama.init()

class TwitchWordCounter:
    def __init__(self, channel_name, target_words=None, quality="audio_only"):
        """Initialize the Twitch Word Counter."""
        self.channel_name = channel_name.lower()
        self.target_words = [word.lower() for word in target_words] if target_words else ["fuck"]
        self.word_counts = Counter()
        self.start_time = datetime.now()
        self.quality = quality
        self.stream_url = f"https://twitch.tv/{self.channel_name}"
        self.running = False
        self.audio_queue = queue.Queue()
        self.recognizer = sr.Recognizer()
        
        # Audio parameters
        self.format = pyaudio.paInt16
        self.channels = 1
        self.rate = 16000
        self.chunk = 1024
        self.record_seconds = 5
        
        print(f"{Fore.CYAN}Initializing Twitch Word Counter for channel: {self.channel_name}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}Tracking words: {', '.join(self.target_words)}{Style.RESET_ALL}")

    def start(self):
        """Start the word counter."""
        self.running = True
        
        # Start threads
        stream_thread = threading.Thread(target=self.stream_audio)
        process_thread = threading.Thread(target=self.process_audio)
        
        stream_thread.daemon = True
        process_thread.daemon = True
        
        stream_thread.start()
        process_thread.start()
        
        # Display initial counts
        print("\n" + "-" * 50)
        self.display_counts()
        
        try:
            # Keep the main thread alive
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            self.running = False
            print(f"\n{Fore.YELLOW}Counter stopped by user.{Style.RESET_ALL}")
            self.save_stats()
            print(f"{Fore.GREEN}Thanks for using Twitch Word Counter!{Style.RESET_ALL}")
            sys.exit(0)

    def stream_audio(self):
        """Stream audio from the Twitch channel."""
        try:
            print(f"{Fore.YELLOW}Connecting to stream: {self.stream_url}{Style.RESET_ALL}")
            
            # Get stream URL using streamlink
            streams = streamlink.streams(self.stream_url)
            if not streams:
                print(f"{Fore.RED}No streams found for {self.channel_name}{Style.RESET_ALL}")
                sys.exit(1)
                
            # Use audio_only if available, otherwise use lowest quality
            if self.quality in streams:
                stream = streams[self.quality]
            else:
                available_qualities = list(streams.keys())
                print(f"{Fore.YELLOW}Quality '{self.quality}' not available. Available qualities: {', '.join(available_qualities)}{Style.RESET_ALL}")
                stream = streams[available_qualities[0]]
                
            print(f"{Fore.GREEN}Successfully connected to stream!{Style.RESET_ALL}")
            print(f"{Fore.YELLOW}Capturing audio...{Style.RESET_ALL}")
            
            # Use ffmpeg to extract audio from the stream
            cmd = [
                "ffmpeg",
                "-i", stream.url,
                "-f", "wav",
                "-ar", str(self.rate),
                "-ac", str(self.channels),
                "-"
            ]
            
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL
            )
            
            # Read audio data in chunks and put it in the queue
            audio = pyaudio.PyAudio()
            stream = audio.open(
                format=self.format,
                channels=self.channels,
                rate=self.rate,
                output=True,
                frames_per_buffer=self.chunk
            )
            
            # Calculate how many chunks make up our recording interval
            chunks_per_recording = int(self.rate / self.chunk * self.record_seconds)
            frames = []
            
            while self.running:
                # Read a chunk of audio data
                data = process.stdout.read(self.chunk)
                if not data:
                    break
                    
                # Play the audio (optional, can be commented out)
                # stream.write(data)
                
                # Add the chunk to our current recording
                frames.append(data)
                
                # If we've collected enough chunks for a recording, process it
                if len(frames) >= chunks_per_recording:
                    # Create a temporary WAV file
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
                        temp_filename = temp_file.name
                        
                    # Write the frames to the temporary file
                    with wave.open(temp_filename, 'wb') as wf:
                        wf.setnchannels(self.channels)
                        wf.setsampwidth(audio.get_sample_size(self.format))
                        wf.setframerate(self.rate)
                        wf.writeframes(b''.join(frames))
                    
                    # Add the file to the queue for processing
                    self.audio_queue.put(temp_filename)
                    
                    # Reset frames for the next recording
                    frames = []
            
            # Clean up
            stream.stop_stream()
            stream.close()
            audio.terminate()
            process.terminate()
            
        except Exception as e:
            print(f"{Fore.RED}Error streaming audio: {str(e)}{Style.RESET_ALL}")
            self.running = False
            sys.exit(1)

    def process_audio(self):
        """Process audio files from the queue and perform speech recognition."""
        while self.running:
            try:
                # Get an audio file from the queue
                if self.audio_queue.empty():
                    time.sleep(0.1)
                    continue
                    
                audio_file = self.audio_queue.get()
                
                # Load the audio file
                audio = AudioSegment.from_wav(audio_file)
                
                # Split audio on silence to get chunks with speech
                chunks = split_on_silence(
                    audio,
                    min_silence_len=500,
                    silence_thresh=-40
                )
                
                # Process each chunk
                for i, chunk in enumerate(chunks):
                    # Save the chunk to a temporary file
                    chunk_filename = f"{audio_file}_chunk_{i}.wav"
                    chunk.export(chunk_filename, format="wav")
                    
                    # Perform speech recognition
                    with sr.AudioFile(chunk_filename) as source:
                        audio_data = self.recognizer.record(source)
                        try:
                            text = self.recognizer.recognize_google(audio_data).lower()
                            
                            # Check for target words
                            for word in self.target_words:
                                pattern = r'\b' + re.escape(word) + r'\b'
                                count = len(re.findall(pattern, text))
                                
                                if count > 0:
                                    self.word_counts[word] += count
                                    self.display_counts()
                                    
                                    # Print the transcribed text that contained the word
                                    print(f"{Fore.CYAN}Transcribed:{Style.RESET_ALL} {text}")
                                    print("-" * 50)
                        except sr.UnknownValueError:
                            # Speech was unintelligible
                            pass
                        except sr.RequestError as e:
                            print(f"{Fore.RED}Error with speech recognition service: {str(e)}{Style.RESET_ALL}")
                    
                    # Clean up the chunk file
                    try:
                        os.remove(chunk_filename)
                    except:
                        pass
                
                # Clean up the original audio file
                try:
                    os.remove(audio_file)
                except:
                    pass
                
                # Mark the task as done
                self.audio_queue.task_done()
                
            except Exception as e:
                print(f"{Fore.RED}Error processing audio: {str(e)}{Style.RESET_ALL}")
                continue

    def get_elapsed_time(self):
        """Get the elapsed time since the counter started."""
        elapsed_time = datetime.now() - self.start_time
        hours, remainder = divmod(elapsed_time.seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        
        return {
            "hours": hours,
            "minutes": minutes,
            "seconds": seconds
        }
        
    def display_counts(self):
        """Display the current word counts."""
        # Clear the previous lines
        sys.stdout.write("\033[F" * (len(self.target_words) + 2))
        
        # Get elapsed time
        time_info = self.get_elapsed_time()
        hours = time_info["hours"]
        minutes = time_info["minutes"]
        seconds = time_info["seconds"]
        
        print(f"{Fore.YELLOW}Word Count - Running for {hours:02}:{minutes:02}:{seconds:02}{Style.RESET_ALL}")
        
        # Print counts for each target word
        for word in self.target_words:
            count = self.word_counts[word]
            print(f"{Fore.GREEN}{word}: {Fore.WHITE}{count}{Style.RESET_ALL}")
        
        print("-" * 50)

    def save_stats(self, filename="word_count_stats.json"):
        """Save the current statistics to a JSON file."""
        stats = {
            "channel": self.channel_name,
            "target_words": {word: self.word_counts[word] for word in self.target_words},
            "start_time": self.start_time.isoformat(),
            "end_time": datetime.now().isoformat()
        }
        
        with open(filename, 'w') as f:
            json.dump(stats, f, indent=4)
            
        print(f"{Fore.GREEN}Statistics saved to {filename}{Style.RESET_ALL}")

def main():
    """Main entry point for the application."""
    parser = argparse.ArgumentParser(description="Count occurrences of specific words in a Twitch stream's audio.")
    parser.add_argument("channel", help="Twitch channel name")
    parser.add_argument("--words", "-w", nargs="+", default=["fuck"],
                        help="Target words to count (default: 'fuck')")
    parser.add_argument("--quality", "-q", default="audio_only",
                        help="Stream quality (default: audio_only)")
    
    args = parser.parse_args()
    
    # Load environment variables from .env file if it exists
    load_dotenv()
    
    # Create and run the counter
    counter = TwitchWordCounter(
        args.channel,
        args.words,
        args.quality
    )
    
    counter.start()

if __name__ == "__main__":
    main()
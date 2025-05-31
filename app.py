#!/usr/bin/env python3
"""
Twitch Word Counter with HTTP Interface
"""

import os
import threading
import time
from flask import Flask, render_template, jsonify
from twitch_word_counter import TwitchWordCounter

# Get environment variables
TWITCH_CHANNEL = os.environ.get('TWITCH_CHANNEL', 'asmongold')
TARGET_WORDS = os.environ.get('TARGET_WORDS', 'fuck').split(',')

# Initialize Flask app
app = Flask(__name__)

# Initialize the counter
counter = TwitchWordCounter(TWITCH_CHANNEL, TARGET_WORDS)

# Create a global variable to access word counts from Flask routes
word_counts = {}
running_time = {"hours": 0, "minutes": 0, "seconds": 0}

@app.route('/')
def index():
    """Render the main page with word counts."""
    return render_template('index.html', 
                          channel=TWITCH_CHANNEL, 
                          word_counts=word_counts,
                          running_time=running_time)

@app.route('/api/counts')
def get_counts():
    """Return word counts as JSON for API access."""
    return jsonify({
        "channel": TWITCH_CHANNEL,
        "counts": word_counts,
        "running_time": running_time
    })

def update_counts():
    """Update the global word_counts variable from the counter."""
    global word_counts, running_time
    while True:
        # Update word counts
        for word in counter.target_words:
            word_counts[word] = counter.word_counts[word]
        
        # Update running time
        elapsed_time = counter.get_elapsed_time()
        running_time["hours"] = elapsed_time["hours"]
        running_time["minutes"] = elapsed_time["minutes"]
        running_time["seconds"] = elapsed_time["seconds"]
        
        time.sleep(1)

def run_counter():
    """Run the Twitch word counter in a separate thread."""
    counter.start()

if __name__ == "__main__":
    # Create templates directory if it doesn't exist
    os.makedirs('templates', exist_ok=True)
    
    # Start the counter in a separate thread
    counter_thread = threading.Thread(target=run_counter)
    counter_thread.daemon = True
    counter_thread.start()
    
    # Start the update thread
    update_thread = threading.Thread(target=update_counts)
    update_thread.daemon = True
    update_thread.start()
    
    # Run the Flask app
    app.run(host='0.0.0.0', port=8080)
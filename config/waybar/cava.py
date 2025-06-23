#!/usr/bin/env python3
import subprocess
import json
import sys

# FIX: Use solid block characters for a thicker, more modern look
bars = [" ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
# Cava configuration path
config_path = "/home/ackerman/.config/cava/config"
# Use the full, absolute path to the cava executable to avoid PATH issues.
cava_executable = "/usr/bin/cava"

def main():
    # Start the Cava process using the full path
    process = subprocess.Popen(
        [cava_executable, "-p", config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    for line in iter(process.stdout.readline, ""):
        try:
            # Read the raw output from Cava
            raw_values = line.strip().split(";")
            
            # Convert values to integers
            values = [int(v) for v in raw_values if v]
            
            # Map each integer value to a bar character
            output_str = "".join(bars[min(v, len(bars) - 1)] for v in values)
            
            # Prepare the JSON output for Waybar
            # The 'class' allows for specific CSS styling
            waybar_output = {"text": output_str, "class": "cava-wave", "tooltip": "Audio Visualizer"}
            
            # Print the JSON to stdout for Waybar to read
            print(json.dumps(waybar_output), flush=True)

        except (ValueError, IndexError) as e:
            sys.stderr.write(f"Error processing Cava output: {e}\n")
        except Exception as e:
            sys.stderr.write(f"An unexpected error occurred: {e}\n")
            break

    process.stdout.close()
    err = process.stderr.read()
    if err:
        sys.stderr.write(f"Cava stderr: {err}\n")

if __name__ == "__main__":
    main()

# Mac Mini Transcription Runner

This document describes how the Mac mini should run the audio transcription pipeline for Notion Journal.

## What the Mac mini does
1. Launch Notion Journal and keep it running.
1. When the app becomes active, it scans for audio blocks missing transcripts.
1. For each missing transcript, it runs the dual-pass Whisper flow and writes the transcript back into `payload_json`.
1. Once the transcript is saved, the block appears in Clipboard Inbox for import.

## Requirements
1. `python3` installed and available in `PATH`.
1. `ffmpeg` and `ffprobe` installed and available in `PATH`.
1. Python package `mlx_whisper` installed in the environment used by `python3`.
1. The Mac mini must be signed into iCloud with access to `iCloud.com.CYC.NotionJournal`.

## What to check if transcription is not running
1. Make sure Notion Journal is open and active at least once after new audio arrives.
1. Confirm `ffmpeg` and `ffprobe` exist.
1. Confirm `python3 -c "import mlx_whisper"` succeeds.
1. Check app logs for lines starting with `NJ_AUDIO_TRANSCRIBE`.

## Behavior notes
1. Audio blocks do not appear in Clipboard Inbox until `transcript_txt` is written.
1. The transcript text is written into both:
1. `sections.audio.data.transcript_txt`
1. `sections.proton1.data.rtf_base64`

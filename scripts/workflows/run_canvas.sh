#!/usr/bin/env bash

# Workflow script for Canvas submissions

usage() {
  cat <<EOF
Usage: $(basename "$0") [-qcea]

Runs the processing pipeline for Canvas submissions based on flags.
Expects COURSE_ID and ASSIGNMENT_ID environment variables to be set.
Reads CANVAS_API_KEY and CANVAS_BASE_URL from environment.

Steps controlled by flags (defaults to all applicable steps):
  -q: Run acquisition
  -c: Run conversion
  -e: Run extraction
  -a: Run assessment

Flags are passed down from main.sh.

Pipeline: Acquire -> Convert -> Extract -> Assess
EOF
}
set -euo pipefail

# Default directories (can be overridden by env vars if needed later)
sub_dir="./submissions"
image_dir="./images"
text_dir="./text"
assessment_dir="./assessment"
steps_dir="./scripts/steps" # Location of step scripts

# Parse step flags passed from main.sh
acquire_flag=false
convert_flag=false
extract_flag=false
assess_flag=false
run_all_steps=false

# Simple check if any flags are passed; if not, run all
if [[ "$#" -eq 0 ]]; then
  run_all_steps=true
else
  while getopts "qcea" opt; do
    case $opt in
      q) acquire_flag=true ;;
      c) convert_flag=true ;;
      e) extract_flag=true ;;
      a) assess_flag=true ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND -1))

  # If specific flags were passed, only run those. If no flags, run all.
  if [ "$acquire_flag" = false ] && [ "$convert_flag" = false ] && [ "$extract_flag" = false ] && [ "$assess_flag" = false ]; then
      run_all_steps=true
  fi
fi


# If run_all_steps is true, enable all flags
if [ "$run_all_steps" = true ]; then
  acquire_flag=true
  convert_flag=true
  extract_flag=true
  assess_flag=true
fi

echo "--- Canvas Workflow ---"
echo "Steps to run: Acquire=$acquire_flag Convert=$convert_flag Extract=$extract_flag Assess=$assess_flag"

# Ensure output directories exist (safer to check here too)
mkdir -p "$sub_dir" "$image_dir" "$text_dir" "$assessment_dir"

# --- Processing Stages ---

# 0. Acquisition step
if [ "$acquire_flag" = true ]; then
  echo "--- Running Acquisition ---"
  # Required env vars COURSE_ID, ASSIGNMENT_ID, CANVAS_API_KEY, CANVAS_BASE_URL checked by step script
  # Pass SUBMISSIONS_DIR
  if ! SUBMISSIONS_DIR="$sub_dir" "$steps_dir/acquire_canvas_submissions.sh"; then
    echo "Error: Canvas acquisition failed." >&2
    exit 1
  fi
  echo "--- Acquisition Complete ---"

  # Check if submissions dir is empty after acquisition attempt before proceeding
  if [ "$convert_flag" = true ] || [ "$extract_flag" = true ] || [ "$assess_flag" = true ]; then
      if [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
        echo "Warning: No files found in '$sub_dir' after acquisition. Subsequent steps may have no input." >&2
        # Decide whether to exit or continue (maybe user only wanted acquire)
        # Let's continue but subsequent steps will likely do nothing.
      fi
  fi

else
  echo "--- Skipping Acquisition ---"
fi

# 1. Conversion step
if [ "$convert_flag" = true ]; then
  echo "--- Running Conversion ---"
  processed_count=0
  error_count=0
  any_output_generated=false # Flag to track if *any* convertible files were processed successfully

  if [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
      echo "No files found in '$sub_dir' to convert. Skipping."
  else
      echo "Converting files in '$sub_dir'..."
      shopt -s nullglob # Avoid errors if glob matches nothing
      for input_file in "$sub_dir"/*; do
        # Skip directories if any exist
        if [ -d "$input_file" ]; then
          continue
        fi
        echo "Processing file: '$(basename "$input_file")'"
        # Call the conversion step script
        if ! "$steps_dir/convert_submission_file.sh" "$input_file"; then
          echo "Error converting '$(basename "$input_file")'." >&2
          ((error_count++))
        else
          ((processed_count++))
          any_output_generated=true # Mark that at least one conversion likely succeeded/skipped appropriately
        fi
      done
      shopt -u nullglob

      echo "Conversion Summary: $processed_count files attempted, $error_count errors."
      if [ $error_count -gt 0 ]; then
        echo "Warning: Some conversion errors occurred." >&2
        # Decide if this should be a fatal error for the workflow
        # exit 1
      fi
  fi

  # Check if any processable files (PNG or MD) exist before extraction/assessment
  # This check is tricky because conversion might produce MD directly
  if [ "$extract_flag" = true ] || [ "$assess_flag" = true ]; then
      if ! $any_output_generated && [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
          echo "Warning: No processable files (PNGs in $image_dir or MDs in $text_dir) seem to exist after conversion." >&2
          # Don't disable flags, let the steps handle empty input dirs if necessary
      fi
  fi
  echo "--- Conversion Complete ---"
else
  echo "--- Skipping Conversion ---"
fi

# 2. Extract Text (from PNGs if needed)
if [ "$extract_flag" = true ]; then
  echo "--- Running Text Extraction ---"
  processed_count=0
  error_count=0

  if [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ]; then
      echo "No PNG files found in '$image_dir' to extract text from. Skipping."
  else
      echo "Extracting text from PNGs in '$image_dir'..."
      shopt -s nullglob
      for png_file in "$image_dir"/*.png; do
        echo "Processing image: '$(basename "$png_file")'"
        if ! "$steps_dir/extract_text_from_image.sh" "$png_file"; then
          echo "Error extracting text from '$(basename "$png_file")'." >&2
          ((error_count++))
        else
          ((processed_count++))
        fi
      done
      shopt -u nullglob

      echo "Extraction Summary: $processed_count files processed, $error_count errors."
      if [ $error_count -gt 0 ]; then
          echo "Warning: Some text extraction errors occurred." >&2
          # exit 1
      fi
  fi

  # Check if any text files exist in text_dir before assessment
  if [ "$assess_flag" = true ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
    echo "Warning: No text files found in '$text_dir' after extraction. Cannot proceed with assessment." >&2
    assess_flag=false # Disable assessment if no text files
  fi
   echo "--- Text Extraction Complete ---"
else
  echo "--- Skipping Text Extraction ---"
fi

# 3. Assess Assignments
if [ "$assess_flag" = true ]; then
  echo "--- Running Assessment ---"
  processed_count=0
  error_count=0

  if [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
      echo "No markdown files found in '$text_dir' to assess. Skipping."
  else
      echo "Assessing markdown files in '$text_dir'..."
      shopt -s nullglob
      for text_file in "$text_dir"/*.md; do
        echo "Processing text file: '$(basename "$text_file")'"
        if ! "$steps_dir/assess_assignment_text.sh" "$text_file"; then
          echo "Error assessing '$(basename "$text_file")'." >&2
          ((error_count++))
        else
          ((processed_count++))
        fi
      done
      shopt -u nullglob

      echo "Assessment Summary: $processed_count files assessed, $error_count errors."
       if [ $error_count -gt 0 ]; then
          echo "Warning: Some assessment errors occurred." >&2
          # exit 1
      fi
  fi
  echo "--- Assessment Complete ---"
else
  echo "--- Skipping Assessment ---"
fi

echo "--- Canvas Workflow Finished ---"
exit 0

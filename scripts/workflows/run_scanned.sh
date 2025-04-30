#!/usr/bin/env bash

# Workflow script for Scanned PDF submissions

usage() {
  cat <<EOF
Usage: $(basename "$0") [-cea]

Runs the processing pipeline for scanned PDF submissions based on flags.
Assumes input PDFs are placed in ./submissions/ manually.

Steps controlled by flags (defaults to all applicable steps):
  -c: Run conversion (PDF -> PNG)
  -e: Run extraction (PNG -> MD)
  -a: Run assessment (MD -> Assessment)

Flags are passed down from main.sh.

Pipeline: Convert -> Extract -> Assess
EOF
}
# Removing set -e to handle errors within loops explicitly
# set -euo pipefail

# Default directories (can be overridden by env vars if needed later)
sub_dir="./submissions" # Input PDFs here
image_dir="./images"    # Output PNGs here
text_dir="./text"       # Output MD here
assessment_dir="./assessment" # Output Assessments here
steps_dir="./scripts/steps" # Location of step scripts

# Global flag to track if any step failed during the workflow run
workflow_error_occurred=false

# Parse step flags passed from main.sh
convert_flag=false
extract_flag=false
assess_flag=false
run_all_steps=false

# Simple check if any flags are passed; if not, run all
if [[ "$#" -eq 0 ]]; then
  run_all_steps=true
else
  while getopts "cea" opt; do
    case $opt in
      c) convert_flag=true ;;
      e) extract_flag=true ;;
      a) assess_flag=true ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND -1))

    # If specific flags were passed, only run those. If no flags, run all.
  if [ "$convert_flag" = false ] && [ "$extract_flag" = false ] && [ "$assess_flag" = false ]; then
      run_all_steps=true
  fi
fi


# If run_all_steps is true, enable all flags
if [ "$run_all_steps" = true ]; then
  convert_flag=true
  extract_flag=true
  assess_flag=true
fi

echo "--- Scanned PDF Workflow ---"
echo "Steps to run: Convert=$convert_flag Extract=$extract_flag Assess=$assess_flag"

# Ensure output directories exist (safer to check here too)
mkdir -p "$sub_dir" "$image_dir" "$text_dir" "$assessment_dir"


# Check for input files in submissions if conversion is requested
if [ "$convert_flag" = true ] && [ -z "$(ls -A "$sub_dir"/*.pdf 2>/dev/null)" ]; then
    echo "Warning: No PDF files found in '$sub_dir'. Conversion step expects PDFs." >&2
    # Don't exit, maybe user wants to run extract/assess on existing files
    # Or maybe conversion handles other types placed here? Let convert step manage.
fi

# --- Processing Stages ---

# 1. Conversion step (PDFs -> PNGs)
if [ "$convert_flag" = true ]; then
  echo "--- Running Conversion ---"
  processed_count=0
  error_count=0
  any_png_output=false

  if [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
      echo "No files found in '$sub_dir' to convert. Skipping."
  else
      echo "Converting files in '$sub_dir'..."
      shopt -s nullglob # Avoid errors if glob matches nothing
      for input_file in "$sub_dir"/*; do
        # Skip directories if any exist
        [ -d "$input_file" ] && continue

         echo "Processing file: '$(basename "$input_file")'"
         # Call the conversion step script
        if ! "$steps_dir/convert_submission_file.sh" "$input_file"; then
           echo "Error converting '$(basename "$input_file")'." >&2
           ((error_count++))
           workflow_error_occurred=true
        else
          ((processed_count++))
          # Check if a PNG was potentially created (crude check)
          [[ "$input_file" == *.pdf ]] && any_png_output=true
         fi
      done
      shopt -u nullglob

      echo "Conversion Summary: $processed_count files attempted, $error_count errors."
      if [ $error_count -gt 0 ]; then
        echo "Warning: Some conversion errors occurred. Workflow will continue." >&2
      fi
  fi

  # Check if any PNG files exist for extraction
  if [ "$extract_flag" = true ]; then
      if ! $any_png_output || [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ]; then
          echo "Warning: No PNG files found in $image_dir after conversion. Text extraction step may have no input." >&2
          # Don't disable flag, let extract step handle empty input dir
      fi
  fi
  echo "--- Conversion Complete ---"

else
  echo "--- Skipping Conversion ---"
fi

# 2. Extract Text (from PNGs)
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
           workflow_error_occurred=true
           ((error_count++))
        else
           ((processed_count++))
        fi
      done
      shopt -u nullglob

      echo "Extraction Summary: $processed_count files processed, $error_count errors."
       if [ $error_count -gt 0 ]; then
          echo "Warning: Some text extraction errors occurred. Workflow will continue." >&2
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
           workflow_error_occurred=true
        else
          ((processed_count++))
        fi
      done
      shopt -u nullglob

      echo "Assessment Summary: $processed_count files assessed, $error_count errors."
      if [ $error_count -gt 0 ]; then
          echo "Warning: Some assessment errors occurred. Workflow will continue." >&2
      fi
  fi
   echo "--- Assessment Complete ---"
else
  echo "--- Skipping Assessment ---"
fi


echo "--- Scanned PDF Workflow Finished ---"
if [ "$workflow_error_occurred" = true ]; then
    echo "Workflow finished with errors." >&2
    exit 1
else
    exit 0
fi

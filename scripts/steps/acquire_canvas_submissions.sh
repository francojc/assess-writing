#!/usr/bin/env bash
# Renamed and moved from original do-acquire.sh

# Usage function kept for reference, but this script is not typically called directly by the user.
usage() {
  cat <<EOF
Usage: $(basename "$0")

Acquires Canvas assignment submissions for a course and saves them.
Relies on environment variables set by the calling workflow script:
  - CANVAS_API_KEY: Your Canvas API key.
  - CANVAS_BASE_URL: The base URL for your Canvas instance.
  - COURSE_ID: The Canvas course ID.
  - ASSIGNMENT_ID: The Canvas assignment ID.
  - SUBMISSIONS_DIR: Directory to save submissions (e.g., ./submissions)

EOF
}
set -euo pipefail

# Check required environment variables passed from workflow
: "${CANVAS_API_KEY:?Set CANVAS_API_KEY in your environment.}"
: "${CANVAS_BASE_URL:?Set CANVAS_BASE_URL in your environment.}"
: "${COURSE_ID:?COURSE_ID environment variable must be set by calling script.}"
: "${ASSIGNMENT_ID:?ASSIGNMENT_ID environment variable must be set by calling script.}"

# Default output directory if not set by caller
sub_dir="${SUBMISSIONS_DIR:-./submissions}"
mkdir -p "$sub_dir"

# Simple help check in case called directly (though not intended)
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

echo "Fetching submissions for course $COURSE_ID, assignment $ASSIGNMENT_ID from $CANVAS_BASE_URL..."

# Fetch all submissions for the assignment. The Canvas API returns an array of submission objects.
# Use -f to cause curl to exit with an error code on server errors (4xx, 5xx).
# Include 'user' to potentially get user names later if needed.
response=$(curl -sfS -L -H "Authorization: Bearer $CANVAS_API_KEY" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/assignments/$ASSIGNMENT_ID/submissions?per_page=100&include[]=user") # Added -L for redirects

# Check curl exit status
if [[ $? -ne 0 ]]; then
  echo "Error: Failed to fetch submissions from Canvas API. Check URL, API key, and network." >&2
  # Optionally print response if it contains error details (might be empty on connection errors)
  # echo "Response: $response" >&2
  exit 1
fi

# Basic check for valid JSON structure (array)
if ! echo "$response" | jq -e . > /dev/null 2>&1; then
  echo "Error: Invalid JSON received from Canvas API." >&2
  echo "Response: $response" >&2
  exit 1
fi

# Process each submission object in the JSON array
download_count=0
skipped_count=0
error_count=0
echo "$response" | jq -c '.[]' | while IFS= read -r submission_json; do
  user_id=$(echo "$submission_json" | jq -r '.user_id')
  submission_type=$(echo "$submission_json" | jq -r '.submission_type')
  workflow_state=$(echo "$submission_json" | jq -r '.workflow_state') # e.g., submitted, graded, unsubmitted
  # Extract sortable_name (e.g., "Doe, John") and handle potential null
  sortable_name=$(echo "$submission_json" | jq -r '.user.sortable_name // "Unknown_User"')
  # Format to Last-First, replacing comma and space with a hyphen
  # Also replace any remaining spaces (e.g., middle names) with underscores
  formatted_name=$(echo "$sortable_name" | sed 's/, /-/g; s/ /_/g')

  # Skip unsubmitted attempts
  if [[ "$workflow_state" == "unsubmitted" ]]; then
    echo "Skipping unsubmitted attempt for user $user_id."
    ((skipped_count++))
    continue
  fi

  echo "Processing submission for user $user_id ($formatted_name - type: $submission_type)..."
  submission_processed=false # Flag to track if any file was successfully saved for this submission

  # Handle Attachments (priority if present)
  attachments=$(echo "$submission_json" | jq -c '.attachments // []')
  if [[ $(echo "$attachments" | jq 'length') -gt 0 ]]; then
    echo "  Found attachments for user $user_id."
    echo "$attachments" | jq -c '.[]' | while IFS= read -r attachment; do
      filename=$(echo "$attachment" | jq -r '.filename')
      url=$(echo "$attachment" | jq -r '.url')
      # Sanitize filename: prepend user_id to avoid collisions
      # Replace spaces with underscores in filename for safety
      safe_filename=$(echo "$filename" | tr ' ' '_') # Keep original filename sanitization
      out_file="$sub_dir/${formatted_name}_${user_id}_${safe_filename}"
      echo "    Downloading attachment: $filename..."
      # Use curl -f to fail on server errors, -L to follow redirects
      if curl -f -sS -L -H "Authorization: Bearer $CANVAS_API_KEY" -o "$out_file" "$url"; then
        echo "    Successfully downloaded to $out_file"
        submission_processed=true
      else
        echo "    Error downloading attachment $filename for user $user_id from $url" >&2
        ((error_count++))
        # Continue to next attachment/submission on error
      fi
    done
  # Handle Online Text Entry (if no attachments)
  elif [[ "$submission_type" == "online_text_entry" ]]; then
    body=$(echo "$submission_json" | jq -r '.body // ""')
    echo "  Checking body content (length: ${#body})..."
    if [[ -n "$body" ]]; then
      # Check for embedded Canvas file links first
      # Extracts the href value ending in /files/number?params
      canvas_file_url=$(printf '%s\n' "$body" | grep -oE 'href="([^"]+/files/[0-9]+[^"]*)"' | sed -E 's/href="([^"]+)"/\1/' | head -n 1 || true)
      # Extracts the title value, preferring common document extensions if present
      canvas_file_title=$(printf '%s\n' "$body" | grep -oE 'title="([^"]+\.(pdf|docx?|pptx?|xlsx?|txt|md))"' | sed -E 's/title="([^"]+)"/\1/' | head -n 1 || true)

      # Check for embedded Google Doc preview links
      gdoc_url=$(printf '%s\n' "$body" | grep -oE 'href="(https://docs\.google\.com/document/[^"]+/preview)"' | sed -E 's/href="([^"]+)"/\1/' | head -n 1 || true)

      if [[ -n "$canvas_file_url" ]]; then
        echo "  Detected Canvas file link in body."
        # Prefer title for filename, fallback to extracting from URL if needed
        if [[ -n "$canvas_file_title" ]]; then
          filename="$canvas_file_title"
        else
          # Basic extraction from URL path, remove query string
          filename=$(basename "$canvas_file_url" | cut -d '?' -f 1)
          # If filename is just a number (the file ID), append a generic extension guess or indicator
          if [[ "$filename" =~ ^[0-9]+$ ]]; then
             filename="${filename}_canvas_file" # Indicate it's a canvas file ID
          fi
        fi
        safe_filename=$(echo "$filename" | tr ' ' '_')
        out_file="$sub_dir/${formatted_name}_${user_id}_canvas_${safe_filename}"
        echo "    Downloading linked Canvas file: $filename..."

        # Ensure the URL is complete (it should be from Canvas API)
        if curl -f -sS -L -H "Authorization: Bearer $CANVAS_API_KEY" -o "$out_file" "$canvas_file_url"; then
            echo "    Successfully downloaded Canvas file to $out_file"
            submission_processed=true
        else
            echo "    Error downloading linked Canvas file for user $user_id from $canvas_file_url" >&2
            ((error_count++))
            # Fallback: Save the raw HTML body if download fails
            out_file_html="$sub_dir/${formatted_name}_${user_id}_submission_link_download_failed.html"
            if printf '%s\n' "$body" > "$out_file_html"; then
              echo "    Saved raw HTML containing link to $out_file_html as fallback."
              submission_processed=true # Still counts as processed (fallback saved)
            else
              echo "    Error saving fallback HTML link for user $user_id." >&2
              ((error_count++))
            fi
        fi
      elif [[ -n "$gdoc_url" ]]; then
        echo "  Detected Google Doc link in body."
        out_file_gdoc="$sub_dir/${formatted_name}_${user_id}_submission.gdoc.url"
        echo "    Saving Google Doc URL to $out_file_gdoc..."
        if printf '%s\n' "$gdoc_url" > "$out_file_gdoc"; then
          echo "    Successfully saved GDoc URL to $out_file_gdoc"
          submission_processed=true
        else
          echo "    Error saving GDoc URL for user $user_id to $out_file_gdoc." >&2
           ((error_count++))
        fi
        # Note: Downloading Google Doc content automatically is complex and not implemented here.
      else
        # No special links detected, save the raw HTML body directly
        out_file_html="$sub_dir/${formatted_name}_${user_id}_submission.html"
        echo "  No special links found. Saving online text entry HTML body to $out_file_html..."
        if printf '%s\n' "$body" > "$out_file_html"; then
          echo "    Successfully saved HTML to $out_file_html"
          submission_processed=true
        else
          echo "    Error saving HTML body for user $user_id to $out_file_html." >&2
          ((error_count++))
        fi
      fi
    else
      echo "  User $user_id submitted online text entry, but body is empty. Skipping file creation."
    fi
  # Handle Online URL (if no attachments and not text entry)
  elif [[ "$submission_type" == "online_url" ]]; then
    url=$(echo "$submission_json" | jq -r '.url // ""')
    if [[ -n "$url" ]]; then
      out_file="$sub_dir/${formatted_name}_${user_id}_submission.url"
      echo "  Saving online URL submission to $out_file..."
      # Use printf to avoid issues with echo interpreting backslashes and ensure newline
      if printf '%s\n' "$url" > "$out_file"; then
        echo "    Successfully saved URL to $out_file"
        submission_processed=true
      else
        echo "    Error saving URL for user $user_id to $out_file" >&2
        ((error_count++))
      fi
    else
      echo "  User $user_id submitted online URL, but URL is empty. Skipping file creation."
    fi
  # Handle other types or no content
  else
    echo "  User $user_id submitted via $submission_type, but no downloadable/savable content found or handled by this script."
  fi

  # Increment download count if any file was saved for this submission
  if [[ "$submission_processed" = true ]]; then
      ((download_count++))
  fi
done

echo "Acquisition Summary: $download_count submissions processed, $skipped_count skipped (unsubmitted), $error_count errors."
if [ $error_count -gt 0 ]; then
   echo "Warning: Some downloads or saves failed." >&2
   exit 1 # Exit with error if acquisition had issues
fi

exit 0 # Success

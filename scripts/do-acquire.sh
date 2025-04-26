#!/usr/bin/env bash

# Acquire Canvas assignment submissions for a course and save to submissions/
# Usage: This script is called by main.sh, which sets all required environment variables.

set -euo pipefail

# Check required environment variables
: "${CANVAS_API_KEY:?Set CANVAS_API_KEY in your environment.}"
: "${CANVAS_BASE_URL:?Set CANVAS_BASE_URL in your environment.}"
: "${COURSE_ID:?Set COURSE_ID in your environment.}"
: "${ASSIGNMENT_ID:?Set ASSIGNMENT_ID in your environment.}"

# Output directory for submissions
: "${SUBMISSIONS_DIR:?SUBMISSIONS_DIR must be set, typically by main.sh.}"
mkdir -p "$SUBMISSIONS_DIR"

echo "Fetching submissions for course $COURSE_ID, assignment $ASSIGNMENT_ID from $CANVAS_BASE_URL..."

# Fetch all submissions for the assignment. The Canvas API returns an array of submission objects.
# Use -f to cause curl to exit with an error code on server errors (4xx, 5xx).
# Include 'user' to potentially get user names later if needed.
response=$(curl -sfS -H "Authorization: Bearer $CANVAS_API_KEY" \
  "$CANVAS_BASE_URL/api/v1/courses/$COURSE_ID/assignments/$ASSIGNMENT_ID/submissions?per_page=100&include[]=user")

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
    continue
  fi

  echo "Processing submission for user $user_id (type: $submission_type)..."

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
      out_file="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_${safe_filename}"
      echo "    Downloading attachment: $filename..."
      # Use curl -f to fail on server errors, -L to follow redirects
      if curl -f -sS -L -H "Authorization: Bearer $CANVAS_API_KEY" -o "$out_file" "$url"; then
        echo "    Successfully downloaded to $out_file"
      else
        echo "    Error downloading attachment $filename for user $user_id from $url" >&2
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
        out_file="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_canvas_${safe_filename}"
        echo "    Downloading linked Canvas file: $filename..."

        # Ensure the URL is complete (it should be from Canvas API)
        if curl -f -sS -L -H "Authorization: Bearer $CANVAS_API_KEY" -o "$out_file" "$canvas_file_url"; then
            echo "    Successfully downloaded Canvas file to $out_file"
        else
            echo "    Error downloading linked Canvas file for user $user_id from $canvas_file_url" >&2
            # Fallback: Save the raw HTML body if download fails
            out_file_html="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_submission_link_download_failed.html"
            printf '%s\n' "$body" > "$out_file_html"
            echo "    Saved raw HTML containing link to $out_file_html as fallback."
        fi
      elif [[ -n "$gdoc_url" ]]; then
        echo "  Detected Google Doc link in body."
        out_file_gdoc="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_submission.gdoc.url"
        echo "    Saving Google Doc URL to $out_file_gdoc..."
        printf '%s\n' "$gdoc_url" > "$out_file_gdoc"
        # Note: Downloading Google Doc content automatically is complex and not implemented here.
      else
        # No special links detected, save the raw HTML body directly
        out_file_html="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_submission.html"
        echo "  No special links found. Saving raw HTML body..."
        echo "  Saving online text entry HTML body to $out_file_html..."
        if printf '%s\n' "$body" > "$out_file_html"; then
          echo "    Successfully saved HTML to $out_file_html"
        else
          echo "    Error saving HTML body for user $user_id to $out_file_html." >&2
        fi
      fi
    else
      echo "  User $user_id submitted online text entry, but body is empty."
    fi
  # Handle Online URL (if no attachments and not text entry)
  elif [[ "$submission_type" == "online_url" ]]; then
    url=$(echo "$submission_json" | jq -r '.url // ""')
    if [[ -n "$url" ]]; then
      out_file="$SUBMISSIONS_DIR/${formatted_name}_${user_id}_submission.url"
      echo "  Saving online URL submission to $out_file..."
      # Use printf to avoid issues with echo interpreting backslashes and ensure newline
      printf '%s\n' "$url" > "$out_file"
    else
      echo "  User $user_id submitted online URL, but URL is empty."
    fi
  # Handle other types or no content
  else
    echo "  User $user_id submitted via $submission_type, but no downloadable/savable content found or handled by this script."
  fi
done

echo "All submissions downloaded to $SUBMISSIONS_DIR"

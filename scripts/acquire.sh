#!/usr/bin/env bash

# Acquires Canvas assignment submissions, attachments, and other submission types.

usage() {
  cat <<EOF
Usage: $(basename "$0") -c <course_id> -a <assignment_id>

Acquires Canvas assignment submissions for a specific course and assignment.

Required Flags:
  -c, --course      ID of the Canvas course.
  -a, --assignment  ID of the Canvas assignment.

Required Environment Variables:
  - CANVAS_API_KEY: Your Canvas API key.
  - CANVAS_BASE_URL: The base URL for your Canvas instance.

Output:
  Submissions are saved to the './submissions/' directory.

EOF
}
# Exit on unset variables and pipeline errors, but not individual command errors within loops
set -uo pipefail

# Initialize variables
COURSE_ID=""
ASSIGNMENT_ID=""

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--course) COURSE_ID="$2"; shift ;;
        -a|--assignment) ASSIGNMENT_ID="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Check required environment variables passed from workflow
: "${CANVAS_API_KEY:?Set CANVAS_API_KEY in your environment.}"
: "${CANVAS_BASE_URL:?Set CANVAS_BASE_URL in your environment.}"

# Check required arguments
: "${COURSE_ID:?Course ID is required (-c or --course)}"
: "${ASSIGNMENT_ID:?Assignment ID is required (-a or --assignment)}"

# Set output directory according to README
sub_dir="./submissions"
mkdir -p "$sub_dir"

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
  submission_id=$(echo "$submission_json" | jq -r '.id // "NoSubmissionID"') # Added // fallback just in case
  submission_type=$(echo "$submission_json" | jq -r '.submission_type')
  workflow_state=$(echo "$submission_json" | jq -r '.workflow_state') # e.g., submitted, graded, unsubmitted
  # Extract sortable_name (e.g., "Doe, John") and handle potential null
  sortable_name=$(echo "$submission_json" | jq -r '.user.sortable_name // "Unknown_User"')
  # Extract Last Name (part before comma), sanitize, and handle edge cases
  lastName=$(echo "$sortable_name" | cut -d ',' -f 1 | tr -d '[:space:]' | tr -c '[:alnum:]-' '_') # Get part before comma, remove spaces, keep only alphanumeric/hyphen
  if [[ "$lastName" == "$sortable_name" && "$sortable_name" != "Unknown_User" ]]; then # If no comma was found and not Unknown
      lastName=$(echo "$sortable_name" | tr -d '[:space:]' | tr -c '[:alnum:]-' '_') # Sanitize the whole name
  elif [[ "$sortable_name" == "Unknown_User" ]]; then
      lastName="UnknownUser" # Specific value for unknown
  fi

  # Skip unsubmitted attempts
  if [[ "$workflow_state" == "unsubmitted" ]]; then
    echo "Skipping unsubmitted attempt for user $user_id."
    ((skipped_count++))
    continue
  fi

  echo "Processing submission for user $user_id ($lastName - type: $submission_type)..."
  submission_processed=false # Flag to track if any file was successfully saved for this submission

  # Handle Attachments (priority if present)
  attachments=$(echo "$submission_json" | jq -c '.attachments // []')
  if [[ $(echo "$attachments" | jq 'length') -gt 0 ]]; then
    echo "  Found attachments for user $user_id."
    echo "$attachments" | jq -c '.[]' | while IFS= read -r attachment; do
      filename=$(echo "$attachment" | jq -r '.filename')
      url=$(echo "$attachment" | jq -r '.url')
      # Sanitize filename: replace spaces/invalid chars with underscores
      safe_filename=$(echo "$filename" | tr -c '[:alnum:]._-' '_' | sed 's/__*/_/g' | sed 's/^_//; s/_$//') # Keep alphanumeric, dot, underscore, hyphen; replace others, collapse underscores, remove leading/trailing
      # New filename format: LastName_UserID_CourseID_AssignmentID_SubmissionID_Type_OriginalFilename.ext
      out_file="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_attachment_${safe_filename}"
      echo "    Downloading attachment: $filename..."
      # Use curl -f to fail on server errors, -L to follow redirects, -o to save
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
        safe_filename=$(echo "$filename" | tr -c '[:alnum:]._-' '_' | sed 's/__*/_/g' | sed 's/^_//; s/_$//') # Sanitize
        # New filename format
        out_file="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_canvasfile_${safe_filename}"
        echo "    Downloading linked Canvas file: $filename..."

        # Ensure the URL is complete (it should be from Canvas API), use -f, -L, -o
        if curl -f -sS -L -H "Authorization: Bearer $CANVAS_API_KEY" -o "$out_file" "$canvas_file_url"; then
            echo "    Successfully downloaded Canvas file to $out_file"
            submission_processed=true
        else
            echo "    Error downloading linked Canvas file for user $user_id from $canvas_file_url" >&2
            ((error_count++))
            # Fallback: Save the raw HTML body if download fails
            # New filename format for fallback HTML
            out_file_html="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_htmlfallback.html"
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
        # New filename format for gdoc URL file
        out_file_gdoc="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_gdoc.url"
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
        # New filename format for direct HTML save
        out_file_html="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_html.html"
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
      # New filename format for URL file
      out_file="$sub_dir/${lastName}_${user_id}_${COURSE_ID}_${ASSIGNMENT_ID}_${submission_id}_url.url"
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

#!/usr/bin/env bash

# Submits feedback (rubric assessments and comments) from YAML files to Canvas.

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# --- Default values ---
FEEDBACK_DIR="./feedback" # Default directory for finalized feedback YAML files
DRY_RUN=false             # Flag to control dry-run mode

# --- Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "${0}") [-f <feedback_dir>] [-d] [-h]

Submits rubric assessments and comments from feedback YAML files to Canvas.

Reads *.yaml files from the specified feedback directory (default: ./feedback).
Each YAML file must be named according to the convention:
  LastName_<UserID>_<CourseID>_<AssignmentID>_<SubmissionID>_<Type...>.yaml
(Note: CourseID and AssignmentID are extracted from the filename).
The file must contain YAML front matter with 'rubric_assessment' and/or 'submission_comment' keys.

Optional Flags:
  -f <feedback_dir>   Directory containing feedback YAML files (default: ${FEEDBACK_DIR})
  -d                  Dry-run mode: Print API call details instead of executing.
  -h                  Display this help and exit

Required Environment Variables:
  CANVAS_API_KEY   Your Canvas API Key
  CANVAS_BASE_URL  Your Canvas instance base URL (e.g., https://your.instructure.com)

Required Commands: curl, jq, yq (specifically yq-go)
EOF
  exit 1
}

# --- Check Dependencies ---
check_deps() {
  local missing_deps=0
  for cmd in curl jq yq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: Required command '$cmd' not found." >&2
      missing_deps=1
    fi
  done
  # Specifically check if yq is the go version, which behaves differently
  if command -v yq &>/dev/null && ! yq --version | grep -q 'github.com/mikefarah/yq'; then
     echo "Error: Incorrect 'yq' version found. This script requires the Go version (from https://github.com/mikefarah/yq)." >&2
     echo "If using Nix, ensure 'pkgs.yq-go' is in your environment." >&2
     missing_deps=1
  fi

  if [ $missing_deps -eq 1 ]; then
    exit 1
  fi
}

# --- URL Encode Function ---
# Uses jq's @uri filter for robust URL encoding
url_encode() {
    jq -sRr @uri <<< "$1"
}

# --- Parse Arguments ---
while getopts ":f:dh" opt; do
  case $opt in
    f) FEEDBACK_DIR="${OPTARG}" ;;
    d) DRY_RUN=true ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND-1))

# --- Validate Inputs ---
if [ -z "${CANVAS_API_KEY:-}" ]; then
  echo "Error: CANVAS_API_KEY environment variable is not set." >&2
  exit 1
fi

if [ -z "${CANVAS_BASE_URL:-}" ]; then
  echo "Error: CANVAS_BASE_URL environment variable is not set." >&2
  exit 1
fi

# Remove trailing slash from base URL if present
CANVAS_BASE_URL="${CANVAS_BASE_URL%/}"

if [[ ! -d "${FEEDBACK_DIR}" ]]; then
    echo "Error: Feedback directory not found: ${FEEDBACK_DIR}" >&2
    exit 1
fi

# Check for required commands
check_deps

# --- Main Logic ---
AUTH_HEADER="Authorization: Bearer ${CANVAS_API_KEY}"

echo "Starting feedback submission from directory: ${FEEDBACK_DIR}"
submitted_count=0
skipped_count=0
error_count=0

# Process each YAML file in the feedback directory using process substitution
# This avoids the while loop running in a subshell, ensuring counts are accurate
while IFS= read -r -d $'\0' feedback_file; do
  filename=$(basename "$feedback_file")
  echo "Processing feedback file: '$filename'"

  # --- Extract IDs from filename ---
  # Format: LastName_<UserID>_<CourseID>_<AssignmentID>_<SubmissionID>_<Type...>.yaml
  # Use Parameter Expansion and IFS splitting for reliability
  IFS='_' read -r lastName user_id course_id assignment_id submission_id rest <<< "$(basename "$filename" .yaml)" # Split base name by underscore

  # Validate extracted IDs (basic checks)
  if ! [[ "$user_id" =~ ^[0-9]+$ ]] || \
     ! [[ "$course_id" =~ ^[0-9]+$ ]] || \
     ! [[ "$assignment_id" =~ ^[0-9]+$ ]] || \
     ! [[ "$submission_id" =~ ^[0-9]+$ ]]; then
      echo "  Warning: Could not reliably extract UserID, CourseID, AssignmentID, or SubmissionID from filename '$filename'. Skipping." >&2
      echo "           Expected format: LastName_UserID_CourseID_AssignmentID_SubmissionID_Type.yaml" >&2
      ((skipped_count++))
      ((skipped_count++))
      continue
  fi

  # -- Parse YAML Content ---
  echo "  Extracting rubric assessment and comment from YAML..."
  # Extract rubric_assessment as compact JSON. Ensure null if not present.
  rubric_json=$(yq '.rubric_assessment // null' "$feedback_file" -o=json -I=0) || {
    echo "  Error parsing .rubric_assessment from '$filename' with yq. Skipping." >&2
    ((error_count++))
    continue
  }

  # Extract submission_comment as raw string. Ensure empty string if not present.
  submission_comment=$(yq '.submission_comment // ""' "$feedback_file" -r) || {
    echo "  Error parsing .submission_comment from '$filename' with yq. Skipping." >&2
    ((error_count++))
    continue
  }

  # Check if we have anything to submit
  if [[ "$rubric_json" == "null" && -z "$submission_comment" ]]; then
       echo "  Warning: No rubric assessment data or submission comment found in '$filename'. Skipping." >&2
       ((skipped_count++))
       continue
  fi

   # --- Construct API Payload ---
  data_payload=""
  payload_parts=() # Use an array to build payload parts safely

  # Process rubric assessment criteria
  if [[ "$rubric_json" != "null" ]]; then
      # Use yq & jq to iterate safely over rubric criteria as JSON lines
      # Each line: {"key": "criterion_id", "points": value, "comments": value}
      while IFS= read -r criterion_json_line; do
          # Parse the JSON line using jq -r to get raw values
          criterion_id=$(echo "$criterion_json_line" | jq -r '.key')
          points_val=$(echo "$criterion_json_line" | jq -r '.points // ""')     # Get raw string, default empty if null
          comments_val=$(echo "$criterion_json_line" | jq -r '.comments // ""') # Get raw string, default empty if null

          # Build the parameter keys (Keep these unencoded for form data)
          points_key="rubric_assessment[${criterion_id}][points]"
          comments_key="rubric_assessment[${criterion_id}][comments]"

          # URL encode only the values
          encoded_points_val=$(url_encode "$points_val")
          encoded_comments_val=$(url_encode "$comments_val")

          # Add key=encoded_value pairs to payload array
          payload_parts+=("${points_key}=${encoded_points_val}")
          payload_parts+=("${comments_key}=${encoded_comments_val}")

      done < <(echo "$rubric_json" | yq 'to_entries | .[] | {"key": .key, "points": .value.points, "comments": .value.comments} | @json') || {
          # Catch errors from the yq/jq pipeline
          echo "  Error processing rubric JSON with yq/jq pipeline to extract criteria. Skipping." >&2
          ((error_count++))
          continue
      }
  fi

  # Process submission comment
  if [[ -n "$submission_comment" ]]; then
       # Key remains unencoded, value gets encoded
       comment_key="comment[text_comment]"
       encoded_comment_val=$(url_encode "$submission_comment")
       payload_parts+=("${comment_key}=${encoded_comment_val}")
  fi

  # Join payload parts with '&'
  data_payload=$(printf "%s&" "${payload_parts[@]}")
  data_payload=${data_payload%&} # Remove trailing '&'

  # Check if payload is actually empty after processing (e.g., rubric_json was null and comment was empty)
  if [[ -z "$data_payload" ]]; then
      echo "  Warning: Constructed payload is empty after processing rubric/comment. Skipping." >&2
      ((skipped_count++))
      continue
  fi

  # --- Build API URL ---
  # Endpoint: /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
  api_url="${CANVAS_BASE_URL}/api/v1/courses/${course_id}/assignments/${assignment_id}/submissions/${user_id}"

  # --- Execute API Call or Dry Run ---
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would submit feedback for UserID: $user_id, SubmissionID: $submission_id"
    echo "  [DRY RUN] API URL: $api_url"
    echo "  [DRY RUN] Intended Payload Parameters (Key=OriginalValue):"
    # Display the intended keys and their original, unencoded values for clarity.
    # Re-extract the data for display to ensure accuracy.
    if [[ "$rubric_json" != "null" ]]; then
      while IFS= read -r criterion_json_line; do
          criterion_id=$(echo "$criterion_json_line" | jq -r '.key')
          points_val=$(echo "$criterion_json_line" | jq -r '.points // ""')
          comments_val=$(echo "$criterion_json_line" | jq -r '.comments // ""')

          points_key="rubric_assessment[${criterion_id}][points]"
          comments_key="rubric_assessment[${criterion_id}][comments]"

          # Print the key and the *original* unencoded value
          printf "    %-40s : %s\n" "$points_key" "$points_val"
          printf "    %-40s : %s\n" "$comments_key" "$comments_val"
      done < <(echo "$rubric_json" | yq 'to_entries | .[] | {"key": .key, "points": .value.points, "comments": .value.comments} | @json')
    else
        printf "    %-40s : %s\n" "rubric_assessment" "(not sending)"
    fi

    # Display submission comment
    if [[ -n "$submission_comment" ]]; then
        printf "    %-40s : %s\n" "comment[text_comment]" "$submission_comment"
    else
        printf "    %-40s : %s\n" "comment[text_comment]" "(not sending)"
    fi

    echo "  [DRY RUN] Raw Payload (Actual URL-Encoded Data To Be Sent):"
    echo "    $data_payload"
    ((submitted_count++)) # Count as "processed" in dry run
  else
    echo "  Submitting feedback for UserID: $user_id, SubmissionID: $submission_id..."
    api_response=$(curl -sfSL -X PUT \
      -H "${AUTH_HEADER}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "$data_payload" \
      "${api_url}" 2>&1) # Capture stderr as well for error messages

    # --- Check Result ---
    curl_exit_status=$?
    if [[ $curl_exit_status -eq 0 ]]; then
        # Check for potential API errors within the JSON response (even with 200 OK)
       api_error=$(echo "$api_response" | jq -r '.errors[0].message // ""') # Try to extract primary error message
       if [[ -n "$api_error" ]]; then
           echo "  Error from Canvas API: $api_error for file '$filename'. Check API permissions and data format." >&2
           ((error_count++))
       else
          # Check if the response is something other than expected JSON (e.g., HTML error page)
          if ! echo "$api_response" | jq -e . >/dev/null 2>&1; then
              echo "  Warning: API response was not valid JSON. Might indicate an issue (e.g., redirect, HTML error). Response:" >&2
              echo "$api_response" >&2
          fi
          echo "  Successfully submitted feedback for '$filename'."
          ((submitted_count++))
       fi
    else
        echo "  Error: curl command failed with exit status $curl_exit_status for file '$filename'." >&2
        echo "  Curl Response/Error (captured stderr+stdout): $api_response" >&2 # Show captured curl output/error
        ((error_count++))
    fi
  fi
done < <(find "$FEEDBACK_DIR" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

echo "Submission Summary: $submitted_count feedback files processed ($([[ "$DRY_RUN" = true ]] && echo 'dry run' || echo 'submitted')), $skipped_count skipped, $error_count errors."

if [[ "$DRY_RUN" = false && $error_count -gt 0 ]]; then
   echo "Warning: Some submissions failed." >&2
   exit 1
fi

exit 0

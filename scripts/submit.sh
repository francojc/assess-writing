#!/usr/bin/env bash

# Submits feedback (rubric assessments and comments) from YAML files to Canvas.

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# --- Default values ---
COURSE_ID=""
ASSIGNMENT_ID=""
FEEDBACK_DIR="./feedback" # Default directory for finalized feedback YAML files

# --- Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "${0}") -c <course_id> -a <assignment_id> [-f <feedback_dir>] [-h]

Submits rubric assessments and comments from feedback YAML files to Canvas.

Reads *.yaml files from the specified feedback directory (default: ./feedback).
Each YAML file must be named according to the convention:
  LastName_<UserID>_<AssignmentID>_<SubmissionID>_<Type>.yaml
and contain YAML front matter with 'rubric_assessment' and/or 'submission_comment' keys.

Required Flags:
  -c <course_id>      Canvas Course ID
  -a <assignment_id>  Canvas Assignment ID

Optional Flags:
  -f <feedback_dir>   Directory containing feedback YAML files (default: ${FEEDBACK_DIR})
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
while getopts ":c:a:f:h" opt; do
  case $opt in
    c) COURSE_ID="${OPTARG}" ;;
    a) ASSIGNMENT_ID="${OPTARG}" ;;
    f) FEEDBACK_DIR="${OPTARG}" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND-1))

# --- Validate Inputs ---
if [ -z "${COURSE_ID}" ] || [ -z "${ASSIGNMENT_ID}" ]; then
  echo "Error: Course ID (-c) and Assignment ID (-a) are required." >&2
  usage
fi

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

# Process each YAML file in the feedback directory
find "$FEEDBACK_DIR" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | while IFS= read -r -d $'\0' feedback_file; do
  filename=$(basename "$feedback_file")
  echo "Processing feedback file: '$filename'"

  # --- Extract IDs from filename ---
  # Format: LastName_<UserID>_<AssignmentID>_<SubmissionID>_<Type>.yaml
  # Use Parameter Expansion and IFS splitting for reliability
  IFS='_' read -r lastName user_id file_assignment_id submission_id rest <<< "$filename%.*" # Split base name by underscore

  # Validate extracted IDs (basic checks)
  if ! [[ "$user_id" =~ ^[0-9]+$ ]] || ! [[ "$submission_id" =~ ^[0-9]+$ ]]; then
      echo "  Warning: Could not reliably extract UserID or SubmissionID from filename '$filename'. Skipping." >&2
      ((skipped_count++))
      continue
  fi
   # Optional: Check if assignment ID in filename matches the flag (sanity check)
  if [[ "$file_assignment_id" != "$ASSIGNMENT_ID" ]]; then
       echo "  Warning: Assignment ID in filename ('$file_assignment_id') does not match script argument ('$ASSIGNMENT_ID'). Processing anyway, but check consistency." >&2
       # Consider making this an error or adding a flag to enforce match
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
  if [[ "$rubric_json" != "null" ]]; then
       encoded_rubric=$(url_encode "$rubric_json")
       data_payload="rubric_assessment=$encoded_rubric"
  fi

  if [[ -n "$submission_comment" ]]; then
       encoded_comment=$(url_encode "$submission_comment")
       # Add '&' separator if rubric data was also present
       [[ -n "$data_payload" ]] && data_payload+="&"
       data_payload+="comment[text_comment]=$encoded_comment"
  fi

  # --- Build API URL ---
  # Endpoint: /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
  api_url="${CANVAS_BASE_URL}/api/v1/courses/${COURSE_ID}/assignments/${ASSIGNMENT_ID}/submissions/${user_id}"

  # --- Execute API Call ---
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
     api_error=$(echo "$api_response" | jq -r '.errors[0].message // ""')
     if [[ -n "$api_error" ]]; then
         echo "  Error from Canvas API: $api_error for file '$filename'. Check API permissions and data format." >&2
         ((error_count++))
     else
        echo "  Successfully submitted feedback for '$filename'."
        ((submitted_count++))
     fi
  else
      echo "  Error: curl command failed with exit status $curl_exit_status for file '$filename'." >&2
      echo "  API URL: $api_url" >&2
      echo "  Curl Response/Error: $api_response" >&2 # Show captured curl output/error
      ((error_count++))
  fi

done

echo "Submission Summary: $submitted_count feedback files submitted, $skipped_count skipped, $error_count errors."

if [ $error_count -gt 0 ]; then
   echo "Warning: Some submissions failed." >&2
   exit 1
fi

exit 0

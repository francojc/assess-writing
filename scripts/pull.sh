#!/usr/bin/env bash

# Pulls assignment description and rubric from Canvas API and saves them as Markdown.

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# Default values
COURSE_ID=""
ASSIGNMENT_ID=""
DOCS_DIR="./docs"

# --- Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "${0}") -c <course_id> -a <assignment_id> [-d <docs_dir>] [-h]

Pulls assignment description and rubric from Canvas API and saves them as Markdown.

Requires environment variables:
  CANVAS_API_KEY   Your Canvas API Key
  CANVAS_BASE_URL  Your Canvas instance base URL (e.g., https://your.instructure.com)

Requires commands: curl, jq, pandoc

Options:
  -c <course_id>      Canvas Course ID (required)
  -a <assignment_id>  Canvas Assignment ID (required)
  -d <docs_dir>       Directory to save the markdown files (default: ./docs)
  -h                  Display this help and exit
EOF
  exit 1
}

# --- Check Dependencies ---
check_deps() {
  local missing_deps=0
  for cmd in curl jq pandoc; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: Required command '$cmd' not found." >&2
      missing_deps=1
    fi
  done
  if [ $missing_deps -eq 1 ]; then
    exit 1
  fi
}

# --- Parse Arguments ---
while getopts ":c:a:d:h" opt; do
  case $opt in
    c) COURSE_ID="${OPTARG}" ;;
    a) ASSIGNMENT_ID="${OPTARG}" ;;
    d) DOCS_DIR="${OPTARG}" ;;
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

# Check for required commands
check_deps

# --- Main Logic ---
API_URL="${CANVAS_BASE_URL}/api/v1/courses/${COURSE_ID}/assignments/${ASSIGNMENT_ID}"
AUTH_HEADER="Authorization: Bearer ${CANVAS_API_KEY}"
ASSIGNMENT_FILE="${DOCS_DIR}/assignment.md"
RUBRIC_FILE="${DOCS_DIR}/rubric.md" # Changed back to .md extension

echo "Fetching assignment data from ${API_URL}..."

# Fetch data using curl, handle potential errors
api_response=$(curl -sfSL -H "${AUTH_HEADER}" "${API_URL}") || {
  echo "Error: Failed to fetch data from Canvas API. Check URL, credentials, and network." >&2
  # Attempt to get error message from Canvas if possible (response might be empty on network failure)
  error_message=$(echo "${api_response:-}" | jq -r '.errors[0].message // "Unknown API error."')
  echo "Canvas API Error: ${error_message}" >&2
  exit 1
}

echo "Ensuring docs directory exists at ${DOCS_DIR}..."
mkdir -p "${DOCS_DIR}"

# Extract and convert description
echo "Extracting description..."
description_html=$(echo "${api_response}" | jq -r '.description // empty')

if [ -z "$description_html" ]; then
  echo "Warning: Assignment description is empty or not found in API response." >&2
  # Create an empty file or a placeholder
  echo "# Assignment Description" > "${ASSIGNMENT_FILE}"
  echo "" >> "${ASSIGNMENT_FILE}"
  echo "*No description provided via Canvas API.*" >> "${ASSIGNMENT_FILE}"
else
  echo "Converting description HTML to Markdown..."
  echo "${description_html}" | pandoc --from html --to markdown_strict --wrap=none -o "${ASSIGNMENT_FILE}" || {
    echo "Error: pandoc failed to convert description HTML to Markdown." >&2
    exit 1
  }
  echo "Assignment description saved to ${ASSIGNMENT_FILE}"
fi


# Extract and format rubric
echo "Extracting rubric..."

# Check if rubric exists and is an array
rubric_exists=$(echo "${api_response}" | jq 'if .rubric? and (.rubric | type == "array") and (.rubric | length > 0) then true else false end')

if [ "$rubric_exists" != "true" ]; then
  echo "Warning: Rubric is missing, empty, or not an array in the API response." >&2
  # Create an empty file or a placeholder
  echo "# Rubric" > "${RUBRIC_FILE}"
  echo "" >> "${RUBRIC_FILE}"
  echo "*No rubric provided or rubric is empty via Canvas API.*" >> "${RUBRIC_FILE}"
else
  echo "Formatting rubric to Markdown..."
  # jq filter to format the rubric into Markdown with IDs, descriptions, and ratings tables
  jq_rubric_filter='
    "# Rubric: " + (.rubric_settings.title // "Assignment Rubric") + " (" + (.rubric_settings.points_possible | tostring) + " Points)\n\n" +
    (
      .rubric | map(
        # Section for each criterion including ID, Description, and Max Points
        "## Criterion: [" + .id + "] " + .description + " (" + (.points | tostring) + " Points)\n\n" +
        # Add long description if available
        (.long_description | if . and . != "" then "> " + . + "\n\n" else "" end) +
        # Add ratings table if ratings exist
        (if .ratings? and (.ratings | length > 0) then
          "| Rating | Points | Description |\n" +
          "|---|---|---|\n" +
          (
            .ratings | map(
              # Ensure descriptions are formatted reasonably for Markdown table cell
              # (Replace pipes, newlines; basic escaping - might need refinement)
              "| " + (.description | gsub("\\|";"\\|") | gsub("\n"; " ")) +
              " | " + (.points | tostring) +
              " | " + ((.long_description // "") | gsub("\\|";"\\|") | gsub("\n"; " ")) + " |"
            ) | join("\n")
          ) + "\n" # Newline after ratings table
        else
           "# No specific ratings defined for this criterion.\n" # Indicate if no ratings
        end)
      ) | join("\n---\n\n") # Join criteria sections with a divider
    )
  '
  # Generate the Markdown rubric file
  echo "${api_response}" | jq -r "${jq_rubric_filter}" > "${RUBRIC_FILE}" || {
    echo "Error: jq failed to format the rubric Markdown." >&2
    exit 1
  }
  echo "Rubric Markdown saved to ${RUBRIC_FILE}"
fi

# Removed redundant jq filter and logic from previous state
echo "Done."
exit 0

#!/usr/bin/env bash

# Reformats assessment Markdown files (table + comments) into YAML format for submission.

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# --- Default values ---
SOURCE_DIR="./assessments"
DEST_DIR="./feedback"

# --- Usage Function ---
usage() {
  cat <<EOF
Usage: $(basename "${0}") [-s <source_dir>] [-d <dest_dir>] [-h]

Reformats Markdown assessment files from the source directory into YAML files
suitable for submission, saving them in the destination directory.

Expects Markdown files in <source_dir> (default: ${SOURCE_DIR}) containing:
1. A Markdown table with the header: | Criterion ID | Points | Comments |
2. A Markdown section starting exactly with: ## Submission comments

Outputs YAML files to <dest_dir> (default: ${DEST_DIR}) with the structure:
rubric_assessment:
  <criterion_id>:
    points: <points>
    comments: <comments>
  ...
submission_comment: <overall comments>

Optional Flags:
  -s <source_dir>    Directory containing assessment Markdown files (default: ${SOURCE_DIR})
  -d <dest_dir>      Directory to save the output YAML files (default: ${DEST_DIR})
  -h                 Display this help and exit

Required Commands: awk, sed, grep, jq, yq (specifically yq-go)
EOF
  exit 1
}

# --- Check Dependencies ---
check_deps() {
  local missing_deps=0
  # Assume awk, sed, grep are available via coreutils/gnused/gnugrep from flake.nix
  for cmd in jq yq; do
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

# --- Parse Arguments ---
while getopts ":s:d:h" opt; do
  case $opt in
    s) SOURCE_DIR="${OPTARG}" ;;
    d) DEST_DIR="${OPTARG}" ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done
shift $((OPTIND-1))

# --- Validate Inputs ---
if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "Error: Source directory not found: ${SOURCE_DIR}" >&2
    exit 1
fi

# Check dependencies
check_deps

# Create destination directory
mkdir -p "$DEST_DIR"

# --- Main Logic ---
echo "Starting reformatting from '$SOURCE_DIR' to '$DEST_DIR'..."
reformatted_count=0
skipped_count=0
error_count=0

# Process each Markdown file in the source directory
# Use process substitution to avoid running the loop in a subshell
while IFS= read -r -d $'\0' input_md_file; do
  input_basename=$(basename "$input_md_file" .md) # Get basename without .md
  output_yaml_file="$DEST_DIR/${input_basename}.yaml" # Create yaml filename

  echo "Processing '$input_basename.md' -> '$input_basename.yaml'"

  # --- Extract Rubric Table Data using awk ---
  # - Find lines between table header and next blank line or header
  # - Skip header and separator
  # - Split by '|', trim whitespace
  # - Build JSON object string for each row
  # - Combine objects into a single JSON array string
  rubric_data_json_array=$(awk '
    # Flag to indicate we are inside the table
    in_table {
        # Stop if we hit a blank line or another header after the separator
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*##/) {
            in_table = 0
            next
        }
        # Skip the separator line
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|/) {
            next
        }
        # Process data row
        gsub(/^[[:space:]]*\||[[:space:]]*\|[[:space:]]*$/, "") # Remove leading/trailing | and spaces
        n = split($0, fields, /[[:space:]]*\|[[:space:]]*/) # Split by | with surrounding spaces
        # Expecting 4 columns: ID | Name | Points | Comments
        if (n == 4) {
            # Trim whitespace from relevant fields
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[1]) # Criterion ID
            # fields[2] is Criterion Name - ignored
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[3]) # Points
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[4]) # Comments

            # Escape quotes and backslashes in comments (field 4) for JSON
            gsub(/\\/, "\\\\", fields[4])
            gsub(/"/, "\\\"", fields[4])

             # Print JSON object for the row (will be collected by shell)
             # Ensure points (field 3) is treated as a number (or null if non-numeric)
            points_val = fields[3]
            if (points_val !~ /^[0-9]+([.][0-9]+)?$/) { points_val = "null" }
            # Use fields[1] (ID), points_val (Points), and fields[4] (Comments)
            printf "{\"id\":\"%s\",\"points\":%s,\"comments\":\"%s\"}\n", fields[1], points_val, fields[4]

        } else {
             # Print error to stderr if row format is unexpected (allow 3 columns for flexibility?)
             # For now, strictly expect 4 columns based on observed error.
             # if (n != 3) { # - uncomment this line and comment below if 3 columns are also valid
               # Escape inner single quotes: '\'' represents a single quote within the awk script string
               print "Warning: Skipping row in " FILENAME " - expected 4 columns ('\''| ID | Name | Points | Comments |'\''), found " n ": " $0 > "/dev/stderr"
             # }
           }

    }
    # Detect table header start
    # Use a more flexible header detection that ignores extra columns for robustness
    /^[[:space:]]*\|[[:space:]]*Criterion ID[[:space:]]*\|/ {
        in_table = 1
    }
    ' "$input_md_file" | jq -s '.' # Use jq to slurp all JSON objects into a single array
  )

  # Check if awk/jq produced valid JSON array (at least '[]')
  if [[ -z "$rubric_data_json_array" ]] || ! jq -e '.' <<< "$rubric_data_json_array" > /dev/null 2>&1 ; then
      echo "  Warning: Could not parse rubric table or table is empty in '$input_basename.md'. Skipping rubric assessment." >&2
      # Set to null json array for jq later
      rubric_data_json_array='[]'
      # Consider this an error or skip? For now, proceed without rubric data.
      # ((error_count++)); continue
  fi

  # --- Extract Submission Comments using sed ---
  # Get all lines from "## Submission comments" to the end, then remove the header line itself
  submission_comment=$(sed -n '/^[[:space:]]*## Submission comments/,$p' "$input_md_file" | sed '1d') || {
    echo "  Warning: Could not find '## Submission comments' section in '$input_basename.md'. Submission comment will be empty." >&2
    submission_comment=""
    # Optionally treat as error: ((error_count++)); continue
  }
  # Trim leading/trailing whitespace/newlines from comment block
  submission_comment=$(echo "$submission_comment" | sed '/^$/d' | sed '$!N; /^\(.*\)\n\1$/!P; D' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')


  # --- Assemble Final JSON using jq ---
  # Convert the array of {"id":..,"points":..,"comments":..} into the desired { "criterion_id": {"points":..,"comments":..} } map
  # Also add the submission comment
  final_json=$(jq -n \
      --argjson rubricArray "$rubric_data_json_array" \
      --arg commentText "$submission_comment" \
      '{
          rubric_assessment: ($rubricArray | map({(.id): {points: .points, comments: .comments}}) | add // {}),
          submission_comment: $commentText
      }') || {
           echo "  Error: Failed to construct final JSON for '$input_basename.md'. Skipping." >&2
           ((error_count++))
           continue
         }

  # --- Convert JSON to YAML using yq ---
  echo "  Generating YAML file '$output_yaml_file'..."
  echo "$final_json" | yq -P '.' > "$output_yaml_file" || {
      echo "  Error: Failed to convert JSON to YAML using yq for '$input_basename.md'. Skipping." >&2
      # Clean up potentially partial file
      rm -f "$output_yaml_file"
      ((error_count++))
      continue
  }

   # Check if output exists and is non-empty
   if [[ -s "$output_yaml_file" ]]; then
       ((reformatted_count++))
   else
       echo "  Warning: Generated YAML file '$output_yaml_file' is empty. Check intermediate steps." >&2
       ((error_count++)) # Count as error if empty
   fi

done < <(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.md' -print0)

echo "Reformatting Summary: $reformatted_count files reformatted, $skipped_count skipped, $error_count errors."

if [ $error_count -gt 0 ]; then
   echo "Warning: Some files failed during reformatting." >&2
   exit 1
fi

exit 0

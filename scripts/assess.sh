#!/usr/bin/env bash
# Assesses student assignment markdown files in ./assignments/ using LLM.

set -uo pipefail # Exit on unset variables and pipeline errors

usage() {
  cat <<EOF
Usage: $(basename "$0")

Assesses all student assignment markdown files found in ./assignments/
using the llm tool, assignment description, and rubric from ./docs/.

Requires:
  - ./docs/assignment.md
  - ./docs/rubric.md
  - Markdown files in ./assignments/
  - 'llm' command installed and configured.

Outputs assessment markdown files to ./assessments/. Creates ./assessments/
if it doesn't exist.

Example:
  $(basename "$0") # Assesses all *.md files in ./assignments/
EOF
}

# Check if llm is installed
if ! command -v llm &> /dev/null; then
  echo "Error: llm is not installed. Please install it to use this script." >&2
  exit 1
fi

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 1
fi

# Define directories and required files
docs_dir="./docs"
assignments_dir="./assignments"
assessments_dir="./assessments"
assignment_desc_file="$docs_dir/assignment.md"
rubric_file="$docs_dir/rubric.md"
prompt_file="$docs_dir/prompt.md" # Added prompt file variable

# Check if assignments directory exists
if [ ! -d "$assignments_dir" ]; then
  echo "Error: Assignments directory '$assignments_dir' not found." >&2
  echo "Did you run the prepare script first?" >&2
  exit 1
fi

# Check for essential project docs files
if [[ ! -f "$assignment_desc_file" ]]; then
  echo "Error: Assignment description file not found: '$assignment_desc_file'" >&2
  exit 1
fi
if [[ ! -f "$rubric_file" ]]; then
  echo "Error: Rubric file not found: '$rubric_file'" >&2
  exit 1
fi


# Create output directory
mkdir -p "$assessments_dir"

# Define the prompt for the LLM
# Note: Using heredoc for multiline prompt clarity

# Define the generic prompt for the LLM
read -r -d '' prompt << EOM
You are tasked with assessing a student's submission based on the provided materials: assignment description, rubric, specific instructions, and the student's work.

Follow the specific instructions provided to structure and formulate your assessment. Ensure your response adheres to the requested format and tone. Use the rubric criteria to guide your evaluation and provide feedback as directed. Address the student directly using 'you' when providing qualitative feedback.

Please use the following assignment description, rubric, specific instructions, and student submission to generate your response.
EOM

echo "Starting assessment of files in '$assignments_dir'..."

assessed_count=0
error_count=0

# Process each markdown file in the assignments directory
find "$assignments_dir" -maxdepth 1 -type f -name '*.md' -print0 | while IFS= read -r -d $'\0' input_md_file; do
  input_basename=$(basename "$input_md_file")
  output_file="$assessments_dir/${input_basename}" # Keep the .md extension

  echo "  Assessing assignment file: '$input_basename' -> '$output_file'"

  # Run the assessment using the llm tool
  # Concatenate description, rubric, specific prompt, assignment text, and the generic prompt
  if ! (cat "$assignment_desc_file"; echo -e "\n---\n"; \
         cat "$rubric_file"; echo -e "\n---\n"; \
         cat "$prompt_file"; echo -e "\n---\n"; \
         cat "$input_md_file"; echo -e "\n---\n"; \
         echo "$prompt") | llm - > "$output_file"; then

      echo "  Error running llm for assessment on file: '$input_basename'" >&2
      # Remove potentially empty/corrupt file on error
      rm -f "$output_file"
      ((error_count++))
  else
      # Check if the output file is empty, which might indicate an llm issue
      if [[ ! -s "$output_file" ]]; then
          echo "  Warning: Assessment resulted in an empty file for '$input_basename'. Check llm execution." >&2
          # Optionally remove empty file: rm "$output_file"
      else
          echo "  Successfully assessed '$input_basename' and saved to '$output_file'"
          ((assessed_count++))
      fi
  fi
done

echo "Assessment Summary: $assessed_count files assessed, $error_count errors."

if [ $error_count -gt 0 ]; then
   echo "Warning: Some files failed during assessment." >&2
   exit 1
fi

exit 0

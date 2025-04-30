#!/usr/bin/env bash
# Renamed and moved from original do-assess.sh

usage() {
  cat <<EOF
Usage: $(basename "$0") <input_markdown_file>

Assesses a single student assignment (markdown file) using LLM with rubric and assignment description.

Input files required in project structure:
  - ./docs/assignment.md
  - ./docs/rubric.md
  - The <input_markdown_file> (typically from ./text/)

Outputs assessment to ./assessment/ directory.

Example:
  $0 text/Doe-John_12345_submission.md

EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if llm is installed
if ! command -v llm &> /dev/null; then
  echo "Error: llm is not installed. Please install it to use this script." >&2
  exit 1
fi


# Check if an assignment file is provided as an argument
if [ -z "$1" ]; then
  echo "Error: Input markdown file not specified." >&2
  usage
  exit 1
fi

assignment_file="$1"

# Check if the input assignment file exists and is a markdown file
if [[ ! -f "$assignment_file" || ! "$assignment_file" == *.md ]]; then
  echo "Error: Input file '$assignment_file' is not a valid markdown file or does not exist." >&2
  exit 1
fi

# Define required doc files
docs_dir="./docs"
assignment_desc_file="$docs_dir/assignment.md"
rubric_file="$docs_dir/rubric.md"

# Check for essential project docs files
if [ ! -f "$assignment_desc_file" ]; then
  echo "Error: Assignment description file not found: '$assignment_desc_file'" >&2
  exit 1
fi
if [ ! -f "$rubric_file" ]; then
  echo "Error: Rubric file not found: '$rubric_file'" >&2
  exit 1
fi


# Assessment output directory (Expected to exist)
assessment_dir="./assessment"

# Construct the output file path based on the input filename
input_basename=$(basename "$assignment_file")
output_file="$assessment_dir/${input_basename}" # Keep the .md extension

echo "  Assessing assignment file: '$input_basename' -> '$output_file'"

# Define the prompt for the LLM
# Use environment variables or config files for sensitive info if needed in prompts later
# Note: Using heredoc for multiline prompt clarity
read -r -d '' prompt << EOM
You are to take on the role of a Spanish TA in an Intermediate Spanish university course (ACTFL level low-intermediate emerging). You will be responsible for grading a student's assignment. Note lean towards higher scalar scores and more thorough, but optimistic qualitative assessment.

The student has submitted a written assignment in Spanish that you need to assess based on the assignment description and the provided rubric. You will need to:

1.  provide a score and short comment (in English) for each criterion (out of 5 possible points),
2.  provide an overall score for the assignment,
3.  provide qualitative assessment and feedback (in English) to the student on their strengths and areas for improvement using excerpts from their writing that support the criterion evaluation and overall score. Direct all your feedback to the student by referring to them as 'you' (not as 'the student')!

The response, then, should include 3 sections: 1. Rubric scalars and comments, 2. Overall score (out of 20), 3. Qualitative assessment. Format section 1 as a markdown table, section 2. a single line, and section 3. a short synopsis and then a set of examples and potential alternatives for improvement. Use markdown formatting for your entire response.
EOM

# Run the assessment using the llm tool
# Concatenate description, rubric, and the assignment text as input to the prompt
if cat "$assignment_desc_file" "$rubric_file" "$assignment_file" | llm "$prompt" > "$output_file"; then
  # Check if the output file is empty, which might indicate an llm error
  if [[ ! -s "$output_file" ]]; then
      echo "Warning: Assessment resulted in an empty file for '$input_basename'. Check llm execution." >&2
      # Depending on workflow, might want to `rm "$output_file"`
  else
      echo "  Successfully assessed assignment '$input_basename' and saved to '$output_file'"
  fi
else
  echo "Error running llm for assessment on file: '$input_basename'" >&2
  # Remove potentially empty/corrupt file on error
  rm -f "$output_file"
  exit 1
fi

exit 0 # Success

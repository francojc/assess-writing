#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <input_assignment_file>

Options:
  -h, --help    Show this help message and exit

Assesses student assignments using LLM with rubric and assignment description.

Input files:
  - Requires docs/assignment_description.md
  - Requires docs/rubric.md
  - Outputs to assessment/ directory

Example:
  $0 text/Jonese.md

EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if an assignment file is provided as an argument
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

# Assign the input assignment file to a variable
assignment_file="$1"

# Check if the assignment file exists
if [ ! -f "$assignment_file" ]; then
  echo "Error: Assignment file '$assignment_file' not found."
  exit 1
fi

# Create the assessment directory if it doesn't exist
assessment_dir="./assessment"
if [ ! -d "$assessment_dir" ]; then
  mkdir -p "$assessment_dir"
fi

# Construct the output file path
output_file="$assessment_dir/$(basename "$assignment_file" .md).md"

# Run the assessment using the llm tool
echo "Assessing assignment file: $assignment_file"
cat ./docs/assignment_description.md ./docs/rubric.md "$assignment_file" | llm "You are to take on the role of a Spanish TA in an Intermediate Spanish university course (ACTFL level low-intermediate emerging). You will be responsible for grading a student's assignment. Note lean towards higher scalar scores and more thorough, but optimistic qualitative assessment. \n\n The student has submitted a written assignment in Spanish that you need to assess based on the assignment description and the provided rubric. You will need to: \n\n 1. provide a score and short comment (in English) for each criterion (out of 5 possible points), \n 2. provide an overall score for the assignment, \n 3. provide qualitative assessment and feedback (in English) to the student on their strengths and areas for improvement using excerpts from their writing that support the criterion evaluation and overall score. Direct all your feedback to the student by referring to them as 'you' (not as 'the student')! \n\n The response, then, should include 3 sections: 1. Rubric scalars and comments, 2. Overall score (out of 20), 3. Qualitative assessment. Format section 1 as a markdown table, section 2. a single line, and section 3. a short synopsis and then a set of examples and potential alternatives for improvement." > "$output_file"

# Check if the assessment was successful
if [ $? -eq 0 ]; then
  echo "Finished assessing the assignment file: $assignment_file"
  echo "Assessment saved to: $output_file"
else
  echo "Error: Assessment failed for file: $assignment_file"
  exit 1
fi

exit 0

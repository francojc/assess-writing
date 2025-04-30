#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [SOURCE] [OPTIONS]

Orchestrates Writing assessment processing pipeline within an initialized project.

  -h, --help      Show this help message

Source (Select one, default is --scanned):
  -S, --scanned   Process scanned PDFs
  -C, --canvas    Process submissions from Canvas

Options (Combine to run multiple steps, default is all steps for the source):
  -q, --acquire   Run Canvas acquisition step only (requires -C/--canvas)
  -c, --convert   Run conversion step only
  -e, --extract   Run text extraction step only
  -a, --assess    Run assignment assessment only

Source dependent options:
  When using '-C, --canvas', these are required:
    --course COURSE_ID          Canvas Course ID
    --assignment ASSIGNMENT_ID  Canvas Assignment ID

Run multiple stages by combining flags (e.g., -ce).
By default (no source/options flags), runs all stages for scanned PDFs (-S -cea).

Examples:
  $(basename "$0")                      # Run all stages with scanned PDFs (-S implicitly)
  $(basename "$0") -C --course 1 --assignment 2  # Run all stages with Canvas submissions
  $(basename "$0") -S -c                # Run only conversion on scanned PDFs
  $(basename "$0") -C -ea --course 1 --assignment 2 # Run extraction and assessment on Canvas submissions

EOF
}

# --- Script Setup ---
# Ensure scripts exit immediately if a command fails
set -e
# Treat unset variables as an error
set -u
# Prevent errors in pipelines from being masked
set -o pipefail

# NOTE: Complex path detection removed. Assumes all scripts (main, workflows, steps)
# are installed into a directory that is included in the PATH (e.g., $out/bin in Nix).


# Flag to track if any step flag was explicitly set by the user
any_step_flag_set=false

# Canvas specific variables
course_id_val=""
assignment_id_val=""
workflow_source="scanned" # Default workflow

# Store step flags to pass down
step_flags=""

# Parse command line arguments
# Use getopt for more robust parsing if complexity increases
while (( $# > 0 )); do
  case "$1" in
    -S|--scanned)
      workflow_source="scanned"
      shift
      ;;
    -C|--canvas)
      workflow_source="canvas"
      shift
      ;;
    -q|--acquire)
      any_step_flag_set=true
      step_flags+="q" # Append flag character
      shift
      ;;
    -c|--convert)
      any_step_flag_set=true
      step_flags+="c"
      shift
      ;;
    -e|--extract)
      any_step_flag_set=true
      step_flags+="e"
      shift
      ;;
    -a|--assess)
      any_step_flag_set=true
      step_flags+="a"
      shift
      ;;
    --course)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: --course requires a value." >&2; usage; exit 1;
      fi
      course_id_val="$2"
      # Don't keep --course N in parsed_args, they are handled via env vars
      shift 2
      ;;
    --assignment)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: --assignment requires a value." >&2; usage; exit 1;
      fi
      assignment_id_val="$2"
      # Don't keep --assignment M in parsed_args
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # For now, treat unknown as error
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done


# Add step flags to pass if any were set
if [ "$any_step_flag_set" = true ]; then
    step_flags_to_pass="-$step_flags"
else
    # If no specific step flags, run workflow with default (all steps)
    # Pass no step flags, workflow script handles default execution.
    step_flags_to_pass=""
fi


# Validate Canvas requirements if canvas workflow is selected
if [[ "$workflow_source" == "canvas" ]]; then
  # Canvas workflow (or just acquire step) requires course/assignment IDs
  if [[ -z "$course_id_val" || -z "$assignment_id_val" ]]; then
    echo "Error: --course and --assignment arguments are required for the 'canvas' workflow." >&2
    usage
    exit 1
  fi
  # Export variables for the Canvas workflow and acquisition step
  export COURSE_ID="$course_id_val"
  export ASSIGNMENT_ID="$assignment_id_val"

  # Check for API key/URL (recommend setting these in .envrc or environment)
   : "${CANVAS_API_KEY:?CANVAS_API_KEY environment variable not set. Required for Canvas workflow.}"
   : "${CANVAS_BASE_URL:?CANVAS_BASE_URL environment variable not set. Required for Canvas workflow.}"

fi

# Scanned workflow has no specific required args here, but needs PDFs in submissions/
# --- Common Project Structure and Input Checks ---
docs_dir="./docs"
assignment_desc_file="$docs_dir/assignment.md" # Renamed for clarity
rubric_file="$docs_dir/rubric.md"

# Check for essential doc files needed by assessment step (regardless of workflow)
if [ ! -d "$docs_dir" ] || \
   [ ! -f "$rubric_file" ] || \
   [ ! -f "$assignment_desc_file" ]; then
  echo "Error: Project structure incomplete. Run from project root." >&2
  echo "Expected: $docs_dir/, $rubric_file, $assignment_desc_file" >&2
  # Consider suggesting `nix flake init...` if appropriate context detected later
  exit 1
fi

# --- Dispatch to Workflow ---

echo "Starting assessment processing..."
echo "Selected workflow: $workflow_source"
echo "Step flags passed to workflow: '$step_flags_to_pass'"

final_exit_code=0

# Check if workflow scripts are executable and in PATH
if ! command -v run_canvas.sh >/dev/null 2>&1 || ! command -v run_scanned.sh >/dev/null 2>&1; then
    echo "Error: Required workflow scripts (run_canvas.sh, run_scanned.sh) not found in PATH." >&2
    echo "This usually indicates an issue with the Nix build or the environment setup." >&2
    exit 1
fi

if [ "$workflow_source" = "canvas" ]; then
    echo "Executing Canvas workflow..."
    # Call script directly by name, pass step flags
    if ! run_canvas.sh ${step_flags_to_pass:+"$step_flags_to_pass"}; then
        echo "Error occurred during Canvas workflow execution." >&2
        final_exit_code=1
    fi

elif [ "$workflow_source" = "scanned" ]; then
     echo "Executing Scanned PDF workflow..."
     # Call script directly by name, pass step flags
     if ! run_scanned.sh ${step_flags_to_pass:+"$step_flags_to_pass"}; then
        echo "Error occurred during Scanned PDF workflow execution." >&2
        exit 1
    fi
    echo "Executing Scanned PDF workflow..."
    # Pass the step flags; remaining args ($@) could be passed if workflows need them
     if ! "$workflow_script" ${step_flags_to_pass:+"$step_flags_to_pass"}; then
        echo "Error occurred during Scanned PDF workflow execution." >&2
        final_exit_code=1
     fi
else
    # Should not happen due to default and parsing, but as a safeguard:
    echo "Error: Unknown workflow source '$workflow_source'." >&2
    usage
    exit 1
fi


echo "--- Assessment processing finished ---"
exit $final_exit_code


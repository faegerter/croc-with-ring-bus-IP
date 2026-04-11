#!/usr/bin/env bash

set -e  # Exit on error

# Default values
NUM_NODES=3

# Help function
print_help() {
  echo "Usage: $0 [--num-nodes N]"
  echo ""
  echo "Options:"
  echo "  --num-nodes N   Number of nodes (default: 3)"
  echo "  -h, --help      Show this help message"
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --num-nodes)
      if [[ -n "$2" && "$2" != --* ]]; then
        NUM_NODES="$2"
        shift 2
      else
        echo "Error: --num-nodes requires a numeric argument"
        exit 1
      fi
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      print_help
      exit 1
      ;;
  esac
done

# Validate NUM_NODES is a positive integer
if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [[ "$NUM_NODES" -lt 1 ]]; then
  echo "Error: --num-nodes must be a positive integer"
  exit 1
fi

echo "Running with NUM_NODES=$NUM_NODES"

# --- Your workflow ---
oseda -2025.12 bash <<EOF
  cd ..
  bender update
  cd sw && make all
  cd ../verilator
  ./run_verilator.sh --flist
  ./run_verilator.sh --ring --num-nodes $NUM_NODES --build --run ../sw/bin
EOF

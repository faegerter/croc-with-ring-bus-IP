#!/usr/bin/env bash

set -e

# Default values
NUM_NODES=3
N_TESTS=5

print_help() {
  echo "Usage: $0 [--num-nodes N] [--n-tests T]"
  echo ""
  echo "Options:"
  echo "  --num-nodes N   Number of nodes (default: 3)"
  echo "  --n-tests T     Number of tests (default: 1)"
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
    --n-tests)
      if [[ -n "$2" && "$2" != --* ]]; then
        N_TESTS="$2"
        shift 2
      else
        echo "Error: --n-tests requires a numeric argument"
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

# Validation
for val in "$NUM_NODES" "$N_TESTS"; do
  if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -lt 1 ]]; then
    echo "Error: values must be positive integers"
    exit 1
  fi
done

echo "Running with NUM_NODES=$NUM_NODES, N_TESTS=$N_TESTS"

# --- Workflow inside oseda environment ---
oseda -2025.12 bash <<EOF
set -e

cd ..
bender vendor init
bender update

cd sw
make clean
make test_serial_link NUM_NODES=$NUM_NODES N_TESTS=$N_TESTS

cd ../verilator
./run_verilator.sh --flist
./run_verilator.sh --ring --num-nodes $NUM_NODES --build --run ../sw/bin
EOF
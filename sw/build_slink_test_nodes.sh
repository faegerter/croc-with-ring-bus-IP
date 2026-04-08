#This doesn't work. Just a placeholder to show the idea
#Also the makefile has to be adapted to always generate a default amount of nodes.
NUM_NODES=$1

if [ "$NUM_NODES" -lt 2 ] || [ "$NUM_NODES" -gt 16 ]; then
    echo "NUM_NODES must be between 2 and 16"
    exit 1
fi

echo "Cleaning previous builds..."
rm -rf bin* build*

echo "Building $NUM_NODES nodes..."

for ((i=0; i<NUM_NODES; i++))
do
    echo "---- NODE_ID=$i ----"
    make compile NODE_ID=$i NUM_NODES=$NUM_NODES \
        BINDIR=bin_id$i \
        BUILDDIR=build_id$i
done

echo "Done."
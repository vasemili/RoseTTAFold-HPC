#!/bin/bash

# make the script stop when error (non-true exit code) occurs
set -e

############################################################
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/ohpc/pub/apps/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/ohpc/pub/apps/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/ohpc/pub/apps/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
############################################################

conda activate rosettafold

SCRIPT=$(realpath -s $0)
export PIPEDIR=$(dirname $SCRIPT)

CPU="8"  # number of CPUs to use
MEM="64" # max memory (in GB)

# Inputs:
IN="$1"                # input.fasta
chmod u+r "$IN"        # ensure the input FASTA file is readable
BASENAME=$(basename "$IN" .fasta) # base name of the input file without extension
WDIR=$(realpath -s "/path/to/your/output_directory/output_$BASENAME") # working folder based on input file name

echo "Running end-to-end prediction"
echo "Current Python executable: $(which python)"
echo "Python version: $(python --version)"
echo "Python path: $PYTHONPATH"
echo "Conda environment: $CONDA_PREFIX"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "PIPEDIR: $PIPEDIR"
echo "Input FASTA: $IN"
echo "Working Directory: $WDIR"

# Ensure dgl is installed using pip
#pip install dgl -f https://data.dgl.ai/wheels/torch-2.3/cu118/repo.html

LEN=$(tail -n1 $IN | wc -m)

mkdir -p $WDIR/log
chmod u+w $WDIR

############################################################
# 1. generate MSAs
############################################################
if [ ! -s $WDIR/t000_.msa0.a3m ]
then
    echo "Running HHblits"
    $PIPEDIR/input_prep/make_msa.sh $IN $WDIR $CPU $MEM > $WDIR/log/make_msa.stdout 2> $WDIR/log/make_msa.stderr
fi

############################################################
# 2. predict secondary structure for HHsearch run
############################################################
if [ ! -s $WDIR/t000_.ss2 ]
then
    echo "Running PSIPRED"
    $PIPEDIR/input_prep/make_ss.sh $WDIR/t000_.msa0.a3m $WDIR/t000_.ss2 > $WDIR/log/make_ss.stdout 2> $WDIR/log/make_ss.stderr
fi

############################################################
# 3. search for templates
############################################################
DB="$PIPEDIR/pdb100_2021Mar03/pdb100_2021Mar03"
if [ ! -s $WDIR/t000_.hhr ]
then
    echo "Running hhsearch"
    HH="hhsearch -b 50 -B 500 -z 50 -Z 500 -mact 0.05 -cpu $CPU -maxmem $MEM -aliw 100000 -e 100 -p 5.0 -d $DB"
    cat $WDIR/t000_.ss2 $WDIR/t000_.msa0.a3m > $WDIR/t000_.msa0.ss2.a3m
    $HH -i $WDIR/t000_.msa0.ss2.a3m -o $WDIR/t000_.hhr -atab $WDIR/t000_.atab -v 0 > $WDIR/log/hhsearch.stdout 2> $WDIR/log/hhsearch.stderr
fi

############################################################
# 4. end-to-end prediction
############################################################
if [ ! -s $WDIR/t000_.3track.npz ]
then
    echo "Running end-to-end prediction"
    python $PIPEDIR/network/predict_e2e.py \
        -m $PIPEDIR/weights \
        -i $WDIR/t000_.msa0.a3m \
        -o $WDIR/t000_.e2e \
        --hhr $WDIR/t000_.hhr \
        --atab $WDIR/t000_.atab \
        --db $DB 1> $WDIR/log/network.stdout 2> $WDIR/log/network.stderr
fi
echo "Done"

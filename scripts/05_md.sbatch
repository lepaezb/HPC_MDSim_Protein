#!/bin/bash
#===============================================================================
# 05_md.sbatch - Production MD
# Submit from project directory: sbatch scripts/05_md.sbatch
#===============================================================================

#SBATCH --job-name=05_md
#SBATCH --partition=(aa100 or nvidia-a100)
#SBATCH --qos=(normal)
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --time=(24:00:00 or longer)
#SBATCH --nodelist=(fijigpu-04)
#SBATCH --output=logs/05_md_%j.out
#SBATCH --error=logs/05_md_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=(email@colorado.edu)

set -e  # Exit immediately on any error

# ============== MODULES ==============
module purge
#module load gcc/11.2.0             # for alpine/blanca
#module load openmpi/4.1.1          # for alpine/blanca
#module load cuda/12.1.1            # for alpine/blanca
#module load gromacs/2024.2         # for alpine/blanca
#module load GROMACS/2024.2_GPU     # for FIJI

# ============== CONFIGURATION ==============
# Environment variables
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export GMX_GPU_DD_COMMS=true
export GMX_GPU_PME_PP_COMMS=true
export GMX_FORCE_UPDATE_DEFAULT_GPU=true

# Directories
PRJ_DIR="${SLURM_SUBMIT_DIR}"
MD_DIR="${PRJ_DIR}/05_md"
cd "${PRJ_DIR}"

# Maximum hours to run (slightly less than SLURM limit) to allow clean shutdown
MAXH="23.9" 


# ============== CHECKS  ==============
if [ ! -f "${MD_DIR}/md.tpr" ]; then
    echo "ERROR: md.tpr not found in ${MD_DIR}. Run NPT equilibration first."
    exit 1
fi

echo "=============================================="
echo "Job ID: ${SLURM_JOB_ID}"
echo "Running on: $(hostname)"
echo "Started at: $(date)"
echo "Project directory: ${PRJ_DIR}"
echo "GPU(s): ${CUDA_VISIBLE_DEVICES}"
echo "=============================================="


# ============== 1. RUN (OR EXTEND) MD PRODUCTION ==============
echo ""
echo "Running production MD..."
echo ""

# Check for existing checkpoint (for extending run)
if [ -f "${MD_DIR}/md.cpt" ]; then
    echo "Found checkpoint file - continuing from previous run..."
    gmx mdrun -deffnm "${MD_DIR}/md" \
              -ntomp ${SLURM_CPUS_PER_TASK} \
              -nb gpu \
              -bonded gpu \
              -pme gpu \
              -update gpu \
              -cpi "${MD_DIR}/md.cpt" \
              -cpo "${MD_DIR}/md.cpt" \
              -append \
              -maxh "${MAXH}"
else
    echo "Starting new production run..."
    gmx mdrun -deffnm "${MD_DIR}/md" \
              -ntomp ${SLURM_CPUS_PER_TASK} \
              -nb gpu \
              -bonded gpu \
              -pme gpu \
              -update gpu \
              -cpo "${MD_DIR}/md.cpt" \
              -maxh "${MAXH}"
fi

# Check if MD completed successfully
if [ -f "${MD_DIR}/md.gro" ]; then
    echo "Simulation completed successfully!"
    echo ""
    echo "Output files in 05_md/:"
    echo "  - md.xtc (trajectory)"
    echo "  - md.edr (energies)"
    echo "  - md.log (log file)"
    echo "  - md.gro (final structure)"
    echo "  - md.cpt (checkpoint)"
    echo ""
    echo "To continue: sbatch scripts/05_md.sbatch"
    echo "The job will automatically resume from checkpoint."
    echo ""
    echo "For analysis: Run analysis basic analysis script:"
    echo "  sbatch scripts/06_analysis.sbatch"
else
    echo "Simulation was interrupted (time limit or error)"
    echo "Checkpoint saved in 05_md/md.cpt"
    echo ""
    echo "Automatically resubmitting to continue from checkpoint..."
    sbatch "${PRJ_DIR}/scripts/05_md.sbatch"
fi
echo ""

echo "=============================================="
echo "Production MD job finished at: $(date)"
echo "=============================================="
echo ""
grep "Performance:" "${MD_DIR}/md.log" 2>/dev/null || true

#!/bin/bash
#===============================================================================
# 02_em.sbatch - Energy Minimization
# Submit from project directory: sbatch scripts/02_em.sbatch
#===============================================================================

#SBATCH --job-name=02_em
#SBATCH --partition=(amilan or highmem)
#SBATCH --qos=(normal)
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=02:00:00
#SBATCH --nodelist=(fijinode-67)
#SBATCH --output=logs/02_em_%j.out
#SBATCH --error=logs/02_em_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=(email@colorado.edu)

set -e  # Stop if any command fails

# ============== MODULES ==============
module purge
#module load gcc/11.2.0         # for alpine/blanca
#module load openmpi/4.1.1      # for alpine/blanca
#module load gromacs/2024.2     # for alpine/blanca
#module load GROMACS/2024.2     # for FIJI


# ============== CONFIGURATION ==============
# Environment variables
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

# Directories
PRJ_DIR="${SLURM_SUBMIT_DIR}"
EM_DIR="${PRJ_DIR}/02_em"
NVT_DIR="${PRJ_DIR}/03_nvt"
cd "${PRJ_DIR}"

# ============== CHECKS  ==============
# Make sure em.tpr exists
if [ ! -f "${EM_DIR}/em.tpr" ]; then
    echo "ERROR: Preprocessing failed - em.tpr not found"
    echo "Please run 01_prep.sh first to generate necessary input files."
    exit 1
fi

echo "=============================================="
echo "Job ID:         ${SLURM_JOB_ID}"
echo "Running on:     $(hostname)"
echo "Started at:     $(date)"
echo "Submit Dir:     ${SLURM_SUBMIT_DIR}"
echo "Project Dir:    ${PRJ_DIR}"
echo "CPUs:           ${SLURM_CPUS_PER_TASK} CPUs"
echo "=============================================="

# ============== 1. ENERGY MINIMIZATION (EM) ==============
echo ""
echo "Running energy minimization..."
gmx mdrun -v -deffnm "${EM_DIR}/em" -ntomp ${SLURM_CPUS_PER_TASK}

# Check if EM completed successfully
if [ ! -f "${EM_DIR}/em.gro" ]; then
    echo "ERROR: Energy minimization failed - em.gro not found"
    exit 1
fi

echo ""
echo "Final energy summary:"
tail -20 "${EM_DIR}/em.log" | grep -E "Potential Energy|Maximum force"
echo ""


# ============== 2. EXTRACT POTENTIAL ENERGY ==============
echo ""
echo "Extracting potential energy..."
echo "Potential" | gmx energy \
    -f "${EM_DIR}/em.edr" \
    -o "${EM_DIR}/potential.xvg"


# ============== 3. POST-PROCESSING ==============
echo ""
echo "Post-processing: fixing PBC..."
echo 0 | gmx trjconv \
    -f "${EM_DIR}/em.gro" \
    -s "${EM_DIR}/em.tpr" \
    -o "${EM_DIR}/em_whole.gro" \
    -pbc whole


# ============== 4. PREPARE NVT INPUT ==============
echo ""
echo "Preparing NVT equilibration input..."
gmx grompp -f mdp/nvt.mdp \
           -c "${EM_DIR}/em_whole.gro" \
           -r "${EM_DIR}/em_whole.gro" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${NVT_DIR}/nvt.tpr"


# ============== SUMMARY ==============
echo ""
echo "=============================================="
echo "Energy minimization completed at: $(date)"
echo "=============================================="
echo ""
echo "Output files in 02_em/:"
echo "  - em.gro, em.log, em.edr"
echo "  - em_whole.gro (PBC corrected)"
echo "  - potential.xvg (energy plot)"
echo ""
echo "Output files in 03_nvt/:"
echo "  - nvt.tpr (ready for NVT)"
echo ""
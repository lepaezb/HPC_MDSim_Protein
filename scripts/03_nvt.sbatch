#!/bin/bash
#===============================================================================
# 03_nvt.sbatch - NVT Equilibration
# Submit from project directory: sbatch scripts/03_nvt.sbatch
#===============================================================================

#SBATCH --job-name=03_nvt
#SBATCH --partition=(aa100 or nvidia-a100)
#SBATCH --qos=(normal)
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --time=02:00:00
#SBATCH --nodelist=(fijigpu-04)
#SBATCH --output=logs/03_nvt_%j.out
#SBATCH --error=logs/03_nvt_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=(email@colorado.edu)

set -e  # Stop if any command fails

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
NVT_DIR="${PRJ_DIR}/03_nvt"
NPT_DIR="${PRJ_DIR}/04_npt"
cd "${PRJ_DIR}"


# ============== CHECKS  ==============
# Make sure nvt.tpr exists
if [ ! -f "${NVT_DIR}/nvt.tpr" ]; then
    echo "ERROR: nvt.tpr not found in ${NVT_DIR}. Run energy minimization first."
    exit 1
fi

echo "=============================================="
echo "Job ID:         ${SLURM_JOB_ID}"
echo "Running on:     $(hostname)"
echo "Started at:     $(date)"
echo "Submit Dir:     ${SLURM_SUBMIT_DIR}"
echo "Project Dir:    ${PRJ_DIR}"
echo "CPUs:           ${SLURM_CPUS_PER_TASK} CPUs"
echo "GPU Assigned:   ${CUDA_VISIBLE_DEVICES}"
echo "=============================================="


# ============== 1. RUN NVT EQUILIBRATION ==============
echo ""
echo "Running NVT equilibration ..."
gmx mdrun -deffnm "${NVT_DIR}/nvt" \
          -ntomp ${SLURM_CPUS_PER_TASK} \
          -nb gpu \
          -bonded gpu \
          -pme gpu \
          -update gpu \
          -cpo "${NVT_DIR}/nvt.cpt"

# Check if NVT completed successfully
if [ ! -f "${NVT_DIR}/nvt.gro" ]; then
    echo "ERROR: NVT equilibration failed - nvt.gro not found"
    echo "Check ${NVT_DIR}/nvt.log for details"
    exit 1
fi

echo ""
echo "NVT simulation completed successfully"
grep "Performance:" "${NVT_DIR}/nvt.log" || true


# ============== 2. EXTRACT TEMPERATURE ==============
echo ""
echo "Extracting temperature data..."
echo "Temperature" | gmx energy \
    -f "${NVT_DIR}/nvt.edr" \
    -o "${NVT_DIR}/temperature.xvg"


# ============== 3. POST-PROCESSING ==============
echo ""
echo "Post-processing: fixing PBC..."
echo 0 | gmx trjconv \
    -f "${NVT_DIR}/nvt.gro" \
    -s "${NVT_DIR}/nvt.tpr" \
    -o "${NVT_DIR}/nvt_whole.gro" \
    -pbc whole


# ============== 4. PREPARE NPT INPUT ==============
echo ""
echo "Preparing NPT equilibration input..."
gmx grompp -f mdp/npt.mdp \
           -c "${NVT_DIR}/nvt_whole.gro" \
           -r "${NVT_DIR}/nvt_whole.gro" \
           -t "${NVT_DIR}/nvt.cpt" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${NPT_DIR}/npt.tpr"


# ============== SUMMARY ==============
echo ""
echo "=============================================="
echo "NVT equilibration completed at: $(date)"
echo "=============================================="
echo ""
echo "Output files in 03_nvt/:"
echo "  - nvt.gro, nvt.log, nvt.edr, nvt.xtc"
echo "  - nvt_whole.gro (PBC corrected)"
echo "  - nvt.cpt (checkpoint)"
echo "  - temperature.xvg (temperature plot)"
echo ""
echo "Output files in 04_npt/:"
echo "  - npt.tpr (ready for NPT)"

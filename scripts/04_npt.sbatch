#!/bin/bash
#===============================================================================
# 04_npt.sbatch - NPT Equilibration
# Submit from project directory: sbatch scripts/04_npt.sbatch
#===============================================================================

#SBATCH --job-name=04_npt
#SBATCH --partition=(aa100 or nvidia-a100)
#SBATCH --qos=(normal)
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --time=02:00:00
#SBATCH --nodelist=(fijigpu-04)
#SBATCH --output=logs/04_npt_%j.out
#SBATCH --error=logs/04_npt_%j.err
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
NPT_DIR="${PRJ_DIR}/04_npt"
MD_DIR="${PRJ_DIR}/05_md"
cd "${PRJ_DIR}"


# ============== CHECKS  ==============
# Make sure npt.tpr exists
if [ ! -f "${NPT_DIR}/npt.tpr" ]; then
    echo "ERROR: npt.tpr not found in ${NPT_DIR}. Run NVT equilibration first."
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


# ============== 1. RUN NPT EQUILIBRATION ==============
echo ""
echo "Running NPT equilibration ..."
gmx mdrun -deffnm "${NPT_DIR}/npt" \
          -ntomp ${SLURM_CPUS_PER_TASK} \
          -nb gpu \
          -bonded gpu \
          -pme gpu \
          -update gpu \
          -cpo "${NPT_DIR}/npt.cpt"

# Check if NPT completed successfully
if [ ! -f "${NPT_DIR}/npt.gro" ]; then
    echo "ERROR: NPT equilibration failed - npt.gro not found"
    echo "Check ${NPT_DIR}/npt.log for details"
    exit 1
fi

echo ""
echo "NPT simulation completed successfully"
grep "Performance:" "${NPT_DIR}/npt.log" || true

# ============== 2. EXTRACT PRESSURE AND DENSITY ==============
echo ""
echo "Extracting pressure and density data..."
# Extracting Pressure
echo "Pressure" | gmx energy \
    -f "${NPT_DIR}/npt.edr" \
    -o "${NPT_DIR}/pressure.xvg"

# Extracting Density
echo "Density" | gmx energy \
    -f "${NPT_DIR}/npt.edr" \
    -o "${NPT_DIR}/density.xvg"


# ============== 3. POST-PROCESSING ==============
echo ""
echo "Post-processing: fixing PBC..."
echo 0 | gmx trjconv \
    -f "${NPT_DIR}/npt.gro" \
    -s "${NPT_DIR}/npt.tpr" \
    -o "${NPT_DIR}/npt_whole.gro" \
    -pbc whole


# ============== 4. PREPARE MD INPUT ==============
echo ""
echo "Preparing production MD input..."
gmx grompp -f mdp/md.mdp \
           -c "${NPT_DIR}/npt_whole.gro" \
           -t "${NPT_DIR}/npt.cpt" \
           -p "${PRJ_DIR}/topol.top" \
           -o "${MD_DIR}/md.tpr"


# ============== SUMMARY ==============
echo ""
echo "=============================================="
echo "NPT equilibration completed at: $(date)"
echo "=============================================="
echo ""
echo "Output files in 04_npt/:"
echo "  - npt.gro, npt.log, npt.edr, npt.xtc"
echo "  - npt_whole.gro (PBC corrected)"
echo "  - npt.cpt (checkpoint)"
echo "  - pressure.xvg, density.xvg"
echo ""
echo "Output files in 05_md/:"
echo "  - md.tpr (ready for production)"
echo ""
echo "IMPORTANT: Check pressure and density plots before production!"
echo "  - Pressure should fluctuate around 1 bar"
echo "  - Density should be stable around ~1000 kg/m³ for aqueous systems"

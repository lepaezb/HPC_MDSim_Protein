#!/bin/bash
#===============================================================================
# 06_analysis.sbatch - Basic MD Trajectory Analysis
# Submit from project directory: sbatch scripts/06_analysis.sbatch
#===============================================================================

#SBATCH --job-name=06_analysis
#SBATCH --partition=(amilan or highmem)
#SBATCH --qos=(normal)
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=05:00:00
#SBATCH --nodelist=(fijinode-67)
#SBATCH --output=logs/06_analysis_%j.out
#SBATCH --error=logs/06_analysis_%j.err
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
MD_DIR="${PRJ_DIR}/05_md"
ANALYSIS_DIR="${PRJ_DIR}/06_analysis"
cd "${PRJ_DIR}"

# Input parameters
TRAJ="${MD_DIR}/md.xtc"       # Trajectory
TPR="${MD_DIR}/md.tpr"        # .tpr file for MD
EM_TPR="${EM_DIR}/em.tpr"     # Unequilibrated structure
EDR="${MD_DIR}/md.edr"        # .edr file for MD

# Create output directories
mkdir -p "${ANALYSIS_DIR}/trajectories"
mkdir -p "${ANALYSIS_DIR}/rmsd"
mkdir -p "${ANALYSIS_DIR}/rog"
mkdir -p "${ANALYSIS_DIR}/energy"


# ============== CHECKS  ==============
# Make sure trajectory exists
if [ ! -f "${TRAJ}" ]; then
    echo "ERROR: Trajectory not found: ${TRAJ}"
    exit 1
fi
# Make sure md.tpr exists
if [ ! -f "${TPR}" ]; then
    echo "ERROR: TPR file not found: ${TPR}"
    exit 1
fi
# Make sure em.tpr exists
if [ ! -f "${EM_TPR}" ]; then
    echo "ERROR: EM TPR file not found: ${EM_TPR}"
    exit 1
fi
# Make sure md.edr exists
if [ ! -f "${EDR}" ]; then
    echo "ERROR: Energy file not found: ${EDR}"
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


# ============== 1. TRAJECTORY INFO ==============
echo ""
echo "1: Trajectory information..."
echo "--------------------------------------"
# Check trajectory info, save in traj_info.txt, and print relevant info
gmx check -f "${TRAJ}" &> "${ANALYSIS_DIR}/traj_info.txt"
echo ""
echo "Summary:"
grep -E "(Step|Last frame|Coords|time)" "${ANALYSIS_DIR}/traj_info.txt" || true


# ============== 2. PBC CORRECTIONS ==============
echo ""
echo "2: Correcting PBC..."
echo "--------------------------------------"
echo ""

# Reassemble molecules split across box boundaries
echo " 2.1. Making molecules whole..."
echo 0 | gmx trjconv \
    -f "${TRAJ}" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/trajectories/traj_whole.xtc" \
    -pbc whole

# Remove jumps when molecules cross the box edge
echo "  2.2. Removing PBC jumps..."
echo 0 | gmx trjconv \
    -f "${ANALYSIS_DIR}/trajectories/traj_whole.xtc" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/trajectories/traj_nojump.xtc" \
    -pbc nojump

# Center protein in the box
echo "  2.3. Centering on protein..."
echo -e "1\n0" | gmx trjconv \
    -f "${ANALYSIS_DIR}/trajectories/traj_nojump.xtc" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/trajectories/traj_center.xtc" \
    -center \
    -pbc mol \
    -ur compact

TRAJ_FIX="${ANALYSIS_DIR}/trajectories/traj_center.xtc"
echo "  Analysis-ready trajectory: ${TRAJ_FIX}"


# ============== 3. ROOT MEAN SQUARE DEVIATION (RMSD) ==============
echo ""
echo "3: Calculating Root Mean Square Deviation (RMSD)..."
echo "--------------------------------------"
echo ""

# RMSD vs initial simulation frame (C-alpha)
echo " RMSD (C-alpha) vs MD reference..."
echo -e "3\n3" | gmx rms \
    -f "${TRAJ_FIX}" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/rmsd/rmsd_ca_vs_md_reference.xvg" \
    -tu ns

# RMSD vs unequilibrated (EM) structure (C-alpha)
echo "RMSD (C-alpha) vs unequilibrated (EM) structure..."
echo -e "3\n3" | gmx rms \
    -f "${TRAJ_FIX}" \
    -s "${EM_TPR}" \
    -o "${ANALYSIS_DIR}/rmsd/rmsd_ca_vs_unequilibrated.xvg" \
    -tu ns

# RMSD vs initial simulation frame (Backbone)
echo " RMSD (Backbone) vs MD reference..."
echo -e "4\n4" | gmx rms \
    -f "${TRAJ_FIX}" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/rmsd/rmsd_bb_vs_md_reference.xvg" \
    -tu ns

# RMSD vs unequilibrated (EM) structure (Backbone)
echo "RMSD (Backbone) vs unequilibrated (EM) structure..."
echo -e "4\n4" | gmx rms \
    -f "${TRAJ_FIX}" \
    -s "${EM_TPR}" \
    -o "${ANALYSIS_DIR}/rmsd/rmsd_bb_vs_unequilibrated.xvg" \
    -tu ns

# ============== 3. RADIUS OF GYRATION (RoG) ==============
echo ""
echo "3: Calculating Radius of Gyration (RoG)..."
echo "--------------------------------------"
echo ""
echo 1 | gmx gyrate \
    -f "${TRAJ_FIX}" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/rog/rog.xvg"

# ============== 4. ENERGY ANALYSIS ==============
echo ""
echo "4: Extracting energy terms from .edr file..."
echo "--------------------------------------"
echo ""

# Potential Energy
echo "  Extracting Potential Energy..."
echo "Potential" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/potential.xvg"

# Total Energy
echo "  Extracting Total Energy..."
echo "Total-Energy" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/total_energy.xvg"

# Temperature
echo "  Extracting Temperature..."
echo "Temperature" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/temperature.xvg"

# Pressure
echo "  Extracting Pressure..."
echo "Pressure" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/pressure.xvg"

# Density
echo "  Extracting Density..."
echo "Density" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/density.xvg"

# Box volume
echo "  Extracting Box Volume..."
echo "Volume" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy/volume.xvg"

# Summary energy statistics
echo "Extracting energy statistics for most important properties..."
echo -e "Temperature\nPressure\nDensity\nPotential\nTotal-Energy\n0" | gmx energy \
    -f "${EDR}" \
    -o "${ANALYSIS_DIR}/energy_summary.xvg" \
    2>&1 | tee "${ANALYSIS_DIR}/energy/energy_stats.txt"


# ============== 5. EXTRACT COMPRESSED TRAJECTORY ==============
echo ""
echo "5: Extracting full thinned trajectory for visualization (1 frame/ns)..."
echo "--------------------------------------"
echo ""
echo 1 | gmx trjconv \
    -f "${TRAJ_FIX}" \
    -s "${TPR}" \
    -o "${ANALYSIS_DIR}/trajectories/traj_thinned.xtc" \
    -skip 100


# ============== SUMMARY ==============
echo ""
echo "=============================================="
echo "ANALYSIS COMPLETE"
echo "=============================================="
echo "Finished at: $(date)"
echo ""
echo "Output files:"
echo "  ${ANALYSIS_DIR}/rmsd/          - RMSD (C-alpha and Backbone)"
echo "  ${ANALYSIS_DIR}/rog/           - Radius of gyration"
echo "  ${ANALYSIS_DIR}/energy/        - Energy terms and statistics"
echo "  ${ANALYSIS_DIR}/trajectories/  - PBC-corrected and thinned trajectories"
echo ""
echo "Next steps:"
echo "  1. Plot results to determine equilibration time"
echo "  2. Look for RMSD plateau, stable Rg, and stable energy"
echo "=============================================="
echo ""
echo "Resource usage:"
sacct -j ${SLURM_JOB_ID} --format=JobID,Elapsed,MaxRSS,MaxVMSize,CPUTime,TotalCPU

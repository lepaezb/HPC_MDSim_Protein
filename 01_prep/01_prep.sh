#!/bin/bash
#===============================================================================
# 01_prep.sh - System Preparation for EM
#===============================================================================
# This script prepares the system from PDB to solvated/ionized structure
#
# Usage: scripts/01_prep.sh <input.pdb> [force_field] [water_model]
#   input.pdb    : Cleaned PDB file
#   force_field  : Force field name (default: charmm36-jul2022)
#   water_model  : Water model (default: tip3p)
#
# Example: scripts/01_prep.sh protein.pdb [charmm36-jul2022] [tip3p]
#===============================================================================

set -e  # Stop if any command fails

# ============== MODULES ==============
module purge
#module load gcc/11.2.0         # for alpine/blanca
#module load openmpi/4.1.1      # for alpine/blanca
#module load gromacs/2024.2     # for alpine/blanca
#module load GROMACS/2024.2     # for FIJI


# ============== CONFIGURATION ==============
# Input arguments
INPUT_PDB="${1:?ERROR: Please provide input PDB file as first argument}"
FF="${2:-charmm36-jul2022}"
WATER="${3:-tip3p}"
BOX_DIST="2"            # Distance from protein to box edge (nm)
BOX_TYPE="cubic"        # Box type (cubic, dodecahedron, etc.)
CONC="0.15"             # Salt concentration (M) - physiological ~0.15 M

# Directories
PREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${PREP_DIR}/.."
MDP_DIR="${PROJ_DIR}/mdp"
EM_DIR="${PROJ_DIR}/02_em"


# ============== CHECKS  ==============
# Make sure input PDB exists
if [ ! -f "${INPUT_PDB}" ]; then
    echo "ERROR: Input PDB file not found: ${INPUT_PDB}"
    exit 1
fi

# Make sure GROMACS was loaded
if ! command -v gmx &> /dev/null; then
    echo "ERROR: GROMACS (gmx) not found in PATH"
    exit 1
fi

echo "=============================================="
echo "GROMACS System Preparation"
echo "=============================================="
echo "Input PDB: ${INPUT_PDB}"
echo "Force Field: ${FF}"
echo "Water Model: ${WATER}"
echo "Box Type: ${BOX_TYPE}"
echo "Box Distance: ${BOX_DIST} nm"
echo "Salt Concentration: ${CONC} M"
echo "=============================================="


# ============== 1. TOPOLOGY (PDB2GMX) ==============
echo ""
echo "Step 1: Generate topology from PDB..."
echo "--------------------------------------"
gmx pdb2gmx -f "${INPUT_PDB}" \
            -o "1_processed.gro" \
            -water "${WATER}" \
            -ff "${FF}" \
            -ignh # ignore existing hydrogens in PDB


# ============== 2. DEFINE BOX (EDITCONF) ==============
echo ""
echo "Step 2: Define simulation box..."
echo "--------------------------------------"
gmx editconf -f "1_processed.gro" \
             -o "2_boxed.gro" \
             -c \
             -d "${BOX_DIST}" \
             -bt "${BOX_TYPE}"


# ============== 3. SOLVATE SYSTEM (SOLVATE) ==============
echo ""
echo "Step 3: Solvate the system..."
echo "--------------------------------------"
gmx solvate -cp "2_boxed.gro" \
            -cs spc216.gro \
            -o "3_solvated.gro" \
            -p "topol.top" 


# ============== 4. ADD IONS (GENION) ==============
echo ""
echo "Step 4: Add ions to neutralize and set ionic concentration..."
echo "--------------------------------------"
gmx grompp -f "${MDP_DIR}/ions.mdp" \
           -c "3_solvated.gro" \
           -p "topol.top" \
           -o "4_ions.tpr" 

echo "SOL" | gmx genion -s "4_ions.tpr" \
                        -o "4_solvated_ions.gro" \
                        -p "topol.top" \
                        -pname NA \
                        -nname CL \
                        -neutral \
                        -conc "${CONC}"


# ============== 5. PREPROCESS FOR EM (GROMPP) ==============
echo ""
echo "Step 5: Prepare energy minimization input..."
echo "--------------------------------------"
gmx grompp -f "${MDP_DIR}/em.mdp" \
           -c "4_solvated_ions.gro" \
           -p "topol.top" \
           -o "${EM_DIR}/em.tpr"

cp topol.top "${PROJ_DIR}/"
cp *.itp "${PROJ_DIR}/"


# ============== SUMMARY ==============
echo ""
echo "=============================================="
echo "System preparation complete!"
echo "=============================================="
echo ""
echo "Important files:"
echo "  -  topol.top                   : System topology (root dir)"
echo "  - 01_prep/4_solvated_ions.gro  : Solvated and ionized structure"
echo "  - 02_em/em.tpr                 : Energy minimization input"
echo ""
echo "Next step: Run energy minimization using sbatch scripts/02_em.sbatch"
echo "=============================================="
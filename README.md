# All-Atom MD Simulation Workflow (GROMACS / HPC)

A modular pipeline for running all-atom molecular dynamics simulations of apo proteins using GROMACS on HPC clusters (University of Colorado Alpine/Blanca and FIJI).

## Force Field and Parameters

- **Force field:** CHARMM36 (July 2022)
- **Water model:** TIP3P (configurable)
- **Temperature:** 310 K (physiological)
- **Salt concentration:** 0.15 M NaCl (physiological)
- **Production length:** 1 microsecond (1000 ns)
- **Timestep:** 2 fs
- **VdW:** Force-switch from 1.0 to 1.2 nm (CHARMM36 requirement)
- **Electrostatics:** PME with 1.2 nm real-space cutoff
- **Thermostat:** V-rescale
- **Barostat:** C-rescale (equilibration), Parrinello-Rahman (production)

## Directory Structure

```
.
├── 01_prep/                 # System preparation (runs interactively)
│   ├── 01_prep.sh           # Preparation script
│   ├── charmm36-jul2022.ff/ # Force field (local copy)
│   └── p1_apo_cleaned.pdb   # Input protein structure
├── 02_em/                   # Energy minimization output
├── 03_nvt/                  # NVT equilibration output
├── 04_npt/                  # NPT equilibration output
├── 05_md/                   # Production MD output
├── 06_analysis/             # Analysis output
├── charmm36-jul2022.ff/     # Force field database
├── logs/                    # SLURM job logs
├── mdp/                     # GROMACS parameter files
│   ├── ions.mdp             # Ion placement
│   ├── em.mdp               # Energy minimization
│   ├── nvt.mdp              # NVT equilibration
│   ├── npt.mdp              # NPT equilibration
│   └── md.mdp               # Production MD
└── scripts/                 # SLURM job submission scripts
    ├── 02_em.sbatch
    ├── 03_nvt.sbatch
    ├── 04_npt.sbatch
    ├── 05_md.sbatch
    └── 06_analysis.sbatch
```

## Pipeline Overview

| Stage | Script | Method | Hardware | Duration |
|-------|--------|--------|----------|----------|
| 1. Preparation | `01_prep/01_prep.sh` | pdb2gmx, solvate, genion | Login node (interactive) | - |
| 2. Energy Minimization | `scripts/02_em.sbatch` | Steepest descent | CPU (32 cores) | 50,000 steps max |
| 3. NVT Equilibration | `scripts/03_nvt.sbatch` | MD with position restraints | GPU (A100) | 1 ns |
| 4. NPT Equilibration | `scripts/04_npt.sbatch` | MD with position restraints | GPU (A100) | 1 ns |
| 5. Production MD | `scripts/05_md.sbatch` | Unrestrained MD | GPU (A100) | 1000 ns |
| 6. Analysis | `scripts/06_analysis.sbatch` | RMSD, RoG, energy, PBC | CPU (4 cores) | - |

## Prerequisites

- GROMACS 2024.2 (or compatible version)
- SLURM workload manager
- Access to GPU nodes (A100) for stages 3-5

Load the appropriate modules for your cluster before running. Each script has commented module lines for Alpine/Blanca and FIJI -- uncomment the set that matches your cluster.

## Usage

All SLURM jobs should be submitted from the **project root directory**.

### 1. Prepare the system

```bash
# Load GROMACS modules first, then:
cd 01_prep
bash 01_prep.sh [p1_apo_cleaned.pdb/p1h1_apo_cleaned.pdb]
cd ..
```

This generates the topology, solvates the system, adds ions, and prepares the EM input (`02_em/em.tpr`).

### 2. Energy minimization

```bash
sbatch scripts/02_em.sbatch
```

Runs steepest descent minimization and prepares NVT input.

### 3. NVT equilibration

```bash
sbatch scripts/03_nvt.sbatch
```

1 ns constant-volume equilibration at 310 K with position restraints on protein heavy atoms. Prepares NPT input.

### 4. NPT equilibration

```bash
sbatch scripts/04_npt.sbatch
```

1 ns constant-pressure equilibration at 310 K / 1 bar with position restraints. Prepares production MD input.

**Check outputs before proceeding:** Verify that pressure fluctuates around 1 bar (large instantaneous fluctuations are normal) and density is stable near ~1000 kg/m^3.

### 5. Production MD

```bash
sbatch scripts/05_md.sbatch
```

Runs unrestrained MD for up to 1 microsecond. The script uses checkpoint-based continuation with `-maxh` to stay within the SLURM walltime. If the simulation does not finish within the time limit, the job **automatically resubmits itself** to continue from the last checkpoint.

### 6. Analysis

```bash
sbatch scripts/06_analysis.sbatch
```

Performs PBC corrections, then computes:

- **RMSD** (C-alpha and backbone) vs MD reference and vs pre-equilibrated structure
- **Radius of gyration**
- **Energy terms:** potential, total, temperature, pressure, density, volume
- **Thinned trajectory** (1 frame/ns) for visualization

Output is organized under `06_analysis/`.

## Customization

Key parameters can be adjusted in the preparation script and MDP files:

| Parameter | File | Default |
|-----------|------|---------|
| Force field | `01_prep.sh` arg 2 | `charmm36-jul2022` |
| Water model | `01_prep.sh` arg 3 | `tip3p` |
| Box distance | `01_prep.sh` `BOX_DIST` | 2 nm |
| Box type | `01_prep.sh` `BOX_TYPE` | cubic |
| Salt concentration | `01_prep.sh` `CONC` | 0.15 M |
| NVT/NPT length | `nvt.mdp` / `npt.mdp` `nsteps` | 500,000 (1 ns) |
| Production length | `md.mdp` `nsteps` | 500,000,000 (1 us) |
| Temperature | all MD `.mdp` files `ref_t` | 310 K |

## Notes

- SLURM partition, QoS, node, and email fields in the sbatch scripts are **placeholders** -- edit them for your cluster before submitting.
- Module load lines are commented out in all scripts -- uncomment the correct set for your cluster (Alpine/Blanca or FIJI).
- The production MD script automatically resubmits on timeout. To stop the chain, cancel the pending job with `scancel`.

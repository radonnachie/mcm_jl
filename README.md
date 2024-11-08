# Multiplierless Constant Multiplication

## Use

### 1. Setup
- Obtain a WSL licence for Gurobi and place it at the root of this repository: `./gurobi.lic`.
### 2. Execute Benchmarks
- `docker compose up mcm_jl_benchmark`
### 3. Review Results
- `docker compose up read_best`


# Upper bound analysis

nonzeropairs: min=0.4, mean=0.6403101, max=1.0, stdev=0.27276123
uniqueterms: min=0.03448276, mean=0.4153989, max=1.6666666, stdev=0.334281

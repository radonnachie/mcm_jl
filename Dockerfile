FROM julia:bullseye

WORKDIR /work
ENV GRB_LICENSE_FILE=/work/gurobi.lic

RUN julia -e 'using Pkg; Pkg.add("Pluto"); Pkg.add("PlutoUI"); Pkg.add("JuMP"); Pkg.add("Gurobi");'

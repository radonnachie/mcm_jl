FROM julia:1.11-bullseye

WORKDIR /work
ENV GRB_LICENSE_FILE=/work/gurobi.lic

COPY . /work/

RUN julia -e 'using Pkg; Pkg.develop(path="/work/"); Pkg.instantiate(); Pkg.precompile();'
RUN julia -e 'using Pkg; Pkg.add("Pluto"); Pkg.add("PlutoUI"); Pkg.add("ArgParse"); Pkg.add("Serialization");'

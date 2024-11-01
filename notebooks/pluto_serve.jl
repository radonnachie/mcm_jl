using Pkg;
using Pluto;

Pkg.activate(".");
Pluto.run(;
  require_secret_for_access=false,
  launch_browser=false,
  host="0.0.0.0",
  port=1234
)
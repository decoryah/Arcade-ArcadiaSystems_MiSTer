# Vendored modules

Third-party HDL copied into the tree (no submodules, so the build is self-contained and reproducible). Each keeps its own
licence alongside.

| module | upstream | licence |
|---|---|---|
| minimig | https://github.com/MiSTer-devel/Minimig-AGA_MiSTer @ ec1353dc1b36e1c1a91fe14786ec7e09ec2a2cf1 (`rtl/` plus `hps_ext.v`; the upstream test benches under `rtl/sim`, `rtl/A2065/sim` and `rtl/fpga-toccata/sim` are left out) | GPL-3.0 or later |
| sys (top level) | the MiSTer framework as shipped in the same Minimig-AGA_MiSTer commit | GPL-3.0 or later |

To update one: re-copy from upstream at the new commit and record it here.

## Local changes

The first commit holds the upstream files unchanged, so `git log -p -- modules/minimig` shows every change made for the
Arcadia hardware. Each one is listed here as it is made.

(none yet)

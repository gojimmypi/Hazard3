#!/bin/bash

set -euo pipefail

# Populate only the native-Verilog UberDDR3 files used by the ULX4M-LD target.
# The exact upstream commit is pinned so future upstream changes cannot alter a
# previously reviewed Hazard3 build.
readonly UBERDDR3_REPOSITORY="https://github.com/AngeloJacobo/UberDDR3.git"
readonly UBERDDR3_COMMIT="4a51b9671347130759c9980d6756918f084e2124"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/hazard3-uberddr3.XXXXXX")"

cleanup()
{
    case "${temporary_directory}" in
    "${TMPDIR:-/tmp}"/hazard3-uberddr3.*)
        rm -rf -- "${temporary_directory}"
        ;;
    *)
        printf 'Refusing to remove unexpected temporary path: %s\n' \
            "${temporary_directory}" >&2
        ;;
    esac
}
trap cleanup EXIT

git -C "${temporary_directory}" init --quiet
git -C "${temporary_directory}" remote add origin "${UBERDDR3_REPOSITORY}"
git -C "${temporary_directory}" fetch --quiet --depth 1 origin \
    "${UBERDDR3_COMMIT}"
git -C "${temporary_directory}" checkout --quiet --detach FETCH_HEAD

mkdir -p "${script_dir}/rtl/ecp5_phy"

# Replace a destination only when its bytes actually differ. Re-running this
# script therefore does not change timestamps on already-correct source files.
install_if_changed()
{
    local source_file="$1"
    local destination_file="$2"

    if [[ -f "${destination_file}" ]] && cmp -s -- \
        "${source_file}" "${destination_file}"; then
        return
    fi

    cp -- "${source_file}" "${destination_file}"
}

# Select the ECP5 PHY in the same compilation unit as ddr3_top.v. The pinned
# upstream top-level omits four parameter forwards in its ECP5 branch, so the
# awk transformation also forwards the selected clock periods and PHY options.
# The exact expected source line is checked below; an upstream mismatch stops
# the script instead of silently producing an unreviewed local variant.
readonly upstream_top="${temporary_directory}/rtl/ddr3_top.v"
readonly patched_top="${temporary_directory}/rtl/ddr3_top_ecp5.v"
readonly local_top="${script_dir}/rtl/ddr3_top.v"
readonly expected_parameter_line='.CONTROLLER_CLK_PERIOD(CONTROLLER_CLK_PERIOD) //ps, period of clock input to this DDR3 controller module'

if [[ "$(grep -Fxc "                ${expected_parameter_line}" "${upstream_top}")" -ne 1 ]]; then
    printf 'Unexpected UberDDR3 ECP5 parameter block at pinned commit.\n' >&2
    exit 1
fi

{
    printf '%s\n\n' '`define LATTICE_ECP5_PHY'
    awk '
        /`else \/\/ LATTICE ECP5 PHY/ {
            in_ecp5_branch = 1
        }
        in_ecp5_branch && /[.]CONTROLLER_CLK_PERIOD[(]CONTROLLER_CLK_PERIOD[)]/ {
            print "                .CONTROLLER_CLK_PERIOD(CONTROLLER_CLK_PERIOD),"
            print "                .DDR3_CLK_PERIOD(DDR3_CLK_PERIOD),"
            print "                .ODELAY_SUPPORTED(ODELAY_SUPPORTED),"
            print "                .DUAL_RANK_DIMM(DUAL_RANK_DIMM)"
            in_ecp5_branch = 0
            next
        }
        { print }
    ' "${upstream_top}"
} > "${patched_top}"

install_if_changed "${patched_top}" "${local_top}"
install_if_changed "${temporary_directory}/rtl/ddr3_controller.v" \
    "${script_dir}/rtl/ddr3_controller.v"
install_if_changed "${temporary_directory}/rtl/ecp5_phy/ddr3_phy_ecp5.v" \
    "${script_dir}/rtl/ecp5_phy/ddr3_phy_ecp5.v"
install_if_changed "${temporary_directory}/rtl/ecp5_phy/iserdes_soft.v" \
    "${script_dir}/rtl/ecp5_phy/iserdes_soft.v"
install_if_changed "${temporary_directory}/rtl/ecp5_phy/oserdes_soft.v" \
    "${script_dir}/rtl/ecp5_phy/oserdes_soft.v"
install_if_changed "${temporary_directory}/LICENSE" "${script_dir}/LICENSE"

printf 'UberDDR3 native Verilog populated from commit %s\n' \
    "${UBERDDR3_COMMIT}"

`default_nettype none

module rvfi_bus_observer_ahb5 #(
	parameter XLEN = 32,
	parameter BUSLEN = 32
) (
	input wire                 clock,
	input wire                 reset,

	input wire [XLEN-1:0]      ahb_haddr,
	input wire                 ahb_hwrite,
	input wire [1:0]           ahb_htrans,
	input wire [2:0]           ahb_hsize,
	input wire [2:0]           ahb_hburst,
	input wire [6:0]           ahb_hprot,      // HPROT[6:4] are optional; tie to 0 if not implemented
	input wire [7:0]           ahb_hmaster,
	input wire                 ahb_hexcl,      // Tie low if not implemented
	input wire                 ahb_hready,
	input wire                 ahb_hresp,
	input wire                 ahb_hexokay,    // Tie low if not implemented
	input wire [BUSLEN-1:0]    ahb_hwdata,
	input wire [BUSLEN-1:0]    ahb_hrdata,

	output wire                rvfi_bus_valid,
	output wire                rvfi_bus_insn,
	output wire                rvfi_bus_data,
	output wire                rvfi_bus_fault,
	output wire [XLEN-1:0]     rvfi_bus_addr,
	output wire [BUSLEN/8-1:0] rvfi_bus_rmask,
	output wire [BUSLEN/8-1:0] rvfi_bus_wmask,
	output wire [BUSLEN-1:0]   rvfi_bus_rdata,
	output wire [BUSLEN-1:0]   rvfi_bus_wdata
);

localparam HTRANS_IDLE = 2'h0;
localparam HTRANS_NSEQ = 2'h2;
localparam HTRANS_SEQ  = 2'h3;

// ----------------------------------------------------------------------------
// Decode current address phase

wire [XLEN-1:0] hsize_lsb_mask = ~({XLEN{1'b1}} << ahb_hsize);

wire [BUSLEN/8-1:0] byte_mask_aph =
	~({BUSLEN / 8{1'b1}} << (1 << ahb_hsize)) <<
	ahb_haddr[$clog2(BUSLEN/8)-1:0];

// ----------------------------------------------------------------------------
// Validate address-phase signals

always @ (posedge clock) begin
	// HADDR should be aligned to transfer size; only strictly required for
	// bursts and exclusives, but practical bus implementations have this
	// constraint for all transfers, and RVFI bus records are BUSLEN-aligned.
	if (ahb_htrans[1]) assert(~|(ahb_haddr & hsize_lsb_mask));
	// HSIZE should not indicate greater than bus-sized transfer
	assert(ahb_hsize <= $clog2(BUSLEN / 8));
end

// ----------------------------------------------------------------------------
// Advance address-phase transfer attributes to data phase

reg                bus_valid_dph;
reg                bus_insn_dph;
reg                bus_data_dph;
reg [XLEN-1:0]     bus_addr_dph;
reg [BUSLEN/8-1:0] bus_rmask_dph;
reg [BUSLEN/8-1:0] bus_wmask_dph;

always @ (posedge clock) begin
	if (reset) begin
		bus_valid_dph <= 1'b0;
		bus_insn_dph  <= 1'b0;
		bus_data_dph  <= 1'b0;
		bus_addr_dph  <= {XLEN{1'b0}};
		bus_rmask_dph <= {BUSLEN/8{1'b0}};
		bus_wmask_dph <= {BUSLEN/8{1'b0}};
	end else if (ahb_hready) begin
		bus_valid_dph <= ahb_htrans[1];
		bus_insn_dph  <= !ahb_hprot[0];
		bus_data_dph  <= ahb_hprot[0];
		bus_addr_dph  <= ahb_haddr & ({XLEN{1'b1}} << $clog2(BUSLEN / 8));
		bus_rmask_dph <= byte_mask_aph & {BUSLEN/8{!ahb_hwrite}};
		bus_wmask_dph <= byte_mask_aph & {BUSLEN/8{ ahb_hwrite}};
	end
end

// ----------------------------------------------------------------------------
// Emit RVFI bus record at end of data phase

assign rvfi_bus_valid = bus_valid_dph && ahb_hready;
assign rvfi_bus_insn  = bus_insn_dph;
assign rvfi_bus_data  = bus_data_dph;
assign rvfi_bus_fault = ahb_hresp;
assign rvfi_bus_addr  = bus_addr_dph;
assign rvfi_bus_rmask = bus_rmask_dph & {BUSLEN/8{!ahb_hresp}};
assign rvfi_bus_wmask = bus_wmask_dph & {BUSLEN/8{!ahb_hresp}};
assign rvfi_bus_rdata = ahb_hrdata;
assign rvfi_bus_wdata = ahb_hwdata;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif

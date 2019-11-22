`default_nettype none

`define	UARTSETUP	434	// Must match testbus_tb, =4Mb w/ a 100MHz ck
module tl45_comp(
    i_clk, i_reset,
    i_halt_proc,
    i_uart, o_uart,
    sdram_clk   ,
    sdr_cs_n    ,
    sdr_cke     ,
    sdr_ras_n   ,
    sdr_cas_n   ,
    sdr_we_n    ,
    sdr_dqm     ,
    sdr_ba      ,
    sdr_addr    ,
    sdr_dq      ,
    inst_decode_err,
`ifndef VERILATOR
	ssegs,
`endif
    opcode_breakout,
    o_valid,
    o_lwopcode,
    o_clk,
    o_halt,
    out_wb_stb,
    out_wb_err,
    out_wb_ack,
    out_wb_cyc,
    out_wb_stall,
    out_fetch_cache_hit,
    i_sw16,

    o_leds,
    i_switches,

    io_disp_data,
    o_disp_rw,
    o_disp_en_n,
    o_disp_rs,
    o_disp_on_n,
    o_disp_blon,

    sdc_o_cs,
    sdc_o_sck,
    sdc_o_mosi,
    sdc_i_miso,
);
    input i_sw16;
    output wire out_wb_stb,out_wb_err,out_wb_ack,out_wb_cyc, out_wb_stall, out_fetch_cache_hit;

    inout wire [7:0] io_disp_data;
    output wire o_valid;
    output wire o_disp_rw, o_disp_blon, o_disp_en_n, o_disp_on_n, o_disp_rs;
    input wire [15:0] i_switches;
    output wire [15:0] o_leds;
    output wire [4:0] opcode_breakout;
    output wire [7:0] o_lwopcode;
    output wire o_clk, o_halt;
    assign o_clk = i_clk;
    assign o_halt = i_halt_proc;
`ifndef VERILATOR
    output wire [6:0] ssegs[8];
`else
    wire [6:0] ssegs[8];
`endif
	input i_uart;
	output o_uart;
    input wire i_halt_proc;
    input wire i_clk, i_reset;
    output wire inst_decode_err;

    // SDRAM IO
    output wire sdram_clk;
    wire dram_clk_source;
`ifndef VERILATOR
    dram_pll dram_clock_pll(i_clk, sdram_clk);
`endif
    // assign sdram_clk = i_clk;
    output wire sdr_cs_n;
    output wire sdr_cke;
    output wire sdr_ras_n;
    output wire sdr_cas_n;
    output wire sdr_we_n;
    output wire [1:0] sdr_dqm;
    output wire [1:0] sdr_ba;
    output wire [11:0] sdr_addr;
    inout wire [15:0] sdr_dq;

    // SD Card SPI
    output	wire sdc_o_sck, sdc_o_mosi;
    input	wire sdc_i_miso;
    output wire sdc_o_cs;
    wire sdc_o_cs_n;
    assign sdc_o_cs = sdc_o_cs_n;
	 
	 // RESET
	 wire reset;
`ifdef VERILATOR
    assign reset = i_reset;
`else
	 assign reset = !i_reset;
`endif

	 
    //MEME
    //wire [12:0] sdr_addr_fake;
    //assign sdr_addr = sdr_addr_fake[11:0];

    // Memory Bus Hierarchy
    // * - denotes higher priority
    // Right side are masters, left are slaves
    //
    // Memory - | - debug
    //          |
    //          |
    //     IO - |*-*| - ifetch
    //          :   |
    //          :   |
    //          :   |*-*dfetch
    //
    //     main ^   ^ internal
    //   (master)       (ibus)
    //

    // master Wishbone
    wire master_o_wb_cyc, master_o_wb_stb, master_o_wb_we;
    wire [29:0] master_o_wb_addr;
    wire [31:0] master_o_wb_data;
    wire [3:0] master_o_wb_sel;

    reg master_i_wb_ack, master_i_wb_err;
    wire master_i_wb_stall;
    reg [31:0] master_i_wb_data;

    // WISHBONE BREAKOUT
    assign out_wb_ack = master_i_wb_ack;
    assign out_wb_cyc = master_o_wb_cyc;
    assign out_wb_err = master_i_wb_err;
    assign out_wb_stb = master_o_wb_stb;
    assign out_wb_stall = master_i_wb_stall;


    // dbgbus Wishbone
    wire dbgbus_o_wb_cyc, dbgbus_o_wb_stb, dbgbus_o_wb_we;
    wire [29:0] dbgbus_o_wb_addr;
    wire [31:0] dbgbus_o_wb_data;
    wire [3:0] dbgbus_o_wb_sel;

    wire dbgbus_i_wb_ack, dbgbus_i_wb_stall, dbgbus_i_wb_err;
    wire [31:0] dbgbus_i_wb_data;
    // ibus Wishbone
    wire ibus_o_wb_cyc, ibus_o_wb_stb, ibus_o_wb_we;
    wire [29:0] ibus_o_wb_addr;
    wire [31:0] ibus_o_wb_data;
    wire [3:0] ibus_o_wb_sel;

    wire ibus_i_wb_ack, ibus_i_wb_stall, ibus_i_wb_err;
    wire [31:0] ibus_i_wb_data;

    // ifetch Wishbone
    wire ifetch_o_wb_cyc, ifetch_o_wb_stb, ifetch_o_wb_we;
    wire [29:0] ifetch_o_wb_addr;
    wire [31:0] ifetch_o_wb_data;
    wire [3:0] ifetch_o_wb_sel;

    wire ifetch_i_wb_ack, ifetch_i_wb_stall, ifetch_i_wb_err;
    wire [31:0] ifetch_i_wb_data;

    // dfetch Wishbone
    wire dfetch_o_wb_cyc, dfetch_o_wb_stb, dfetch_o_wb_we;
    wire [29:0] dfetch_o_wb_addr;
    wire [31:0] dfetch_o_wb_data;
    wire [3:0] dfetch_o_wb_sel;
    
    wire dfetch_i_wb_ack, dfetch_i_wb_stall, dfetch_i_wb_err;
    wire [31:0] dfetch_i_wb_data;

    // fetch buffer
    wire [31:0] fetch_buf_pc, fetch_buf_inst;

    // decode buffer
    wire [31:0] decode_buf_pc;
    wire [4:0] decode_buf_opcode;
    wire decode_buf_ri;
    wire [3:0] decode_buf_dr, decode_buf_sr1, decode_buf_sr2;
    wire [31:0] decode_buf_imm;

    // rr buffer
    wire [4:0] rr_buf_opcode;
    wire [3:0] rr_buf_dr;
    wire [3:0] rr_buf_jmp_cond;
    wire [31:0] rr_buf_sr1_val, rr_buf_sr2_val, rr_buf_pc;
    wire [31:0] rr_buf_target_address_offset; // Target Jump Address Offset

    // ALU buffer
    wire [31:0] alu_buf_value;
    wire [3:0] alu_buf_dr;
    wire alu_buf_ld_newpc;
    wire [31:0] alu_buf_br_pc;

    // Mem buffer
    wire [31:0] mem_buf_value;
    wire [3:0] mem_buf_dr;

    wire mem_buf_ld_newpc;
    wire [31:0] mem_buf_br_pc;

    // stalls & flushes
    wire stall_fetch_decode, stall_decode_rr, stall_rr_alu, stall_rr_mem, stall_alu_wb;
    wire flush_fetch_decode, flush_decode_rr, flush_rr_alu, flush_rr_mem;

    // Forwarding
    wire [3:0] of1_reg, of1_reg_alu, of1_reg_mem, of2_reg;
    wire [31:0] of1_val, of1_val_alu, of1_val_mem, of2_val;

    // Shared components

    wire [3:0] dprf_reg1, dprf_reg2, dprf_wreg;
    wire [31:0] dprf_reg1_val, dprf_reg2_val, dprf_wreg_val;
    wire dprf_we_wreg;

    tl45_dprf dprf(
        .clk(i_clk),
        .reset(reset),
        .readAdd1(dprf_reg1),
        .readAdd2(dprf_reg2),
        .dataO1(dprf_reg1_val),
        .dataO2(dprf_reg2_val),
        .writeAdd(dprf_wreg),
        .dataI(dprf_wreg_val),
        .wrREG(dprf_we_wreg)
    );


    // Stages

    // tl45_prefetch
	 wire [3:0] fetch_current_state;
    tl45_pfetch_with_cache fetch(
        .i_clk(i_clk),
        .i_reset(reset || i_halt_proc),
        .i_pipe_stall(stall_fetch_decode || inst_decode_err),
        .i_pipe_flush(flush_fetch_decode || i_halt_proc),
        .i_new_pc(alu_buf_ld_newpc || mem_buf_ld_newpc),
        .i_pc(alu_buf_ld_newpc ? alu_buf_br_pc : mem_buf_br_pc),

        .o_wb_cyc(ifetch_o_wb_cyc),
        .o_wb_stb(ifetch_o_wb_stb),
        .o_wb_we(ifetch_o_wb_we),
        .o_wb_addr(ifetch_o_wb_addr),
        .o_wb_data(ifetch_o_wb_data),
        .o_wb_sel(ifetch_o_wb_sel),
        .i_wb_ack(ifetch_i_wb_ack),
        .i_wb_stall(ifetch_i_wb_stall),
        .i_wb_err(ifetch_i_wb_err),
        .i_wb_data(ifetch_i_wb_data),

        .o_buf_pc(fetch_buf_pc),
        .o_buf_inst(fetch_buf_inst),
        .o_cache_hit(out_fetch_cache_hit),
        .current_state(fetch_current_state)
    );

    tl45_decode decode(
        .i_clk(i_clk),
        .i_reset(reset),
        .o_pipe_stall(stall_fetch_decode),
        .i_pipe_stall(stall_decode_rr),
        .o_pipe_flush(flush_fetch_decode),
        .i_pipe_flush(flush_decode_rr),

        .i_buf_pc(fetch_buf_pc),
        .i_buf_inst(fetch_buf_inst),

        .o_buf_pc(decode_buf_pc),
        .o_buf_opcode(decode_buf_opcode),
        .o_buf_ri(decode_buf_ri),
        .o_buf_dr(decode_buf_dr),
        .o_buf_sr1(decode_buf_sr1),
        .o_buf_sr2(decode_buf_sr2),
        .o_buf_imm(decode_buf_imm),

        .o_decode_err(inst_decode_err)
    );

    tl45_register_read rr(
        .i_clk(i_clk),
        .i_reset(reset),
        .i_pipe_stall(stall_rr_alu || stall_rr_mem),
        .o_pipe_stall(stall_decode_rr),
        .i_pipe_flush(flush_rr_alu || flush_rr_mem),
        .o_pipe_flush(flush_decode_rr),

        .i_opcode(decode_buf_opcode),
        .i_ri(decode_buf_ri),
        .i_dr(decode_buf_dr),
        .i_sr1(decode_buf_sr1),
        .i_sr2(decode_buf_sr2),
        .i_imm32(decode_buf_imm),
        .i_pc(decode_buf_pc),

        .o_dprf_read_a1(dprf_reg1),
        .o_dprf_read_a2(dprf_reg2),
        .i_dprf_d1(dprf_reg1_val),
        .i_dprf_d2(dprf_reg2_val),

        .i_of1_reg(of1_reg),
        .i_of1_data(of1_val),
        .i_of2_reg(of2_reg),
        .i_of2_data(of2_val),

        .o_opcode(rr_buf_opcode),
        .o_dr(rr_buf_dr),
        .o_jmp_cond(rr_buf_jmp_cond),
        .o_sr1_val(rr_buf_sr1_val),
        .o_sr2_val(rr_buf_sr2_val),
        .o_target_address_offset(rr_buf_target_address_offset),
        .o_pc(rr_buf_pc)
    );

    assign opcode_breakout = rr_buf_opcode;
    assign o_lwopcode = rr_buf_pc[7:0];
    assign o_valid = !(stall_rr_alu || stall_rr_mem);

    assign of1_reg = of1_reg_alu != 0 ? of1_reg_alu : of1_reg_mem;
    assign of1_val = of1_reg_alu != 0 ? of1_val_alu : of1_val_mem;

    tl45_alu alu(
        .i_clk(i_clk),
        .i_reset(reset),
        .i_pipe_stall(stall_alu_wb),
        .o_pipe_stall(stall_rr_alu),
        .i_pipe_flush(0),
        .o_pipe_flush(flush_rr_alu),

        .i_opcode(rr_buf_opcode),
        .i_dr(rr_buf_dr),
        .i_jmp_cond(rr_buf_jmp_cond),
        .i_sr1_val(rr_buf_sr1_val),
        .i_sr2_val(rr_buf_sr2_val),
        .i_target_offset(rr_buf_target_address_offset),
        .i_pc(rr_buf_pc),

        .o_of_reg(of1_reg_alu),
        .o_of_val(of1_val_alu),

        .o_dr(alu_buf_dr),
        .o_value(alu_buf_value),
        .o_ld_newpc(alu_buf_ld_newpc),
        .o_br_pc(alu_buf_br_pc)
    );

    tl45_memory memory(
        .i_clk(i_clk),
        .i_reset(reset),
        .i_pipe_stall(stall_alu_wb),
        .o_pipe_stall(stall_rr_mem),
        .i_pipe_flush(0),
        .o_pipe_flush(flush_rr_mem),

        .o_wb_cyc(dfetch_o_wb_cyc),
        .o_wb_stb(dfetch_o_wb_stb),
        .o_wb_we(dfetch_o_wb_we),
        .o_wb_addr(dfetch_o_wb_addr),
        .o_wb_data(dfetch_o_wb_data),
        .o_wb_sel(dfetch_o_wb_sel),
        .i_wb_ack(dfetch_i_wb_ack),
        .i_wb_stall(dfetch_i_wb_stall),
        .i_wb_err(dfetch_i_wb_err),
        .i_wb_data(dfetch_i_wb_data),

        .i_buf_opcode(rr_buf_opcode),
        .i_buf_dr(rr_buf_dr),
        .i_buf_sr1_val(rr_buf_sr1_val),
        .i_buf_sr2_val(rr_buf_sr2_val),
        .i_buf_imm(rr_buf_target_address_offset),
        .i_buf_pc(rr_buf_pc),

        .o_fwd_dr(of1_reg_mem),
        .o_fwd_val(of1_val_mem),

        .o_buf_dr(mem_buf_dr),
        .o_buf_val(mem_buf_value),
        .o_ld_newpc(mem_buf_ld_newpc),
        .o_br_pc(mem_buf_br_pc)
    );

    tl45_writeback writeback(
        .i_clk(i_clk),
        .i_reset(reset),
        .o_pipe_stall(stall_alu_wb),

        .i_buf_dr(alu_buf_dr != 0 ? alu_buf_dr : mem_buf_dr),
        .i_buf_val(alu_buf_dr != 0 ? alu_buf_value : mem_buf_value),

        .o_fwd_reg(of2_reg),
        .o_fwd_val(of2_val),

        .o_rf_en(dprf_we_wreg),
        .o_rf_reg(dprf_wreg),
        .o_rf_val(dprf_wreg_val)
    );

    // Wishbone master arbitration
    assign dfetch_i_wb_data = ibus_i_wb_data;
    assign ifetch_i_wb_data = ibus_i_wb_data;

    wbpriarbiter #(32, 30) ibus_arbiter(
        .i_clk(i_clk),
        // A
        .i_a_cyc(dfetch_o_wb_cyc),
        .i_a_stb(dfetch_o_wb_stb),
        .i_a_we(dfetch_o_wb_we),
        .i_a_adr(dfetch_o_wb_addr),
        .i_a_dat(dfetch_o_wb_data),
        .i_a_sel(dfetch_o_wb_sel),

        .o_a_ack(dfetch_i_wb_ack),
        .o_a_stall(dfetch_i_wb_stall),
        .o_a_err(dfetch_i_wb_err),

        // B
        .i_b_cyc(ifetch_o_wb_cyc),
        .i_b_stb(ifetch_o_wb_stb),
        .i_b_we(ifetch_o_wb_we),
        .i_b_adr(ifetch_o_wb_addr),
        .i_b_dat(ifetch_o_wb_data),
        .i_b_sel(ifetch_o_wb_sel),

        .o_b_ack(ifetch_i_wb_ack),
        .o_b_stall(ifetch_i_wb_stall),
        .o_b_err(ifetch_i_wb_err),

        // Merged
        .o_cyc(ibus_o_wb_cyc),
        .o_stb(ibus_o_wb_stb),
        .o_we(ibus_o_wb_we),
        .o_adr(ibus_o_wb_addr),
        .o_dat(ibus_o_wb_data),
        .o_sel(ibus_o_wb_sel),

        .i_ack(ibus_i_wb_ack),
        .i_stall(ibus_i_wb_stall),
        .i_err(ibus_i_wb_err)
    );

assign ibus_i_wb_data = master_i_wb_data;
assign dbgbus_i_wb_data = master_i_wb_data;
wbpriarbiter #(32, 30) mbus_arbiter(
        .i_clk(i_clk),
        // A
        .i_a_cyc(ibus_o_wb_cyc),
        .i_a_stb(ibus_o_wb_stb),
        .i_a_we(ibus_o_wb_we),
        .i_a_adr(ibus_o_wb_addr),
        .i_a_dat(ibus_o_wb_data),
        .i_a_sel(ibus_o_wb_sel),

        .o_a_ack(ibus_i_wb_ack),
        .o_a_stall(ibus_i_wb_stall),
        .o_a_err(ibus_i_wb_err),

        // B
        .i_b_cyc(dbgbus_o_wb_cyc),
        .i_b_stb(dbgbus_o_wb_stb),
        .i_b_we(dbgbus_o_wb_we),
        .i_b_adr(dbgbus_o_wb_addr),
        .i_b_dat(dbgbus_o_wb_data),
        .i_b_sel(dbgbus_o_wb_sel),

        .o_b_ack(dbgbus_i_wb_ack),
        .o_b_stall(dbgbus_i_wb_stall),
        .o_b_err(dbgbus_i_wb_err),

        // Merged
        .o_cyc(master_o_wb_cyc),
        .o_stb(master_o_wb_stb),
        .o_we(master_o_wb_we),
        .o_adr(master_o_wb_addr),
        .o_dat(master_o_wb_data),
        .o_sel(master_o_wb_sel),

        .i_ack(master_i_wb_ack),
        .i_stall(master_i_wb_stall),
        .i_err(master_i_wb_err)
    );

// Master Bus Address Decoding
//
// Define some wires for returning values to the bus from our various
// components
reg	    [31:0]	smpl_data; // Simple Device
wire	[31:0]	mem_data; // MEM
wire    [31:0] sseg_data, sw_led_data, sdc_data, lcd_data, timer_data;
wire	smpl_stall, mem_stall, sseg_stall, sw_led_stall, sdc_stall, lcd_stall, timer_stall;
reg	    smpl_interrupt;
wire	mem_ack;
reg	    smpl_ack;
wire    sseg_ack, sw_led_ack, sdc_ack, lcd_ack, timer_ack;

wire	smpl_sel, mem_sel, sseg_sel, sw_led_sel, sdc_sel, lcd_sel, timer_sel;

`ifdef VERILATOR
reg	    [31:0]	v_hook_data; // Simple Device
reg v_hook_ack;
reg v_hook_stall;

    wire v_hook_stb;
    assign v_hook_stb = (master_o_wb_addr[29:12] == 18'h4ff) && master_o_wb_stb;
`endif

// Nothing should be assigned to the null page
//
// 0000 0000 0000 0000 0000 0000 0000 00
// 0000 0000 0xxx xxxx xxxx xxxx xxxx xx - DRAM     8MB
// 0000 0000 1xxx xxxx xxxx xxxx xxxx xx - SCOMP    8MB
//         1 0000 0000 0000 0000 0000 00 - SSEG
//         1 0000 0000 0000 0000 0000 01 - SW/LEDS
//         1 0000 0000 0000 0000 0000 1x - LCD
//         1 0000 0000 0000 0000 0010 xx - SD Card
//         1 0000 0000 0000 01xx xxxx xx - SCOMP
//         1 0011 1111 11xx xxxx xxxx xx - Verilator


// Yaotian's Memory Map
// ------- BUS ADDRESS SAPCE ----------- --SEL
//
// 00 0000 0000 0000 0000 0000 0000 0000 00
// 00 0000 000x xxxx xxxx xxxx xxxx xxxx xx - DRAM 8 MB (0x0000_0000 -> 0x007f_ffff)
// 00 0000 001x xxxx xxxx xxxx xxxx xxxx xx - Simple Device 8 MB (0x0080_0000 -> 0x00ff_ffff)
// 00 0000 0100 0000 0000 0000 0000 0000 xx - SSEG   (4 Bytes) (0x0100_0000 -> 0x0100_0003)
// 00 0000 0100 0000 0000 0000 0000 0001 xx - SW/LED (4 Bytes) (0x0100_0004 -> 0x0100_0007)
// 00 0000 0100 0000 0000 0000 0000 001x xx - LCD    (8 Bytes) (0x0100_0008 -> 0x0100_000f)
// 00 0000 0100 0000 0000 0000 0000 01xx xx - SD     (16Bytes) (0x0100_0010 -> 0x0100_001f)
// 00 0000 0100 0000 0000 0000 0000 1000 xx - ENC(L) (4 Bytes) (0x0100_0020 -> 0x0100_0023)
// 00 0000 0100 0000 0000 0000 0000 1001 xx - ENC(R) (4 Bytes) (0x0100_0024 -> 0x0100_0027)
// 00 0000 0100 0000 0000 0000 0000 1010 xx - TIMER  (4 Bytes) (0x0100_0028 -> 0x0100_002c)
// 00 0000 0100 0000 0000 0001 xxxx xxxx xx - SCOMP  (1KBytes) (0x0100_0400 -> 0x0100_07ff)
//(31)

assign	mem_sel  = (master_o_wb_addr[29:21] == 9'h0); // mem selected
assign	smpl_sel = (master_o_wb_addr[29:21] == 9'h1); // Simple device gets a big block
assign  sseg_sel = (master_o_wb_addr[29:0] == 30'h400000); // SSEG
assign  sw_led_sel = (master_o_wb_addr[29:0] == 30'h400001); // SWITCH LED
assign lcd_sel = (master_o_wb_addr[29:0] ==     30'h400002
                ||master_o_wb_addr[29:0] ==     30'h400003);
assign  sdc_sel = (master_o_wb_addr[29:2] ==    28'b0000_0001_0000_0000_0000_0000_0010);

assign timer_sel = (master_o_wb_addr[29:0] == 30'b00_0000_0100_0000_0000_0000_0000_1010);

wire	none_sel;
assign	none_sel = (!smpl_sel)
    &&(!mem_sel)
    &&(!sseg_sel)
    &&(!sw_led_sel)
    && (!sdc_sel)
    &&(!lcd_sel)
    && (!timer_sel)
`ifdef VERILATOR
    && (!v_hook_stb)
`endif
    ;

always @(posedge i_clk)
    master_i_wb_err <= (master_o_wb_stb) && (none_sel);

// Master Bus Respond
always @(posedge i_clk)
    master_i_wb_ack <= (smpl_ack)
        || (mem_ack)
        || sseg_ack
        || sw_led_ack
        || sdc_ack
        || lcd_ack
        || timer_ack
`ifdef VERILATOR
        || v_hook_ack
`endif
        ;

always @(posedge i_clk)
`ifdef VERILATOR
    if (v_hook_ack)
        master_i_wb_data <= v_hook_data;
    else
`endif
    if (smpl_ack)
        master_i_wb_data <= smpl_data;
    else if (mem_ack)
        master_i_wb_data <= mem_data;
    else if (sseg_ack)
        master_i_wb_data <= sseg_data;
    else if (sw_led_ack)
        master_i_wb_data <= sw_led_data;
    else if (sdc_ack)
        master_i_wb_data <= sdc_data;
    else if (lcd_ack)
        master_i_wb_data <= lcd_data;
    else if (timer_ack)
        master_i_wb_data <= timer_data;
    else
        master_i_wb_data <= 32'h0;

assign	master_i_wb_stall = 
           ((smpl_sel) && (smpl_stall))
        || ((mem_sel)  && (mem_stall))
        || (sseg_sel) && (sseg_stall)
        || sdc_sel && sdc_stall
        || lcd_sel && lcd_stall
        || sw_led_sel && sw_led_stall
        || timer_sel && timer_stall;

// Simple Device
reg	[31:0]	smpl_register, power_counter;
reg	[29:0]	bus_err_address;

always @(posedge i_clk)
    smpl_ack <= ((master_o_wb_stb)&&(smpl_sel));
assign	smpl_stall = 1'b0;
initial	smpl_interrupt = 1'b0;
always @(posedge i_clk)
    if ((master_o_wb_stb)&&(smpl_sel)&&(master_o_wb_we))
    begin
        case(master_o_wb_addr[3:0])
        4'h1: smpl_register  <= master_o_wb_data;
        4'h4: smpl_interrupt <= master_o_wb_data[0];
        default: begin end
        endcase
    end

always @(posedge i_clk)
    case(master_o_wb_addr[3:0])
    4'h0:    smpl_data <= 32'h20191028;
    4'h1:    smpl_data <= smpl_register;
    4'h2:    smpl_data <= { bus_err_address, 2'b00 };
    4'h3:    smpl_data <= power_counter;
    4'h4:    smpl_data <= { 31'h0, smpl_interrupt };
    default: smpl_data <= 32'h00;
    endcase

// Start our clocks since power up counter from zero
initial	power_counter = 0;
always @(posedge i_clk)
    // Count up from zero until the top bit is set
    if (!power_counter[31])
        power_counter <= power_counter + 1'b1;
    else // Once the top bit is set, keep it set forever
        power_counter[30:0] <= power_counter[30:0] + 1'b1;

initial	bus_err_address = 0;
always @(posedge i_clk)
    if (master_i_wb_err)
        bus_err_address <= master_o_wb_addr; // possibly wrong

// IO Devices


// Wishbone Timer
wb_timer timer1(
    i_clk, reset, 
    master_o_wb_cyc, 
    (master_o_wb_stb && timer_sel),
    master_o_wb_we, 
    master_o_wb_addr, master_o_wb_data,
    master_o_wb_sel,
    timer_ack, timer_stall, 
    timer_data);


    wire sdc_int;
    wire [31:0] sdc_debug;

    sdspi #(
        .OPT_SPI_ARBITRATION(0),
        .OPT_CARD_DETECT(0),
        .INITIAL_CLKDIV(7'h3e),
        .STARTUP_CLOCKS(0)
    ) sdcard(
        .i_clk(i_clk),

        .i_wb_cyc(master_o_wb_cyc),
        .i_wb_stb(master_o_wb_stb && sdc_sel),
        .i_wb_we(master_o_wb_we),
        // remap address to what sdspi expects
        .i_wb_addr(master_o_wb_addr[1:0]),
        .i_wb_data(master_o_wb_data),
        .i_wb_sel(master_o_wb_sel),
        .o_wb_stall(sdc_stall),
        .o_wb_ack(sdc_ack),
        .o_wb_data(sdc_data),

        .o_cs_n(sdc_o_cs_n),
        .o_sck(sdc_o_sck),
        .o_mosi(sdc_o_mosi),
        .i_miso(sdc_i_miso),
        .i_card_detect(1'b1),

        .o_int(sdc_int),
        .i_bus_grant(1'b1),
        .o_debug(sdc_debug)
    );

// SevenSeg
wb_sevenseg sevenseg_disp(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && sseg_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    sseg_ack,
    sseg_stall,
    sseg_data,
`ifndef VERILATOR
    ssegs,
`endif
    (i_sw16 ? sdc_debug : fetch_buf_pc),
    inst_decode_err || i_sw16
);

// LCDHD47780
wb_lcdhd47780 de2_lcd(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && lcd_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    lcd_ack,
    lcd_stall,
    lcd_data,
    io_disp_data,
    o_disp_rw,
    o_disp_en_n,
    o_disp_rs,
    o_disp_on_n,
    o_disp_blon
);

// Sw_LED
wb_switch_led de2_switch_led(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && sw_led_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    sw_led_ack,
    sw_led_stall,
    sw_led_data,
    o_leds,
    i_switches
);

`ifdef VERILATOR
    memdev #(16) my_mem(
        .i_clk(i_clk),
        .i_wb_cyc(ibus_o_wb_cyc),
        .i_wb_stb(ibus_o_wb_stb && mem_sel),
        .i_wb_we(ibus_o_wb_we),
        .i_wb_addr(ibus_o_wb_addr[15-2:0]),
        .i_wb_data(ibus_o_wb_data),
        .i_wb_sel(ibus_o_wb_sel),

        .o_wb_ack(mem_ack),
        .o_wb_stall(mem_stall),
        .o_wb_data(mem_data)
    );
`else
	// wire	[15:0]	ram_data;
	// wire		ram_drive_data;
	// reg	[15:0]	r_ram_data;
    // // real mem
    // assign sdr_dq = (ram_drive_data) ? ram_data : 16'bzzzz_zzzz_zzzz_zzzz;
	// reg	[15:0]	r_ram_data_ext_clk;

    // // 2FF Sync
	// always @(posedge i_clk)
	// 	r_ram_data_ext_clk <= sdr_dq;
	// always @(posedge i_clk)
	// 	r_ram_data <= r_ram_data_ext_clk;

	// wire [31:0] sdram_debug;

	// wbsdram yeetmemory(i_clk,
	// 	master_o_wb_cyc, (mem_sel && master_o_wb_stb), master_o_wb_we, 
    //     master_o_wb_addr, master_o_wb_data, master_o_wb_sel,
	// 		mem_ack, mem_stall, mem_data,
	// 	sdr_cs_n, sdr_cke, sdr_ras_n, sdr_cas_n, sdr_we_n,
	// 		sdr_ba, sdr_addr_fake,
	// 		ram_drive_data, r_ram_data, ram_data, sdr_dqm,
	// 	sdram_debug);

    sdram #(
        .SDRAM_MHZ(50),
        .SDRAM_ADDR_W(22),
        .SDRAM_COL_W(8),
        .SDRAM_TARGET("ALTERA") // This is fake news, but whatever
    ) memram (
        i_clk,
        reset,
        
        (mem_sel && master_o_wb_stb),
        master_o_wb_we,
        master_o_wb_sel,
        master_o_wb_cyc,
        {master_o_wb_addr, 2'h0},
        master_o_wb_data,
        mem_data,
        mem_stall,
        mem_ack,

        dram_clk_source,
        sdr_cke,
        sdr_cs_n,
        sdr_ras_n,
        sdr_cas_n,
        sdr_we_n,
        sdr_dqm,
        sdr_addr,
        sdr_ba,
        sdr_dq
    );

`endif

`ifndef VERILATOR
	wire		rx_stb;
	wire	[7:0]	rx_data;
	rxuartlite #(`UARTSETUP) rxtransport(i_clk,
					i_uart, rx_stb, rx_data);

	wire		tx_stb, tx_busy;
	wire	[7:0]	tx_data;
	txuartlite #(`UARTSETUP) txtransport(i_clk,
					tx_stb, tx_data, o_uart, tx_busy);

hbbus	genbus(i_clk,
		// The receive transport wires
		rx_stb, rx_data,
		// The bus control output wires
		dbgbus_o_wb_cyc, dbgbus_o_wb_stb, dbgbus_o_wb_we,
        dbgbus_o_wb_addr, dbgbus_o_wb_data, dbgbus_o_wb_sel,
		//	The return bus wires
		dbgbus_i_wb_ack, dbgbus_i_wb_stall, dbgbus_i_wb_err, dbgbus_i_wb_data,
		// An interrupt line
		0,
		// The return transport wires
		tx_stb, tx_data, tx_busy);
`endif
endmodule : tl45_comp



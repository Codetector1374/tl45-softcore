`default_nettype none

module tl45_memory(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall,

    // Wishbone
    o_wb_cyc, o_wb_stb, o_wb_we,
    o_wb_addr, o_wb_data, o_wb_sel,
    i_wb_ack, i_wb_stall, i_wb_err,
    i_wb_data,
    
    // Buffer In
    i_buf_opcode,
    i_buf_dr, i_buf_sr1_val, i_buf_sr2_val, i_buf_imm,

    // Buffer Out and Forwarding
    o_buf_dr, o_buf_val,
);

input wire i_clk, i_reset;
input wire i_pipe_stall;
output reg o_pipe_stall;

// Wishbone 
output reg o_wb_cyc, o_wb_stb, o_wb_we;
output reg [29:0] o_wb_addr;
output reg [31:0] o_wb_data;
output reg [3:0] o_wb_sel;
initial begin
    o_wb_cyc = 0;
    o_wb_stb = 0;
    o_wb_we = 0;
    o_wb_data = 0;
    o_wb_addr = 0;
end

input wire i_wb_ack, i_wb_stall, i_wb_err;
input wire [31:0] i_wb_data;

// Buffer In
input wire [4:0] i_buf_opcode;
input wire [3:0] i_buf_dr;
input wire [31:0] i_buf_sr1_val, i_buf_sr2_val, i_buf_imm;

// Buffer Out
output reg [3:0] o_buf_dr;
output reg [31:0] o_buf_val;
initial begin
    o_buf_dr = 0;
    o_buf_val = 0;
end


// Internal

// Small inconsistencies between LW, SW, IN, and OUT make this a little
// annoying. Here we generate a bunch of combinational logic so that the state
// machine is simpler.
//
// Buffer Layout:
//  LW: dr <- MEM[sr1+imm]
//  SW: MEM[sr1+imm] <- sr2
//  IN: dr <- IO[imm]
// OUT: IO[imm] <- sr1
//
// However IO is mapped onto the memory bus so mem_addr will hold the mapped
// address for IO. The correct write value will be resolved into wr_val.
//
// IO is mapped into the highest 16 bits of memory however the memory bus is
// only 30 bits wide. To reconcile this, the top 2 bits of the IO imm are
// ignored. 16 + 14 = 30 bits. mem_addr is 32 bits wide. The bottom two bits
// select within a 32 bit word for instruction where this is supported. (none
// right now). When sent on the wishbone bus, only the top 30 bits of mem_addr
// are sent.

wire start_tx;
assign start_tx = (i_buf_opcode == 5'h10 ||   // IN
                   i_buf_opcode == 5'h11 ||   // OUT
                   i_buf_opcode == 5'h14 ||   // LW
                   i_buf_opcode == 5'h15);    // SW

wire is_io;
assign is_io =    (i_buf_opcode == 5'h10 ||   // IN
                   i_buf_opcode == 5'h11);    // OUT

wire is_write;
assign is_write = (i_buf_opcode == 5'h11 ||   // OUT
                   i_buf_opcode == 5'h15);    // SW

wire [31:0] mem_addr;
assign mem_addr = is_io ? {16'hff, i_buf_imm[13:0], 2'b00} : (i_buf_sr1_val + i_buf_imm);

wire [31:0] wr_val;
assign wr_val = is_io ? i_buf_sr1_val : i_buf_sr2_val;

enum integer { 
    IDLE = 0,
     READ_STROBE,  READ_WAIT_ACK, READ_STALLED_OUT, READ_OUT,
    WRITE_STROBE, WRITE_WAIT_ACK,
    LAST_STATE 
} current_state; 

// wishbone combinational control signals
assign o_wb_stb = (current_state == READ_STROBE) || (current_state == WRITE_STROBE);
assign o_wb_we  = (current_state == WRITE_STROBE);
assign o_wb_cyc = (current_state != IDLE && current_state != LAST_STATE);

reg internal_stall;
initial internal_stall = 0;
assign o_pipe_stall = i_pipe_stall || internal_stall;

// internal state machine control signals
wire state_strobe, state_wait_ack;
assign state_strobe = (current_state == READ_STROBE) || (current_state == WRITE_STROBE);
assign state_wait_ack = (current_state == READ_WAIT_ACK) || (current_state == WRITE_WAIT_ACK);


assign internal_stall = (current_state != IDLE) && (current_state != READ_STALLED_OUT) && (current_state != READ_OUT);

reg [31:0] temp_read;


always @(posedge i_clk) begin
    if (i_reset) begin
        current_state <= IDLE;
        o_pipe_stall <= 0;

        o_wb_addr <= 0;
        o_wb_data <= 0;
        o_wb_sel <= 0;

        o_buf_dr <= 0;
        o_buf_val <= 0;
    end
    if (i_pipe_stall) begin 
    end
    else if ((current_state == IDLE) && start_tx) begin
        current_state <= is_write ? WRITE_STROBE : READ_STROBE;
        o_wb_addr <= mem_addr[31:2];
        o_wb_sel <= 4'b1111;
        
        if (is_write)
            o_wb_data <= wr_data;
    end
    else if (state_strobe && !i_wb_stall) begin
        current_state <= current_state == READ_STROBE ? READ_WAIT_ACK : WRITE_WAIT_ACK;
        o_wb_addr <= 0;
        o_wb_sel <= 0;
        o_wb_data <= 0;
    end
    // TODO probably not correct when wb response is on the same clock as the
    // request.
    else if (state_wait_ack && i_wb_ack && i_wb_err) begin
        // for now we'll just squash bus error as a special read value.
        // for write, whatever.
        current_state <= current_state == READ_WAIT_ACK ? (i_pipe_stall ? READ_STALLED_OUT : READ_OUT) : IDLE;
        
        if (!is_write) begin
            if (i_pipe_stall)
                temp_read <= 32'h13371337;
            else begin
                o_buf_dr <= i_buf_dr;
                o_buf_val <= 32'h13371337;
            end
        end
    end
    else if (state_wait_ack && i_wb_ack && !i_wb_err) begin
        current_state <= current_state == READ_WAIT_ACK ? (i_pipe_stall ? READ_STALLED_OUT : READ_OUT) : IDLE;

        if (!is_write) begin
            if (i_pipe_stall)
                temp_read <= i_wb_data;
            else begin
                o_buf_dr <= i_buf_dr;
                o_buf_val <= i_wb_data;
            end
        end
    end
    else if (current_state == READ_STALLED_OUT && !i_pipe_stall) begin
        current_state <= READ_OUT;
        o_buf_dr <= i_buf_dr;
        o_buf_val <= temp_read;
        temp_read <= 0;
    end
    else if (current_state == READ_OUT) begin
        current_state <= IDLE;
        o_buf_dr <= 0;
        o_buf_val <= 0;
    end
end





endmodule



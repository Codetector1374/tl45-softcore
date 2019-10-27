`default_nettype none

module tl45_nofetch(
    i_clk, i_reset,
    i_pipe_stall,
    i_new_pc, i_pc,

    // Buffer
    o_buf_pc, o_buf_inst
);

    input wire i_clk, i_reset; // Sys CLK, Reset
    input wire i_pipe_stall; // Stall

// PC Override stuff
    input wire i_new_pc;
    input wire [31:0] i_pc;

// Buffer
    output reg [31:0] o_buf_pc, o_buf_inst;
    initial begin
        o_buf_pc = 0;
        o_buf_inst = 0;
    end

// Internal PC
    reg [31:0] current_pc;
    initial current_pc = 0;

    wire [31:0] next_pc = i_new_pc ? i_pc : (current_pc + 4);

    always @(posedge i_clk) begin
        if (i_reset) begin
            current_state <= IDLE;
            current_pc <= 0;

            o_buf_pc <= 0;
            o_buf_inst <= 0;
        end
        else if (!i_pipe_stall) begin

            current_pc <= next_pc; // PC Increment
            o_buf_pc <= current_pc;
            o_buf_inst <= i_wb_data;

            // ADDI r1, r0, 1  :  0d 10 00 01
            // ADD r1, r1, r1  :  08 11 10 00
            case (current_pc)
                0: o_buf_inst <= 32'h0d100001;
                1,
                2,
                3,
                4: o_buf_inst <= 32'h08111000;
                default: o_buf_inst <= 0;
            endcase

        end
    end

endmodule: tl45_nofetch

`timescale 1ns / 1ps

module fifo(
    input clk,rst,wr,rd,
    input [7:0] din,
    output reg [7:0] dout,
    output full,empty
    );
    
    reg [3:0] wptr = 0, rptr = 0;
    reg [4:0] counter = 0;
    reg [7:0] mem [15:0] ;

    always @(posedge clk) begin
        if(rst == 1'b1) begin
            dout <= 8'd0;
            wptr <= 4'd0;
            rptr <= 4'd0;
            counter <= 5'd0;
        end
            else if (wr && !full) begin
                    mem[wptr] <= din;
                    wptr <= wptr + 1;
                    counter <= counter + 1;
                 end
                    else if (rd && !empty) begin
                            dout <= mem[rptr];
                            rptr <= rptr + 1;
                            counter <= counter - 1;
                         end
    end

    assign empty = (counter == 1'b0) ? 1'b1 : 1'b0;
    assign full = (counter == 5'd16) ? 1'b1 : 1'b0;

endmodule

interface fifo_if(
    logic clk,rst,wr,rd,
    logic [7:0] din,
    logic [7:0] dout,
    logic full,empty
);

endinterface



`timescale 1ns / 1ps

module d_ff ( d_ff_if vif );

    always@(posedge vif.clk) 
        begin
            if(vif.rst == 1'b1)
                vif.dout <= 1'b0;
            else
                vif.dout <= vif.din;
        end

endmodule

interface d_ff_if(
    input logic clk,
    input logic rst,
    input logic din,
    output logic dout
);

endinterface

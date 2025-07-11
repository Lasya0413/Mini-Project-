`timescale 1ns / 1ps
`include "usb_rtl.sv"
module usb_tb;

// Parameters
localparam CLK_PERIOD = 20.833; // 48 MHz (USB Full Speed)

// Testbench Signals
reg clk;
reg reset;
reg [1:0] pkt_type;
reg [6:0] addr;
reg [3:0] endp;
reg [7:0] data_in;
reg data_valid;
reg [15:0]frame_num;
wire usb_dp;
wire usb_dm;

wire tx_enable;
wire pkt_complete;

// Device Under Test
usb_packet_generator dut (
    .clk(clk),
    .reset(reset),
    .pkt_type(pkt_type),
    .addr(addr),
    .endp(endp),
    .data_in(data_in),
    .data_valid(data_valid),
    .usb_dp(usb_dp),
    .usb_dm(usb_dm),
    .tx_enable(tx_enable),
    .pkt_complete(pkt_complete)
);

// Clock generation
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end


initial begin
    reset = 1'b1;
   // pkt_type = 2'b00;
    addr = 7'h0;
    endp = 4'h0;
    data_in = 8'h00;
    data_valid = 1'b0;
    pkt_type=2'b00;
   
    dut.frame_num=1'b0;
    dut.pid=4'b0;
    dut.token=11'b0;
    
    // Reset
    #100;
    reset = 1'b0;
    #10;
    
    // Test OUT packet
    $display("\nTesting OUT packet...");
    pkt_type = 2'b00; // OUT
    addr = 7'hA;      // Address 0xA
    endp = 4'h1;      // Endpoint 1
    wait(pkt_complete);

    #20;
    $display("Testing IN pcaket...");
    pkt_type=2'b01;
    addr=7'hB;
    endp=4'h2;
    wait(pkt_complete);
    #810;
    
    addr=7'h0;
    endp=4'h0;
    $display("Testing SOF pcaket...");
    pkt_type=2'b10;
    dut.frame_num=$urandom;
    
    wait(pkt_complete);
    #780; 
    $display("Testing DATA PACKET...");
    pkt_type=2'b11;
    data_valid=1'b1;
    data_in=8'hAA;
    @(posedge clk)
    data_in=8'hBB;
    @(posedge clk);
    data_in=8'hCC;
    
    @(posedge clk)
   // data_valid=1'b0;
    wait(pkt_complete);
    
    


    #1000;
    $finish;
end
endmodule




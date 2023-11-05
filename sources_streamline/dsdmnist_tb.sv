`timescale 10ps/10ps
module dsdmnist_tb;

reg             CLK = 1'b1;
reg             RST_n = 1'b1;
reg             STARTSW = 1'b0;

//generate clock
always #1 CLK = ~CLK;

//reset
initial begin
    #30  RST_n <= 1'b0;
    #200 RST_n <= 1'b1;

    #300 STARTSW <= 1'b1;
    #60  STARTSW <= 1'b0;

    #16000  RST_n <= 1'b0;
    #200 RST_n <= 1'b1;
    #300 STARTSW <= 1'b1;
    #60  STARTSW <= 1'b0;
end

wire    [7:0]   din[4];
assign  din[0] = 8'h71;
assign  din[1] = 8'h4E;
assign  din[2] = 8'h58;
assign  din[3] = 8'h4C;


dsdmnist #(
    .IMGNUM (10), 
    .ROMPATH("C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_streamline_fpga/dsd_mlp.srcs/sources_streamline/"),
    .ROMHEX ("C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_streamline_fpga/dsd_mlp.srcs/sources_streamline/imgset4_v2.txt")
) dut (
    .i_CLK                      (CLK                        ),
    .i_RST_n                    (RST_n                      ),

    .i_STARTSW                  (STARTSW                    ),
    .o_ARMINT                   (                           ),
    .o_DONELED                  (                           ),

    .o_RESULTBUF_EN             (                           ),
    .o_RESULTBUF_WE             (                           ),
    .o_RESULTBUF_DATA           (                           ),
    .o_RESULTBUF_ADDR           (                           )
);


endmodule
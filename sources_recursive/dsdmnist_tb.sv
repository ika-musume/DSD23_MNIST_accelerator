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

    #30000 STARTSW <= 1'b1;
    #60  STARTSW <= 1'b0;

    
end

dsdmnist #(
    .IMGNUM (10), 
    .ROMPATH("C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_recursive_fpga/dsd_mlp.srcs/sources_recursive/"),
    .ROMHEX ("C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_recursive_fpga/dsd_mlp.srcs/sources_recursive/imgset_v3.txt")
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
`timescale 10ps/10ps
module dsdmnist_tb;

reg             CLK = 1'b1;
reg             RST_n = 1'b1;
reg             STARTSW = 1'b0;

//generate clock
always #1 CLK = ~CLK;

reg signed [7:0]   k=~(8'sd78) + 8'sd1;
string     disassembly = "";
string      data="";

//reset
initial begin
    disassembly = {disassembly, "Hello "};
    disassembly = {disassembly, "World!!\n"};
    $display(disassembly);
    disassembly = "";
    disassembly = "byebye";
    $sformat(data, "%d", k);
    disassembly = {disassembly, data};
    $display(disassembly);

    #30  RST_n <= 1'b0;
    #200 RST_n <= 1'b1;

    #300 STARTSW <= 1'b1;
    #60  STARTSW <= 1'b0;

    #30000 STARTSW <= 1'b1;
    #60  STARTSW <= 1'b0;

    
end

dsdmnist dut (
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
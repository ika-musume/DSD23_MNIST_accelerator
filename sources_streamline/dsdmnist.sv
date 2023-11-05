module dsdmnist #(
    parameter IMGNUM = 10,
    parameter ROMPATH = "",
    parameter ROMHEX  = ""
) (
    input   wire                i_CLK,
    input   wire                i_RST_n,

    input   wire                i_STARTSW,

    output  wire                o_ARMINT,
    output  wire                o_DONELED,
    
    output  wire                o_RESULTBUF_EN,
    output  wire                o_RESULTBUF_WE,
    output  wire    [31:0]      o_RESULTBUF_DATA,
    output  wire    [$clog2(IMGNUM*10)-1:0] o_RESULTBUF_ADDR
);



///////////////////////////////////////////////////////////
//////  PARAMETERS
////

//address width
localparam  IAW = $clog2(IMGNUM * 196); //input image ROM address width
localparam  OAW = $clog2(IMGNUM * 10); //output buffer address width



///////////////////////////////////////////////////////////
//////  IMAGE LOADER
////

wire                imgload_start;
wire                layer1_start;
wire                layer1sr_shift;
wire signed [7:0]   layer1sr_din[0:3];
dsdmnist_imgloader #(.IAW(IAW), .ROMHEX(ROMHEX)) u_imgloader (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (~i_RST_n                   ),

    .i_START                    (imgload_start              ),
    .o_DONE                     (layer1_start               ),

    .o_DOUT                     (layer1sr_din               ),
    .o_SHIFT                    (layer1sr_shift             )
);



///////////////////////////////////////////////////////////
//////  LOOP COUNTER
////

reg     [3:0]   img_done;
reg             startsw_z;
reg     [11:0]  op_start_dly;
assign  imgload_start = op_start_dly[11];
always_ff @(posedge i_CLK) begin
    //posedge detector
    startsw_z <= i_STARTSW;

    //count loop
    if(!i_RST_n) img_done <= 4'd0;
    else begin
        if(layer1_start) img_done <= img_done == 4'd15 ? 4'd0 : img_done + 4'd1;
    end

    //delay chain
    op_start_dly[0] <= (~startsw_z & i_STARTSW) | (layer1_start & (img_done < IMGNUM-1));
    op_start_dly[11:1] <= op_start_dly[10:0];
end



///////////////////////////////////////////////////////////
//////  LAYER 1
////

wire                layer2_start;
wire                layer2sr_shift;
wire signed [7:0]   layer2sr_din;
dsdmnist_layer1 #(.ROMPATH(ROMPATH)) u_layer1 (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (~i_RST_n                   ),

    .i_DIN                      (layer1sr_din               ),
    .i_SHIFT                    (layer1sr_shift             ),

    .i_START                    (layer1_start               ),
    .o_DONE                     (layer2_start               ),

    .o_DOUT                     (layer2sr_din               ),
    .o_SHIFT                    (layer2sr_shift             )
);



///////////////////////////////////////////////////////////
//////  LAYER 2
////

wire                layer2_done;
wire                layer3acc_en;
wire signed [7:0]   layer3acc_din;
dsdmnist_layer2 #(.ROMPATH(ROMPATH)) u_layer2 (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (~i_RST_n                   ),

    .i_DIN                      (layer2sr_din               ),
    .i_SHIFT                    (layer2sr_shift             ),

    .i_START                    (layer2_start               ),
    .o_DONE                     (layer2_done                ),

    .o_DOUT                     (layer3acc_din              ),
    .o_VALID                    (layer3acc_en               )
);



///////////////////////////////////////////////////////////
//////  LAYER 3
////

wire signed [31:0]  layer3_dout[0:9];
dsdmnist_layer3 #(.ROMPATH(ROMPATH)) u_layer3 (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (~i_RST_n                   ),

    .i_DIN                      (layer3acc_din              ),
    .i_ACC_EN                   (layer3acc_en               ),

    .i_START                    (layer2_start               ),

    .o_DOUT                     (layer3_dout                )
);



///////////////////////////////////////////////////////////
//////  RESULT BUFFER CONTROL
////

dsdmnist_bufwrfe #(.IMGNUM(IMGNUM), .OAW(OAW)) u_bufwrfe (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (~i_RST_n                   ),

    .i_START                    (layer2_done                ),

    .i_DIN                      (layer3_dout                ),

    .o_DONELED                  (o_DONELED                  ),
    .o_ARMINT                   (o_ARMINT                   ),

    .o_RESULTBUF_EN             (o_RESULTBUF_EN             ),
    .o_RESULTBUF_WE             (o_RESULTBUF_WE             ),
    .o_RESULTBUF_DATA           (o_RESULTBUF_DATA           ),
    .o_RESULTBUF_ADDR           (o_RESULTBUF_ADDR           )
);

endmodule
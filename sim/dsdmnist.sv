module dsdmnist #(
    parameter IMGNUM = 10,
    parameter ROMPATH = "C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_streamline_fpga/dsd_mlp.srcs/sources_streamline/",
    parameter ROMHEX  = "C:/Users/kiki1/Desktop/assignments2/DSD_termprj/dsdmnist_streamline_fpga/dsd_mlp.srcs/sources_streamline/imgset4.txt"
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
localparam  IAW = $clog2(IMGNUM * 49); //input image ROM address width
localparam  OAW = $clog2(IMGNUM * 10); //output buffer address width

//coefficients
localparam  signed [32:0] l1 = 33'h0_00A3_E3B6; //0.0025007552467286586761474609375, layer 1
localparam  signed [32:0] l2 = 33'h0_0230_FB0F; //0.00855988613329827785491943359375, layer 2



///////////////////////////////////////////////////////////
//////  INTERCONNECTS
////

//image rom
wire    [IAW-1:0]   imgrom_addr;
wire                imgrom_rst;
wire                imgrom_hold;
wire    [4:0]       imgrom_data_offset;
wire                imgrom_data_offset_we;

//shift register
wire                sr_byte_we;
wire    [3:0]       sr_byte_addr;
wire                sr_word_rst;
wire                sr_word_we;
wire    [15:0]      sr_word_mask;
wire                sr_chain_rst;
wire                sr_chain_shift;

//weight rom
wire    [9:0]       weightrom_pa_addr, weightrom_pb_addr;
wire                weightrom_pb_we;

//accumulator
wire                acc_rst, acc_en;

//postcalc
wire                accval_ld;
wire                coeff_sel;


///////////////////////////////////////////////////////////
//////  SEQUENCER
////

dsdmnist_sequencer #(.IAW(IAW), .OAW(OAW), .IMGNUM(IMGNUM)) u_sequencer_main (
    .i_CLK                      (i_CLK                      ),
    .i_RST_n                    (i_RST_n                    ),

    .i_STARTSW                  (i_STARTSW                  ),
    .o_ARMINT                   (o_ARMINT                   ),
    .o_DONELED                  (o_DONELED                  ),

    .o_IMGROM_ADDR              (imgrom_addr                ),
    .o_IMGROM_RST               (imgrom_rst                 ),
    .o_IMGROM_HOLD              (imgrom_hold                ),
    .o_IMGROM_DATA_OFFSET       (imgrom_data_offset         ),
    .o_IMGROM_DATA_OFFSET_WE    (imgrom_data_offset_we      ),

    .o_WEIGHTROM_PA_ADDR        (weightrom_pa_addr          ),
    .o_WEIGHTROM_PB_ADDR        (weightrom_pb_addr          ),
    .o_WEIGHTROM_PB_WE          (weightrom_pb_we            ), 

    .o_SR_BYTE_ADDR             (sr_byte_addr               ),
    .o_SR_BYTE_WE               (sr_byte_we                 ),
    .o_SR_WORD_RST              (sr_word_rst                ),
    .o_SR_WORD_WE               (sr_word_we                 ),
    .o_SR_WORD_MASK             (sr_word_mask               ),
    .o_SR_CHAIN_RST             (sr_chain_rst               ),
    .o_SR_CHAIN_SHIFT           (sr_chain_shift             ),

    .o_ACC_RST                  (acc_rst                    ),
    .o_ACC_EN                   (acc_en                     ),

    .o_ACCVAL_LD                (accval_ld                  ),
    .o_COEFF_SEL                (coeff_sel                  ),

    .o_RESULTBUF_EN             (o_RESULTBUF_EN             ),
    .o_RESULTBUF_WE             (o_RESULTBUF_WE             ),
    .o_RESULTBUF_ADDR           (o_RESULTBUF_ADDR           )
);




///////////////////////////////////////////////////////////
//////  IMAGE ROM
////

wire    [7:0]   imgrom_data[0:15];
dsdaccel_imgrom #(.IAW(IAW), .ROMHEX(ROMHEX)) u_imgrom_main (
    .i_CLK                      (i_CLK                      ),
    .i_RST                      (imgrom_rst                 ),

    .i_ADDR                     (imgrom_addr                ),
    .o_DOUT                     (imgrom_data                ),

    .i_HOLD                     (imgrom_hold                ),
    .i_DATA_OFFSET              (imgrom_data_offset         ),
    .i_DATA_OFFSET_WE           (imgrom_data_offset_we      )
);

//quantize image data, divide by 8 
//wire    [7:0]   imgrom_data_quantized[0:15] = imgrom_data;

int     i;
reg     [7:0]   imgrom_data_quantized[0:15];
always_comb begin
    for(i=0; i<16; i=i+1) begin
        /*  WARNING!! THERE'S A BUG IN THE C REFERENCE CODE!! */
        //imgrom_data_quantized[i] = imgrom_data[i][2] ? (imgrom_data[i] >> 3) + 8'd1 : (imgrom_data[i] >> 3);
        imgrom_data_quantized[i] = imgrom_data[i] >> 3; //DO NOT ROUND
    end
end




///////////////////////////////////////////////////////////
//////  SHIFT REGISTER
////

wire    [7:0]   postcalc_result;
wire    [7:0]   sr_out[0:261];
dsdaccel_sr u_sr_main (
    .i_CLK                      (i_CLK                      ),

    .i_BYTE_WE                  (sr_byte_we                 ),
    .i_BYTE_ADDR                (sr_byte_addr               ),
    .i_BYTE_DIN                 (postcalc_result            ),
    .i_WORD_RST                 (sr_word_rst                ),
    .i_WORD_WE                  (sr_word_we                 ),
    .i_WORD_MASK                (sr_word_mask               ),
    .i_WORD_DIN                 (imgrom_data_quantized      ),

    .i_CHAIN_RST                (sr_chain_rst               ),
    .i_CHAIN_SHIFT              (sr_chain_shift             ),

    .o_OUT                      (sr_out                     )
);



///////////////////////////////////////////////////////////
//////  WEIGHT ROM/BUFFER
////

wire    [7:0]   weightrom_opset0[0:261];
wire    [7:0]   weightrom_opset1[0:261];
dsdaccel_weightrom #(.ROMPATH(ROMPATH)) u_weightrom_main (
    .i_CLK                      (i_CLK                      ),

    .i_PA_ADDR                  (weightrom_pa_addr          ),
    .i_PA_DIN                   ('{262{8'h00}}              ),
    .o_PA_DOUT                  (weightrom_opset0           ),
    .i_PA_WE                    (1'b0                       ),

    .i_PB_ADDR                  (weightrom_pb_addr          ),
    .i_PB_DIN                   (sr_out                     ),
    .o_PB_DOUT                  (weightrom_opset1           ),
    .i_PB_WE                    (weightrom_pb_we            )
);

//Modelsim crashes when I try to cast unsigned 2D array to signed 2D array
//like this: $signed() - Verilog 2001, signed'() - Systemverilog -- Why?????
int     j;
reg signed  [7:0]   weightrom_opset0_signed[0:261];
reg signed  [7:0]   weightrom_opset1_signed[0:261];
always_comb begin
    for(j=0; j<262; j=j+1) begin
        weightrom_opset0_signed[j] = weightrom_opset0[j];
        weightrom_opset1_signed[j] = weightrom_opset1[j];
    end
end




///////////////////////////////////////////////////////////
//////  OPERATOR
////

wire signed [31:0]  acc_value;
assign  o_RESULTBUF_DATA = acc_value;
dsdmnist_operator #(.NUM_OF_DSP(218)) u_operator_main (
    .i_CLK                      (i_CLK                      ),

    .i_OPSET0                   (weightrom_opset0_signed    ),
    .i_OPSET1                   (weightrom_opset1_signed    ),

    .i_ACC_RST                  (acc_rst                    ),
    .i_ACC_EN                   (acc_en                     ),
    .o_ACC_OUT                  (acc_value                  )
);



///////////////////////////////////////////////////////////
//////  POST CALCULATION(QUANTIZER/DEQUANTIZER)
////

dsdmnist_postcalc u_postcalc_main (
    .i_CLK                      (i_CLK                      ),

    .i_ACCVAL_LD                (accval_ld                  ),
    .i_ACCVAL                   (acc_value[24:0]            ),
    .i_CONST                    (coeff_sel ? l2 : l1        ),

    .o_RESULT                   (postcalc_result            )
);

endmodule
module dsdmnist_operator #(parameter NUM_OF_DSP = 218) (
    input   wire                i_CLK,

    //operands
    input   wire signed [7:0]   i_OPSET0[0:261],
    input   wire signed [7:0]   i_OPSET1[0:261],

    //accumulator
    input   wire                i_ACC_RST, //reset accumulator
    input   wire                i_ACC_EN, //accumulator load enable
    output  wire signed [31:0]  o_ACC_OUT
);

/*
    Zynq-7020 FPGA has 220 DSP48E1 slices, and we'll use 2 slices for
    the single 24-bit * 32-bit multiplication for quantization/
    dequantization. The remaining 218 slices will be used for matrix
    multiplcation. This accelerator performs 262 multiplications in one 
    clock, so the logic for 44 slices must be implemented as a LUT. 
    
    Fortunately, the multiplication load is not heavy. Vivado reported
    that the replacement will consume 138 LUTs and 49 DFFs. If we don't
    use the compiler directive, Vivado will blindly synthesize this
    module as a LUT mess, so we need to change the parameter.

    8*8 signed곱셈은 LUT으로 합성하는데 대략 12비트 넘어갈즈음 해서는 dsp로
    바뀌는듯... 8*8 signed 곱셈기 여러개 집어넣어놓고 합성하면 어떨지 모르겠는데
    일단 하나만 합성했을때는 저리나왔음
*/


int     i;
reg signed [32:0] refval;
wire signed [7:0] opset0_261 = i_OPSET0[261];
wire signed [7:0] opset1_261 = i_OPSET1[261];
always @(posedge i_CLK) begin
    refval = 33'sd0;
    for(i=0; i<262; i=i+1) begin
        refval = refval + (i_OPSET0[i] * i_OPSET1[i]);
    end
end

///////////////////////////////////////////////////////////
//////  CYC0, CYC1: MUL-ADD STAGE
////

wire signed [16:0]  cyc1_muladd[0:130]; //cycle0 = mul, cycle1 = add
genvar m;
generate
for(m=0; m<131; m=m+1) begin : MULADD
    wire signed [7:0]   opset0[0:1] = {i_OPSET0[261 - m*2 - 1], i_OPSET0[261 - m*2]};
    wire signed [7:0]   opset1[0:1] = {i_OPSET1[261 - m*2 - 1], i_OPSET1[261 - m*2]};

    if(m < NUM_OF_DSP/2) begin
        dsdmnist_4op_muladd #(.USEDSP("yes")) muladd_dsp (
            .i_CLK(i_CLK),
            .i_OPSET0(opset0),
            .i_OPSET1(opset1),
            .o_RESULT(cyc1_muladd[m])
        );
    end
    else begin
        dsdmnist_4op_muladd #(.USEDSP("no")) muladd_lut (
            .i_CLK(i_CLK),
            .i_OPSET0(opset0),
            .i_OPSET1(opset1),
            .o_RESULT(cyc1_muladd[m])
        );
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC2: ADD STAGE 1 / 131->44
////

wire signed [18:0]  cyc2_add1[0:43];
generate
for(m=0; m<44; m=m+1) begin : ADD1
    if(m < 43) begin
        dsdmnist_3op_add #(.OPW(17)) u_add0 (
            .i_CLK(i_CLK),
            .i_OP0(cyc1_muladd[m*3 + 0]), .i_OP1(cyc1_muladd[m*3 + 1]), .i_OP2(cyc1_muladd[m*3 + 2]),
            .o_RESULT(cyc2_add1[m])
        );
    end
    else begin
        dsdmnist_3op_add #(.OPW(17)) u_add0 (
            .i_CLK(i_CLK),
            .i_OP0(cyc1_muladd[129]), .i_OP1(cyc1_muladd[130]), .i_OP2(17'sd0),
            .o_RESULT(cyc2_add1[m])
        );
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC3: ADD STAGE 2 / 44->15
////

wire signed [20:0]  cyc3_add2[0:14];
generate
for(m=0; m<15; m=m+1) begin : ADD2
    if(m < 14) begin
        dsdmnist_3op_add #(.OPW(19)) u_add2 (
            .i_CLK(i_CLK),
            .i_OP0(cyc2_add1[m*3 + 0]), .i_OP1(cyc2_add1[m*3 + 1]), .i_OP2(cyc2_add1[m*3 + 2]),
            .o_RESULT(cyc3_add2[m])
        );
    end
    else begin
        dsdmnist_3op_add #(.OPW(19)) u_add2 (
            .i_CLK(i_CLK),
            .i_OP0(cyc2_add1[42]), .i_OP1(cyc2_add1[43]), .i_OP2(19'sd0),
            .o_RESULT(cyc3_add2[m])
        );
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC4: ADD STAGE 3 / 15->5
////

wire signed [22:0]  cyc4_add3[0:4];
generate
for(m=0; m<5; m=m+1) begin : ADD3
    dsdmnist_3op_add #(.OPW(21)) u_add3 (
        .i_CLK(i_CLK),
        .i_OP0(cyc3_add2[m*3 + 0]), .i_OP1(cyc3_add2[m*3 + 1]), .i_OP2(cyc3_add2[m*3 + 2]),
        .o_RESULT(cyc4_add3[m])
    );
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC5: ADD STAGE 4 / 5->2
////

wire signed [24:0]  cyc5_add4[0:1];
dsdmnist_3op_add #(.OPW(23)) u_add4a (
    .i_CLK(i_CLK),
    .i_OP0(cyc4_add3[0]), .i_OP1(cyc4_add3[1]), .i_OP2(cyc4_add3[2]),
    .o_RESULT(cyc5_add4[0])
);
dsdmnist_3op_add #(.OPW(23)) u_add4b (
    .i_CLK(i_CLK),
    .i_OP0(cyc4_add3[3]), .i_OP1(cyc4_add3[4]), .i_OP2(23'sd0),
    .o_RESULT(cyc5_add4[1])
);



///////////////////////////////////////////////////////////
//////  CYC6: ADD-ACC STAGE
////

dsdmnist_3op_acc #(.OPW(25)) u_addacc (
    .i_CLK(i_CLK),
    .i_RST(i_ACC_RST), .i_EN(i_ACC_EN),
    .i_OP0(cyc5_add4[0]), .i_OP1(cyc5_add4[1]),
    .o_ACC(o_ACC_OUT)
);

endmodule



module dsdmnist_4op_muladd #(parameter USEDSP = "no") (
    input   wire                i_CLK,

    //operands
    input   wire signed [7:0]   i_OPSET0[0:1],
    input   wire signed [7:0]   i_OPSET1[0:1],

    //output
    output  wire signed [16:0]  o_RESULT
);

(* use_dsp = USEDSP *) reg signed  [15:0]  mul0, mul1;
(* use_dsp = USEDSP *) reg signed  [16:0]  add;

always_ff @(posedge i_CLK) begin
    mul0 <= i_OPSET0[0] * i_OPSET1[0];
    mul1 <= i_OPSET0[1] * i_OPSET1[1];

    add <= mul0 + mul1;
end

assign  o_RESULT = add;

endmodule


module dsdmnist_3op_add #(parameter OPW = 8) (
    input   wire                    i_CLK,

    input   wire signed [OPW-1:0]   i_OP0, i_OP1, i_OP2,
    output  reg signed  [OPW+1:0]   o_RESULT
);

(* use_dsp = "no" *) reg signed  [OPW+1:0] add;

//Artix-7's 6-input LUT can handle 3 op addition fluently
always_ff @(posedge i_CLK) begin
    add <= i_OP0 + i_OP1 + i_OP2;
end

assign  o_RESULT = add;

endmodule


module dsdmnist_3op_acc #(parameter OPW = 8) (
    input   wire                    i_CLK,

    input   wire                    i_RST, //reset accumulator
    input   wire                    i_EN, //accumulator load enable
    
    input   wire signed [OPW-1:0]   i_OP0, i_OP1,
    output  wire signed [31:0]      o_ACC
);

(* use_dsp = "no" *) reg signed  [32:0]  acc;

always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        acc <= 32'sd0;
    end
    else begin
        if(i_EN) acc <= i_OP0 + i_OP1 + acc;
        else acc <= i_OP0 + i_OP1;
    end
end

assign  o_ACC = acc;

endmodule
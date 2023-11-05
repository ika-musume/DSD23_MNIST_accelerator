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


module dsdmnist_2op_mulacc #(parameter USEDSP = "no") (
    input   wire                i_CLK,

    //operands
    input   wire signed [7:0]   i_OP0,
    input   wire signed [7:0]   i_OP1,

    //control
    input   wire                i_RST,
    input   wire                i_ACC_EN,

    //output
    output  wire signed [31:0]  o_ACC
);

(* use_dsp = USEDSP *) reg signed  [15:0]  mul;
(* use_dsp = USEDSP *) reg signed  [31:0]  acc;

always_ff @(posedge i_CLK) begin
    mul <= i_OP0 * i_OP1;

    if(i_RST) begin
        acc <= 32'sd0;
    end
    else begin
        if(i_ACC_EN) acc <= mul + acc;
    end
end

assign  o_ACC = acc;

endmodule
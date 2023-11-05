module dsdmnist_postcalc (
    input   wire                i_CLK,

    input   wire                i_ACCVAL_LD,
    input   wire signed [24:0]  i_ACCVAL,
    input   wire signed [32:0]  i_CONST,

    output  wire        [7:0]   o_RESULT
);

/*
    BIT WIDTH
    int8 = -128 - 127
    int8 * int8 = -16256 - 16384 : int16
    -16256 * 784 = -12744704 : sign(1) + int(24), 1100 0010 0111 1000 0000 0000(magnitude)
     16384 * 784 =  12845056 : sign(1) + int(24), 1100 0100 0000 0000 0000 0000
    get 25bit signed integer, multiply by Q1.32 constant
    *Vivado uses 2 DSPs up to 24bit * 35bit multiplication*

    LAYER 1 OUTPUT
    fc1_scale = 0.0312818368371458
    w1_scale  = 0.0017583206588146732
    fc2_scale = 0.02199475500596525

    wolfram alpha says:
    (fc1_scale*w1_scale)/fc2_scale = 0.0025007552910457827566627130951619034042018406532868845341982855 = k1
    k1/(2^-32) = 10740662.1903405985785870788463513109461579745888704439801098 = 10740662
    k1 = +0000_0000_00A3_E3B6 = 0.0025007552467286586761474609375


    LAYER 2 OUTPUT
    fc2_scale = 0.02199475500596525
    w2_scale  = 0.0030979273365993125
    fc3_scale = 0.00796017049452235

    wolfram alpha says:
    (fc2_scale*w2_scale)/fc3_scale = 0.0085598861031522355913756360090181174617802584900060410663039932 = k2
    k2/(2^-32) = 36764430.8705237343742455763099327755698327401530022892222086 = 36764431
    k2 = +0000_0000_0230_FB0F = 0.00855988613329827785491943359375
*/

//relu
reg signed  [24:0]  relu;
always_ff @(posedge i_CLK) begin
   if(i_ACCVAL_LD) relu <= i_ACCVAL[24] ? 25'sd0 : i_ACCVAL; 
end

//multiplication
(* use_dsp = "yes" *) reg signed    [56:0]  mul; //57~32 = integer, 31~0 = fractional
reg signed    [56:0]  mul_z;
real    mul_fp;
always_ff @(posedge i_CLK) begin
    mul <= relu * i_CONST;
    mul_z <= mul;
end
//always_comb mul_fp <= mul * 0.000000000232830643654;


//round
wire signed [24:0]  round;
wire signed  [7:0]   clip;
assign  round = mul_z[31] ? mul_z[56:32] + 25'sd1 : mul_z[56:32]; //round
assign  clip = (|{round[24:7]}) ? 8'sd127 : round[7:0]; //clip

assign  o_RESULT = unsigned'(clip);

endmodule
module dsdmnist_layer1 #(parameter ROMPATH = "") (
    input   wire                i_CLK,
    input   wire                i_RST,

    //input shift register control
    input   wire signed [7:0]   i_DIN[0:3],
    input   wire                i_SHIFT,

    //start control
    input   wire                i_START,
    output  wire                o_DONE,

    //output shift register control
    output  wire signed [7:0]   o_DOUT,
    output  wire                o_SHIFT
);



///////////////////////////////////////////////////////////
//////  SHIFT REGISTER SELECT
////

reg             srbanksel; //SR to be read
reg             start_z;
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        srbanksel <= 1'b0;
        start_z <= 1'b0;
    end
    else begin
        start_z <= i_START;
        
        if(~start_z & i_START) begin //posedge detect
            srbanksel <= ~srbanksel;
        end
    end
end



///////////////////////////////////////////////////////////
//////  SHIFT REGISTER
////

//write
int     i;
reg signed  [7:0]   sr0[196][4]; //196 blocks of 8bit*4
reg signed  [7:0]   sr1[196][4];
always_ff @(posedge i_CLK) begin
    if(i_SHIFT) begin
        if(srbanksel == 1'b1) begin //read: 1, write: 0
            for(i=0; i<196; i=i+1) begin
                if(i == 0)  sr0[195-i] <= i_DIN;
                else        sr0[195-i] <= sr0[195-i+1];
            end
        end
        else begin //read: 0, write: 1
            for(i=0; i<196; i=i+1) begin
                if(i == 0)  sr1[195-i] <= i_DIN;
                else        sr1[195-i] <= sr1[195-i+1];
            end
        end
    end
end

//read mux
wire            srwordsel;
reg signed  [7:0]   srdata[0:391];
int     j;
always_comb begin
    if(srbanksel == 1'b0) begin
        if(srwordsel == 1'b1)   for(j=0; j<98; j=j+1) srdata[j*4+:4] = sr0[j];    //reverse hi and lo since bram outputs its contents 1 cycle later
        else                    for(j=0; j<98; j=j+1) srdata[j*4+:4] = sr0[j+98];
    end
    else begin
        if(srwordsel == 1'b1)   for(j=0; j<98; j=j+1) srdata[j*4+:4] = sr1[j];
        else                    for(j=0; j<98; j=j+1) srdata[j*4+:4] = sr1[j+98];
    end
end



///////////////////////////////////////////////////////////
//////  CYCLE COUNTER / SEQUENCER
////

reg             run;
reg     [8:0]   cycle_cntr;
assign  srwordsel = cycle_cntr[0];
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        run <= 1'b0;
        cycle_cntr <= 9'd0;
    end
    else begin
        if(run) begin
            if(cycle_cntr == 9'd511) begin
                run <= 1'b0;
                cycle_cntr <= 9'd0;
            end
            else begin
                cycle_cntr <= cycle_cntr + 9'd1;
            end
        end
        else begin
            if(i_START) run <= 1'b1;
        end
    end
end

//done delay
reg     [11:0]  done_dly;
assign  o_DONE = done_dly[11];

//accumulation enable/accumulator value load delay
reg     [11:0]  acc_en_dly;
wire            acc_en = acc_en_dly[7];
wire            accval_ld = acc_en_dly[8];
assign  o_SHIFT = acc_en_dly[11];

always_ff @(posedge i_CLK) begin
    done_dly[0] <= cycle_cntr == 9'd511;
    done_dly[11:1] <= done_dly[10:0];

    acc_en_dly[0] <= cycle_cntr[0];
    acc_en_dly[11:1] <= acc_en_dly[10:0];
end


///////////////////////////////////////////////////////////
//////  WEIGHT ROM
////

//declare the SPRAM
reg     [392*8-1:0] w1rom_dout;
reg     [392*8-1:0] w1rom[0:511];

always_ff @(posedge i_CLK) begin
    w1rom_dout <= w1rom[cycle_cntr];
end

//rearrange ROM output
reg signed  [7:0]   w1data[0:391];
int     k;
always_comb begin
    for(k=0; k<392; k=k+1) begin
        w1data[k] = signed'(w1rom_dout[k*8+:8]); //unpack port a dout
    end
end

`ifdef DSDMNIST_SIMULATION
//make ROM initializer file
int     m, n;
reg     [392*8-1:0] weightbuf[0:511];
reg     [7:0]       w1buf[0:(784*256)-1];
reg     [392*8-1:0] writebuf;
initial begin
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W1_hex.txt"}, w1buf);

    //initialize weightbuf
    for(m=0; m<512; m=m+1) begin
        weightbuf[m] = 392*8'h0;
    end

    //convert weight 1 buffer
    for(m=0; m<256; m=m+1) begin
        //first chunk
        writebuf = 392*8'h0;
        for(n=0; n<392; n=n+1) begin
            writebuf = writebuf | ({391*8'h0, w1buf[m*784 + n]} << n*8);
        end
        weightbuf[m*2 + 0] = writebuf;

        //second chunk
        writebuf = 392*8'h0;
        for(n=0; n<392; n=n+1) begin
            writebuf = writebuf | ({391*8'h0, w1buf[m*784 + n + 392]} << n*8);
        end
        weightbuf[m*2 + 1] = writebuf;
    end

    //write
    $writememh({ROMPATH, "WEIGHTROM_W1.txt"}, weightbuf);

    //read
    $readmemh({ROMPATH, "WEIGHTROM_W1.txt"}, w1rom);
end
`else
initial begin
    //read
    $readmemh({ROMPATH, "WEIGHTROM_W1.txt"}, w1rom);
end
`endif



///////////////////////////////////////////////////////////
//////  CYC0, CYC1: MUL-ADD STAGE
////

wire signed [16:0]  cyc1_muladd[0:195]; //cycle0 = mul, cycle1 = add
genvar p;
generate
for(p=0; p<196; p=p+1) begin : MULADD
    wire signed [7:0]   opset0[0:1] = {srdata[391 - p*2 - 1], srdata[391 - p*2]};
    wire signed [7:0]   opset1[0:1] = {w1data[391 - p*2 - 1], w1data[391 - p*2]};
    if(p < 108) begin
        dsdmnist_4op_muladd #(.USEDSP("yes")) muladd_dsp (
            .i_CLK(i_CLK),
            .i_OPSET0(opset0),
            .i_OPSET1(opset1),
            .o_RESULT(cyc1_muladd[p])
        );
    end
    else begin
        dsdmnist_4op_muladd #(.USEDSP("no")) muladd_lut (
            .i_CLK(i_CLK),
            .i_OPSET0(opset0),
            .i_OPSET1(opset1),
            .o_RESULT(cyc1_muladd[p])
        );
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC2: ADD STAGE 1 / 196->66
////

wire signed [18:0]  cyc2_add1[0:65];
generate
for(p=0; p<66; p=p+1) begin : ADD1
    if(p < 65) begin
        dsdmnist_3op_add #(.OPW(17)) u_add1 (
            .i_CLK(i_CLK),
            .i_OP0(cyc1_muladd[p*3 + 0]), .i_OP1(cyc1_muladd[p*3 + 1]), .i_OP2(cyc1_muladd[p*3 + 2]),
            .o_RESULT(cyc2_add1[p])
        );
    end
    else begin
        //BYPASS
        reg signed [18:0]   cyc2_add1_65;
        always_ff @(posedge i_CLK) cyc2_add1_65 <= {{2{cyc1_muladd[195][16]}}, cyc1_muladd[195]}; //sign extension
        assign cyc2_add1[65] = cyc2_add1_65;
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC3: ADD STAGE 2 / 66->22
////

wire signed [20:0]  cyc3_add2[0:21];
generate
for(p=0; p<22; p=p+1) begin : ADD2
    dsdmnist_3op_add #(.OPW(19)) u_add2 (
        .i_CLK(i_CLK),
        .i_OP0(cyc2_add1[p*3 + 0]), .i_OP1(cyc2_add1[p*3 + 1]), .i_OP2(cyc2_add1[p*3 + 2]),
        .o_RESULT(cyc3_add2[p])
    );
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC4: ADD STAGE 3 / 22->8
////

wire signed [22:0]  cyc4_add3[0:7];
generate
for(p=0; p<8; p=p+1) begin : ADD3
    if(p < 7) begin
        dsdmnist_3op_add #(.OPW(21)) u_add3 (
            .i_CLK(i_CLK),
            .i_OP0(cyc3_add2[p*3 + 0]), .i_OP1(cyc3_add2[p*3 + 1]), .i_OP2(cyc3_add2[p*3 + 2]),
            .o_RESULT(cyc4_add3[p])
        );
    end
    else begin
        //BYPASS
        reg signed [18:0]   cyc4_add3_7;
        always_ff @(posedge i_CLK) cyc4_add3_7 <= {{2{cyc3_add2[21][20]}}, cyc3_add2[21]};
        assign cyc4_add3[7] = cyc4_add3_7;
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC5: ADD STAGE 4 / 8->3
////

wire signed [24:0]  cyc5_add4[0:2];
dsdmnist_3op_add #(.OPW(23)) u_add4a (
    .i_CLK(i_CLK),
    .i_OP0(cyc4_add3[0]), .i_OP1(cyc4_add3[1]), .i_OP2(cyc4_add3[2]),
    .o_RESULT(cyc5_add4[0])
);
dsdmnist_3op_add #(.OPW(23)) u_add4b (
    .i_CLK(i_CLK),
    .i_OP0(cyc4_add3[3]), .i_OP1(cyc4_add3[4]), .i_OP2(cyc4_add3[5]),
    .o_RESULT(cyc5_add4[1])
);
dsdmnist_3op_add #(.OPW(23)) u_add4c (
    .i_CLK(i_CLK),
    .i_OP0(cyc4_add3[6]), .i_OP1(cyc4_add3[7]), .i_OP2(23'sd0),
    .o_RESULT(cyc5_add4[2])
);



///////////////////////////////////////////////////////////
//////  CYC6: ADD STAGE 5 / 3->1
////

wire signed [26:0]  cyc6_add5;
dsdmnist_3op_add #(.OPW(25)) u_add5 (
    .i_CLK(i_CLK),
    .i_OP0(cyc5_add4[0]), .i_OP1(cyc5_add4[1]), .i_OP2(cyc5_add4[2]),
    .o_RESULT(cyc6_add5)
);



///////////////////////////////////////////////////////////
//////  CYC7: ADD-ACC STAGE
////

wire signed [31:0]  cyc7_acc_out;
dsdmnist_3op_acc #(.OPW(27)) u_addacc (
    .i_CLK(i_CLK),
    .i_RST(i_RST), .i_EN(acc_en),
    .i_OP0(cyc6_add5), .i_OP1(27'sd0),
    .o_ACC(cyc7_acc_out)
);



///////////////////////////////////////////////////////////
//////  CYC8: RELU STAGE
////

//relu
reg signed  [24:0]  relu;
always_ff @(posedge i_CLK) begin
   if(accval_ld) relu <= cyc7_acc_out[24] ? 25'sd0 : cyc7_acc_out[24:0]; 
end

//multiplication
(* use_dsp = "yes" *) reg signed    [56:0]  mul; //57~32 = integer, 31~0 = fractional
reg signed    [56:0]  mul_z;
real    mul_fp;
always_ff @(posedge i_CLK) begin
    mul <= relu * 33'sh0_00A3_E3B6;
    mul_z <= mul;
end
//always_comb mul_fp <= mul * 0.000000000232830643654;

//round
wire signed [24:0]  round;
wire signed  [7:0]   clip;
assign  round = mul_z[31] ? mul_z[56:32] + 25'sd1 : mul_z[56:32]; //round
assign  clip = (|{round[24:7]}) ? 8'sd127 : round[7:0]; //clip

assign  o_DOUT = clip;


endmodule
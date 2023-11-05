module dsdmnist_layer2 #(parameter ROMPATH = "") (
    input   wire                i_CLK,
    input   wire                i_RST,

    //input shift register control
    input   wire signed [7:0]   i_DIN,
    input   wire                i_SHIFT,

    //start control
    input   wire                i_START,
    output  wire                o_DONE,

    //output data control
    output  wire signed [7:0]   o_DOUT,
    output  wire                o_VALID
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
reg signed  [7:0]   sr0[0:255]; //256byte length shift register
reg signed  [7:0]   sr1[0:255];
always_ff @(posedge i_CLK) begin
    if(i_SHIFT) begin
        if(srbanksel == 1'b1) begin //read: 1, write: 0
            for(i=0; i<256; i=i+1) begin
                if(i == 0)  sr0[255-i] <= i_DIN;
                else        sr0[255-i] <= sr0[255-i+1];
            end
        end
        else begin //read: 0, write: 1
            for(i=0; i<256; i=i+1) begin
                if(i == 0)  sr1[255-i] <= i_DIN;
                else        sr1[255-i] <= sr1[255-i+1];
            end
        end
    end
end

//read mux
wire        [1:0]   srwordsel;
reg signed  [7:0]   srdata[0:63];
int     j;
always_comb begin
    if(srbanksel == 1'b0) begin
        case(srwordsel)
            2'd0: for(j=0; j<64; j=j+1) srdata[j] = sr0[j+192];
            2'd1: for(j=0; j<64; j=j+1) srdata[j] = sr0[j    ];
            2'd2: for(j=0; j<64; j=j+1) srdata[j] = sr0[j+64 ];
            2'd3: for(j=0; j<64; j=j+1) srdata[j] = sr0[j+128];
        endcase
    end
    else begin
        case(srwordsel)
            2'd0: for(j=0; j<64; j=j+1) srdata[j] = sr1[j+192];
            2'd1: for(j=0; j<64; j=j+1) srdata[j] = sr1[j    ];
            2'd2: for(j=0; j<64; j=j+1) srdata[j] = sr1[j+64 ];
            2'd3: for(j=0; j<64; j=j+1) srdata[j] = sr1[j+128];
        endcase
    end
end






///////////////////////////////////////////////////////////
//////  CYCLE COUNTER / SEQUENCER
////

reg             run;
reg     [8:0]   cycle_cntr;
assign  srwordsel = cycle_cntr[1:0];
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
reg     [9:0]  done_dly;
assign  o_DONE = done_dly[9];

//accumulation enable/accumulator value load delay
reg     [5:0]   acc_en_dly;
wire            acc_en = acc_en_dly[5];
reg     [9:0]   valid_dly;
wire            accval_ld = valid_dly[6];
assign  o_VALID = valid_dly[9];


always_ff @(posedge i_CLK) begin
    done_dly[0] <= cycle_cntr == 9'd511;
    done_dly[9:1] <= done_dly[8:0];

    acc_en_dly[0] <= ~(cycle_cntr[1:0] == 2'd0);
    acc_en_dly[5:1] <= acc_en_dly[4:0];

    valid_dly[0] <= cycle_cntr[1:0] == 2'd3;
    valid_dly[9:1] <= valid_dly[8:0];
end


///////////////////////////////////////////////////////////
//////  WEIGHT ROM
////

//declare the SPRAM
reg     [64*8-1:0] w2rom_dout;
reg     [64*8-1:0] w2rom[0:511];

always_ff @(posedge i_CLK) begin
    w2rom_dout <= w2rom[cycle_cntr];
end

//rearrange ROM output
reg signed  [7:0]   w2data[0:63];
int     k;
always_comb begin
    for(k=0; k<64; k=k+1) begin
        w2data[k] = signed'(w2rom_dout[k*8+:8]); //unpack port a dout
    end
end

`ifdef DSDMNIST_SIMULATION
//make ROM initializer file
int     m, n;
reg     [64*8-1:0] weightbuf[0:511];
reg     [7:0]       w2buf[0:(256*128)-1];
reg     [64*8-1:0] writebuf;
initial begin
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W2_hex.txt"}, w2buf);

    //initialize weightbuf
    for(m=0; m<512; m=m+1) begin
        weightbuf[m] = 64*8'h0;
    end

    //convert weight 2 buffer
    for(m=0; m<128; m=m+1) begin
        //first chunk
        writebuf = 64*8'h0;
        for(n=0; n<64; n=n+1) begin
            writebuf = writebuf | ({63*8'h0, w2buf[m*256 + n]} << n*8);
        end
        weightbuf[m*4 + 0] = writebuf;

        //second chunk
        writebuf = 64*8'h0;
        for(n=0; n<64; n=n+1) begin
            writebuf = writebuf | ({63*8'h0, w2buf[m*256 + n + 64]} << n*8);
        end
        weightbuf[m*4 + 1] = writebuf;

        //first chunk
        writebuf = 64*8'h0;
        for(n=0; n<64; n=n+1) begin
            writebuf = writebuf | ({63*8'h0, w2buf[m*256 + n + 128]} << n*8);
        end
        weightbuf[m*4 + 2] = writebuf;

        //first chunk
        writebuf = 64*8'h0;
        for(n=0; n<64; n=n+1) begin
            writebuf = writebuf | ({63*8'h0, w2buf[m*256 + n + 192]} << n*8);
        end
        weightbuf[m*4 + 3] = writebuf;
    end

    //write
    $writememh({ROMPATH, "WEIGHTROM_W2.txt"}, weightbuf);

    //read
    $readmemh({ROMPATH, "WEIGHTROM_W2.txt"}, w2rom);
end
`else
initial begin
    //read
    $readmemh({ROMPATH, "WEIGHTROM_W2.txt"}, w2rom);
end
`endif


int     h;
reg signed [32:0] refval;
always @(posedge i_CLK) begin
    refval = 33'sd0;
    for(h=0; h<64; h=h+1) begin
        refval = refval + (w2data[h] * srdata[h]);
    end
end



///////////////////////////////////////////////////////////
//////  CYC0, CYC1: MUL-ADD STAGE
////

wire signed [16:0]  cyc1_muladd[0:31]; //cycle0 = mul, cycle1 = add
genvar p;
generate
for(p=0; p<32; p=p+1) begin : MULADD
    wire signed [7:0]   opset0[0:1] = {srdata[63 - p*2 - 1], srdata[63 - p*2]};
    wire signed [7:0]   opset1[0:1] = {w2data[63 - p*2 - 1], w2data[63 - p*2]};

    dsdmnist_4op_muladd #(.USEDSP("no")) muladd_lut (
        .i_CLK(i_CLK),
        .i_OPSET0(opset0),
        .i_OPSET1(opset1),
        .o_RESULT(cyc1_muladd[p])
    );
end
endgenerate

int     g;
reg signed [32:0] refval2;
always @(posedge i_CLK) begin
    refval2 = 33'sd0;
    for(g=0; g<32; g=g+1) begin
        refval2 = refval2 + cyc1_muladd[g];
    end
end




///////////////////////////////////////////////////////////
//////  CYC2: ADD STAGE 1 / 32->11
////

wire signed [18:0]  cyc2_add1[0:10];
generate
for(p=0; p<11; p=p+1) begin : ADD1
    if(p < 10) begin
        dsdmnist_3op_add #(.OPW(17)) u_add0 (
            .i_CLK(i_CLK),
            .i_OP0(cyc1_muladd[p*3 + 0]), .i_OP1(cyc1_muladd[p*3 + 1]), .i_OP2(cyc1_muladd[p*3 + 2]),
            .o_RESULT(cyc2_add1[p])
        );
    end
    else begin
        dsdmnist_3op_add #(.OPW(17)) u_add0 (
            .i_CLK(i_CLK),
            .i_OP0(cyc1_muladd[30]), .i_OP1(cyc1_muladd[31]), .i_OP2(17'sd0),
            .o_RESULT(cyc2_add1[p])
        );
    end
end
endgenerate



///////////////////////////////////////////////////////////
//////  CYC3: ADD STAGE 2 / 11->4
////

wire signed [20:0]  cyc3_add2[0:3];
dsdmnist_3op_add #(.OPW(19)) u_add2a (
    .i_CLK(i_CLK),
    .i_OP0(cyc2_add1[0]), .i_OP1(cyc2_add1[1]), .i_OP2(cyc2_add1[2]),
    .o_RESULT(cyc3_add2[0])
);
dsdmnist_3op_add #(.OPW(19)) u_add2b (
    .i_CLK(i_CLK),
    .i_OP0(cyc2_add1[3]), .i_OP1(cyc2_add1[4]), .i_OP2(cyc2_add1[5]),
    .o_RESULT(cyc3_add2[1])
);
dsdmnist_3op_add #(.OPW(19)) u_add2c (
    .i_CLK(i_CLK),
    .i_OP0(cyc2_add1[6]), .i_OP1(cyc2_add1[7]), .i_OP2(cyc2_add1[8]),
    .o_RESULT(cyc3_add2[2])
);
dsdmnist_3op_add #(.OPW(19)) u_add2d (
    .i_CLK(i_CLK),
    .i_OP0(cyc2_add1[9]), .i_OP1(cyc2_add1[10]), .i_OP2(19'sd0),
    .o_RESULT(cyc3_add2[3])
);




///////////////////////////////////////////////////////////
//////  CYC4: ADD STAGE 3 / 4->2
////

wire signed [22:0]  cyc4_add3[0:1];
dsdmnist_3op_add #(.OPW(21)) u_add3a (
    .i_CLK(i_CLK),
    .i_OP0(cyc3_add2[0]), .i_OP1(cyc3_add2[1]), .i_OP2(21'sd0),
    .o_RESULT(cyc4_add3[0])
);
dsdmnist_3op_add #(.OPW(21)) u_add3b (
    .i_CLK(i_CLK),
    .i_OP0(cyc3_add2[2]), .i_OP1(cyc3_add2[3]), .i_OP2(21'sd0),
    .o_RESULT(cyc4_add3[1])
);



///////////////////////////////////////////////////////////
//////  CYC5: ADD-ACC STAGE
////

wire signed [31:0]  cyc5_acc_out;
dsdmnist_3op_acc #(.OPW(23)) u_addacc (
    .i_CLK(i_CLK),
    .i_RST(i_RST), .i_EN(acc_en),
    .i_OP0(cyc4_add3[0]), .i_OP1(cyc4_add3[1]),
    .o_ACC(cyc5_acc_out)
);



///////////////////////////////////////////////////////////
//////  CYC6: RELU STAGE
////

//relu
reg signed  [24:0]  relu;
always_ff @(posedge i_CLK) begin
   if(accval_ld) relu <= cyc5_acc_out[24] ? 25'sd0 : cyc5_acc_out[24:0]; 
end

//multiplication
(* use_dsp = "yes" *) reg signed    [56:0]  mul; //57~32 = integer, 31~0 = fractional
reg signed    [56:0]  mul_z;
real    mul_fp;
always_ff @(posedge i_CLK) begin
    mul <= relu * 33'sh0_0230_FB0F;
    mul_z <= mul;
end

//round
wire signed [24:0]  round;
wire signed  [7:0]   clip;
assign  round = mul_z[31] ? mul_z[56:32] + 25'sd1 : mul_z[56:32]; //round
assign  clip = (|{round[24:7]}) ? 8'sd127 : round[7:0]; //clip

assign  o_DOUT = clip;


endmodule
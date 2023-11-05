module dsdmnist_layer3 #(parameter ROMPATH = "") (
    input   wire                i_CLK,
    input   wire                i_RST,

    //input control
    input   wire signed [7:0]   i_DIN,
    input   wire                i_ACC_EN,

    //start control
    input   wire                i_START,

    //output data
    output  wire signed [31:0]  o_DOUT[0:9]
);



///////////////////////////////////////////////////////////
//////  ADDRESS COUNTER
////

reg     [6:0]   w3rom_addr_cntr;
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        w3rom_addr_cntr <= 7'd0;
    end
    else begin
        if(i_START) w3rom_addr_cntr <= 7'd0;
        else begin
            if(i_ACC_EN) w3rom_addr_cntr <= (w3rom_addr_cntr == 7'd127) ? 7'd0 :  w3rom_addr_cntr + 7'd1;
        end
    end
end



///////////////////////////////////////////////////////////
//////  WEIGHT ROM
////

//declare the SPRAM
reg     [10*8-1:0] w3rom_dout;
reg     [10*8-1:0] w3rom[0:127];

always_ff @(posedge i_CLK) begin
    w3rom_dout <= w3rom[w3rom_addr_cntr];
end

//rearrange ROM output
reg signed  [7:0]   w3data[0:9];
int     k;
always_comb begin
    for(k=0; k<10; k=k+1) begin
        w3data[k] = signed'(w3rom_dout[k*8+:8]); //unpack port a dout
    end
end

`ifdef DSDMNIST_SIMULATION
//make ROM initializer file
int     m, n;
reg     [10*8-1:0] weightbuf[0:127];
reg     [7:0]      w3buf[0:(128*10)-1];
reg     [10*8-1:0] writebuf;
initial begin
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W3_hex.txt"}, w3buf);

    //initialize weightbuf
    for(m=0; m<10; m=m+1) begin
        weightbuf[m] = 10*8'h0;
    end

    //convert weight 3 buffer
    for(m=0; m<128; m=m+1) begin
        //first chunk
        writebuf = 10*8'h0;
        for(n=0; n<10; n=n+1) begin
            writebuf = writebuf | ({9*8'h0, w3buf[m + n*128]} << n*8);
        end
        weightbuf[m] = writebuf;
    end

    //write
    $writememh({ROMPATH, "WEIGHTROM_W3.txt"}, weightbuf);

    //read
    $readmemh({ROMPATH, "WEIGHTROM_W3.txt"}, w3rom);
end
`else
initial begin
    //read
    $readmemh({ROMPATH, "WEIGHTROM_W3.txt"}, w3rom);
end
`endif



///////////////////////////////////////////////////////////
//////  OPERATOR
////

reg             acc_en_z;
always_ff @(posedge i_CLK) begin
    acc_en_z <= i_ACC_EN;
end

genvar i;
generate
for(i=0; i<10; i=i+1) begin : MULACC
    dsdmnist_2op_mulacc #(.USEDSP("no")) u_mulacc (
        .i_CLK(i_CLK),
        .i_OP0(w3data[i]), .i_OP1(i_DIN),
        .i_RST(i_START), .i_ACC_EN(acc_en_z),
        .o_ACC(o_DOUT[i])
    );
end
endgenerate






endmodule
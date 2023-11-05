module dsdaccel_weightrom #(parameter ROMPATH = "C:/Users/kiki1/Desktop/assignments2/DSD_termprj/sim/roms/") (
    input   wire            i_CLK,

    input   wire    [9:0]   i_PA_ADDR,
    input   wire    [7:0]   i_PA_DIN[0:261],
    output  reg     [7:0]   o_PA_DOUT[0:261],
    input   wire            i_PA_WE,

    input   wire    [9:0]   i_PB_ADDR,
    input   wire    [7:0]   i_PB_DIN[0:261],
    output  reg     [7:0]   o_PB_DOUT[0:261],
    input   wire            i_PB_WE
);

`define DSDMNIST_SIMULATION

/*
    ADDR(DEC)   8*262 VECTOR
    962     X|------260-------| quantized image0 524-784
    961     |-------262-------| quantized image0 262-523
    960     |-------262-------| quantized image0   0-261
                ...........
    921     |--128---|XXXXXXXXX layer 2 output     0-127
    920     |-----256-------|XX layer 1 output     0-255
                ...........
    896     |--128---|XXXXXXXXX layer 3 weight     0-127
                ...........
    768     |-----256-------|XX layer 2 weight     0-255
                ...........
      2     X|------260-------| layer 1 weight   524-784
      1     |-------262-------| layer 1 weight   262-523
      0     |-------262-------| layer 1 weight     0-261
           MSB               LSB

*/

reg     [262*8-1:0] pa_din, pa_dout;
reg     [262*8-1:0] pb_din, pb_dout;

//pack/unpack the ports
int     p;
always_comb begin
    for(p=0; p<262; p=p+1) begin
        pa_din[p*8+:8] = i_PA_DIN[p]; //pack port a din
        pb_din[p*8+:8] = i_PB_DIN[p]; //pack port b din

        o_PA_DOUT[p] = pa_dout[p*8+:8]; //unpack port a dout
        o_PB_DOUT[p] = pb_dout[p*8+:8]; //unpack port b dout
    end
end

//declare the DPRAM
reg     [262*8-1:0] weightrom[0:1023];

always_ff @(posedge i_CLK) begin
    if(i_PA_WE) weightrom[i_PA_ADDR] <= pa_din;
    else pa_dout <= weightrom[i_PA_ADDR];
end

always_ff @(posedge i_CLK) begin
    if(i_PB_WE) weightrom[i_PB_ADDR] <= pb_din;
    else pb_dout <= weightrom[i_PB_ADDR];
end

/*
    Shitty Vivado incorrectly executes simulation-only code during synthesis
    and often falls into traps. Be sure to define a macro before synthesis
    because the process will take infinitely long. Damn.
*/

`ifdef DSDMNIST_SIMULATION
//make ROM initializer file
int     i, j, k;
reg     [262*8-1:0] weightbuf[0:1023];
reg     [7:0]       w1buf[0:(784*256)-1];
reg     [7:0]       w2buf[0:(256*128)-1];
reg     [7:0]       w3buf[0:(128*10)-1];
reg     [262*8-1:0] writebuf;
initial begin
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W1_hex.txt"}, w1buf);
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W2_hex.txt"}, w2buf);
    if(ROMPATH != "") $readmemh({ROMPATH, "t_quantized_weights_W3_hex.txt"}, w3buf);

    //initialize weightbuf
    for(i=0; i<1024; i=i+1) begin
        weightbuf[i] = 262*8'h0;
    end

    //convert weight 1 buffer
    for(i=0; i<256; i=i+1) begin
        //first chunk
        writebuf = 262*8'h0;
        for(j=0; j<262; j=j+1) begin
            writebuf = writebuf | ({261*8'h0, w1buf[i*784 + j]} << j*8);
        end
        weightbuf[i*3 + 0] = writebuf;

        //second chunk
        writebuf = 262*8'h0;
        for(j=0; j<262; j=j+1) begin
            writebuf = writebuf | ({261*8'h0, w1buf[i*784 + j + 262]} << j*8);
        end
        weightbuf[i*3 + 1] = writebuf;

        //third chunk
        writebuf = 262*8'h0;
        for(j=0; j<260; j=j+1) begin
            writebuf = writebuf | ({261*8'h0, w1buf[i*784 + j + 524]} << j*8);
        end
        weightbuf[i*3 + 2] = writebuf;
    end

    //convert weight 2 buffer
    for(i=0; i<128; i=i+1) begin
        writebuf = 262*8'h0;
        for(j=0; j<256; j=j+1) begin
            writebuf = writebuf | ({261*8'h0, w2buf[i*256 + j]} << (j + 6)*8);
        end
        weightbuf[i + 768] = writebuf;
    end

    //convert weight 3 buffer
    for(i=0; i<10; i=i+1) begin
        writebuf = 262*8'h0;
        for(j=0; j<128; j=j+1) begin
            writebuf = writebuf | ({261*8'h0, w3buf[i*128 + j]} << (j + 134)*8);
        end
        weightbuf[i + 896] = writebuf;
    end

    //write
    $writememh({ROMPATH, "WEIGHTROM.txt"}, weightbuf);

    //read
    $readmemh({ROMPATH, "WEIGHTROM.txt"}, weightrom);
end
`else
initial begin
    //read
    $readmemh({ROMPATH, "WEIGHTROM.txt"}, weightrom);
end
`endif

endmodule
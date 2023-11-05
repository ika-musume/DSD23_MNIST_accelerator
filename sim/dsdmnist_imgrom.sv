module dsdaccel_imgrom #(
    parameter IAW = 0,
    parameter ROMHEX = "C:/Users/kiki1/Desktop/assignments2/DSD_termprj/sim/roms/imgset4.txt"
    ) (
    input   wire                i_CLK,
    input   wire                i_RST,

    //address
    input   wire    [IAW-1:0]   i_ADDR,
    output  reg     [7:0]       o_DOUT[0:15],

    //alignment control
    input   wire                i_HOLD,
    input   wire                i_DATA_OFFSET_WE,
    input   wire    [4:0]       i_DATA_OFFSET
);


///////////////////////////////////////////////////////////
//////  IMAGE ROM
////

reg     [127:0] imgrom_dout;
(* ram_style = "block" *) reg     [127:0] imgrom[0:(2**IAW)-1];
always_ff @(posedge i_CLK) begin
    imgrom_dout <= imgrom[i_ADDR];
end

//outlatch\
reg             hold_z;
reg             addr_parity;
reg     [127:0] imgrom_dout0_z, imgrom_dout1_z;
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        hold_z <= 1'b0;
        addr_parity <= 1'b1;
        imgrom_dout0_z <= 128'd0;
        imgrom_dout1_z <= 128'd0;
    end
    else begin
        hold_z <= i_HOLD;

        if(hold_z) addr_parity <= addr_parity;
        else addr_parity <= ~addr_parity;

        if(addr_parity) imgrom_dout1_z <= imgrom_dout;
        else            imgrom_dout0_z <= imgrom_dout;
    end
end

initial begin
    if(ROMHEX != "") $readmemh(ROMHEX, imgrom);
end



///////////////////////////////////////////////////////////
//////  IMAGE ROM DATA ALIGNER
////

/*
    Think about Motorola 68020 CPU. It can read unaligned data from bus.
    This thing does the same to prevent pipeline stall.
*/

//make 2D array
reg     [7:0]   imgrom_data_latched[0:31];
int i;
always_comb begin
    for(i=0; i<32; i=i+1) begin
        if(i < 16) imgrom_data_latched[i] = imgrom_dout0_z[(15-i)*8+:8]; //big endian to small endian
        else       imgrom_data_latched[i] = imgrom_dout1_z[(31-i)*8+:8];
    end
end

//data offset
reg     [4:0]   data_offset;
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        data_offset <= 5'd0;
    end
    else begin
        if(i_DATA_OFFSET_WE) data_offset <= i_DATA_OFFSET;
        else data_offset <= data_offset + 5'd16; //discard carry, wraps around
    end
end

//MUX
genvar j;
generate
for(j=0; j<16; j=j+1) begin
    always_comb begin
        o_DOUT[j] = imgrom_data_latched[data_offset + j[4:0]]; //apply offset
    end
end
endgenerate

endmodule
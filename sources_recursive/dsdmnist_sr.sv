module dsdaccel_sr (
    input   wire            i_CLK,

    //fisrt stage
    input   wire            i_BYTE_WE,
    input   wire    [3:0]   i_BYTE_ADDR,
    input   wire    [7:0]   i_BYTE_DIN,
    input   wire            i_WORD_RST,
    input   wire            i_WORD_WE,
    input   wire    [15:0]  i_WORD_MASK,
    input   wire    [7:0]   i_WORD_DIN[0:15],

    //control
    input   wire            i_CHAIN_RST,
    input   wire            i_CHAIN_SHIFT,

    //output
    output  reg     [7:0]   o_OUT[0:261]
);


//stage 0
int     k;
reg     [7:0]   sr_stage_0[0:15];
always_ff @(posedge i_CLK) begin
    if(i_WORD_RST) begin
        sr_stage_0 <= '{16{8'h00}};
    end
    else begin
        if(i_WORD_WE) begin
            for(k=0; k<16; k=k+1) begin
                sr_stage_0[k] <= i_WORD_MASK[k] ? 8'h00 : i_WORD_DIN[k];
            end
        end
        else begin
            if(i_BYTE_WE) begin
                sr_stage_0[i_BYTE_ADDR] <= i_BYTE_DIN;
            end
        end
    end
end


//stage 1 to 16
reg     [7:0]   sr_middle[16][16];
int     i;
always_ff @(posedge i_CLK) begin
    if(i_CHAIN_RST) begin
        for(i=0; i<16; i=i+1) begin
            sr_middle[i] <= '{16{8'h00}};
        end
    end
    else begin
        if(i_CHAIN_SHIFT) begin
            for(i=0; i<16; i=i+1) begin
                if(i == 0)  sr_middle[i] <= sr_stage_0;
                else        sr_middle[i] <= sr_middle[i-1];
            end
        end
    end
end

int     j;
always_comb begin
    for(j=0; j<16; j=j+1) begin
        o_OUT[j*16+:16] = sr_middle[15-j];
    end

    o_OUT[256] = sr_stage_0[0];
    o_OUT[257] = sr_stage_0[1];
    o_OUT[258] = sr_stage_0[2];
    o_OUT[259] = sr_stage_0[3];
    o_OUT[260] = sr_stage_0[4];
    o_OUT[261] = sr_stage_0[5];
end


/*
genvar i;
generate
for(i=1; i<17; i=i+1) begin : sr_middle
    int     j;
    reg     [7:0]   sr_stage_middle[0:15];
    always @(*) begin
        for(j=0; j<16; j=j+1) begin
            o_OUT[(16-i)*16 + j] = sr_stage_middle[j];
        end
    end
end
endgenerate

//descript shift behavior, fucking Vivado cannot parse the variable in a genvar index
always_ff @(posedge i_CLK) begin
    if(i_CHAIN_RST) begin
        sr_middle[1 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[2 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[3 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[4 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[5 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[6 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[7 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[8 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[9 ].sr_stage_middle <= '{16{8'h00}};
        sr_middle[10].sr_stage_middle <= '{16{8'h00}};
        sr_middle[11].sr_stage_middle <= '{16{8'h00}};
        sr_middle[12].sr_stage_middle <= '{16{8'h00}};
        sr_middle[13].sr_stage_middle <= '{16{8'h00}};
        sr_middle[14].sr_stage_middle <= '{16{8'h00}};
        sr_middle[15].sr_stage_middle <= '{16{8'h00}};
        sr_middle[16].sr_stage_middle <= '{16{8'h00}};
    end
    else begin
        if(i_CHAIN_SHIFT) begin
            sr_middle[1 ].sr_stage_middle <= sr_stage_0;
            sr_middle[2 ].sr_stage_middle <= sr_middle[1 ].sr_stage_middle;
            sr_middle[3 ].sr_stage_middle <= sr_middle[2 ].sr_stage_middle;
            sr_middle[4 ].sr_stage_middle <= sr_middle[3 ].sr_stage_middle;
            sr_middle[5 ].sr_stage_middle <= sr_middle[4 ].sr_stage_middle;
            sr_middle[6 ].sr_stage_middle <= sr_middle[5 ].sr_stage_middle;
            sr_middle[7 ].sr_stage_middle <= sr_middle[6 ].sr_stage_middle;
            sr_middle[8 ].sr_stage_middle <= sr_middle[7 ].sr_stage_middle;
            sr_middle[9 ].sr_stage_middle <= sr_middle[8 ].sr_stage_middle;
            sr_middle[10].sr_stage_middle <= sr_middle[9 ].sr_stage_middle;
            sr_middle[11].sr_stage_middle <= sr_middle[10].sr_stage_middle;
            sr_middle[12].sr_stage_middle <= sr_middle[11].sr_stage_middle;
            sr_middle[13].sr_stage_middle <= sr_middle[12].sr_stage_middle;
            sr_middle[14].sr_stage_middle <= sr_middle[13].sr_stage_middle;
            sr_middle[15].sr_stage_middle <= sr_middle[14].sr_stage_middle;
            sr_middle[16].sr_stage_middle <= sr_middle[15].sr_stage_middle;
        end
    end
end
*/

endmodule
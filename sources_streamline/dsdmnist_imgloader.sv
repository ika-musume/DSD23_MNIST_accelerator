module dsdmnist_imgloader #(
    parameter IAW = 0,
    parameter ROMHEX = ""
    ) (
    input   wire                i_CLK,
    input   wire                i_RST,

    //start control
    input   wire                i_START,
    output  wire                o_DONE,

    //shift register control
    output  reg signed  [7:0]   o_DOUT[0:3],
    output  reg                 o_SHIFT
);


///////////////////////////////////////////////////////////
//////  IMAGE ROM
////

reg     [IAW-1:0]   imgrom_addr_cntr;
reg     [31:0]      imgrom_dout;
(* ram_style = "block" *) reg     [31:0] imgrom[0:(2**IAW)-1];
always_ff @(posedge i_CLK) begin
    imgrom_dout <= imgrom[imgrom_addr_cntr];
end

initial begin
    if(ROMHEX != "") $readmemh(ROMHEX, imgrom);
end

int     i;
reg     [7:0]   imgrom_data[0:3];
always_comb begin
    for(i=0; i<4; i=i+1) begin
        imgrom_data[i] = imgrom_dout[(3-i)*8+:8];
    end
end

int     j;
reg     [7:0]   imgrom_data_quantized[0:3];
always_comb begin
    for(j=0; j<4; j=j+1) begin
        //imgrom_data_quantized[i] = imgrom_data[i][2] ? (imgrom_data[i] >> 3) + 8'd1 : (imgrom_data[i] >> 3);
        imgrom_data_quantized[j] = imgrom_data[j] >> 3; //DO NOT ROUND
        //imgrom_data_quantized[j] = imgrom_data[j]; //TEST
        o_DOUT[j] = signed'(imgrom_data_quantized[j]);
    end
end



///////////////////////////////////////////////////////////
//////  CYCLE COUNTER / SEQUENCER
////

reg             run;
reg     [8:0]   cycle_cntr;
reg             imgrom_addr_inc;
assign  o_DONE = (cycle_cntr == 9'd511);

always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        run <= 1'b0;
        cycle_cntr <= 9'd0;

        imgrom_addr_inc <= 1'b0;

        o_SHIFT <= 1'b0;
    end
    else begin
        if(run) begin
            if(cycle_cntr == 9'd511) begin
                run <= 1'b0;
                cycle_cntr <= 9'd0;
            end
            else begin
                cycle_cntr <= cycle_cntr + 9'd1;

                if(cycle_cntr < 9'd196) imgrom_addr_inc <= 1'b1;
                else imgrom_addr_inc <= 1'b0;
            end
        end
        else begin
            if(i_START) run <= 1'b1;
        end
    end

         if(cycle_cntr == 9'd1)     o_SHIFT <= 1'b1;
    else if(cycle_cntr == 9'd197)   o_SHIFT <= 1'b0;

end



///////////////////////////////////////////////////////////
//////  IMGROM ADDR CNTR
////

always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        imgrom_addr_cntr <= {IAW{1'b0}};
    end
    else begin
        if(imgrom_addr_inc) imgrom_addr_cntr <= imgrom_addr_cntr == {IAW{1'b1}} ? {IAW{1'b0}} : imgrom_addr_cntr + {{IAW-1{1'b0}}, 1'b1};
    end
end



endmodule
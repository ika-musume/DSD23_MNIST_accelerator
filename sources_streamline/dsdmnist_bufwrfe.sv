module dsdmnist_bufwrfe #(parameter IMGNUM = 10, parameter OAW = 10) (
    input   wire                i_CLK,
    input   wire                i_RST,

    //start control
    input   wire                i_START,

    //layer3 data input
    input   wire signed [31:0]  i_DIN[0:9],

    //done signal
    output  reg                 o_DONELED,
    output  wire                o_ARMINT,

    //buffer control
    output  wire                o_RESULTBUF_EN,
    output  wire                o_RESULTBUF_WE,
    output  wire        [31:0]  o_RESULTBUF_DATA,
    output  wire        [OAW-1:0] o_RESULTBUF_ADDR
);





///////////////////////////////////////////////////////////
//////  START SIGNAL DELAY
////

reg             start_z, start_zz;
always_ff @(posedge i_CLK) begin
    start_z <= i_START;
    start_zz <= start_z;
end



///////////////////////////////////////////////////////////
//////  VALUE LATCH
////

int     i;
wire                shift;
reg signed  [31:0]  result[0:9];
always_ff @(posedge i_CLK) begin
    if(start_zz) begin
        result <= i_DIN;
    end
    else begin
        if(shift) begin
            for(i=0; i<10; i=i+1) begin
                if(i < 9) result[i] <= result[i+1];
                else result[i] <= 32'sd0;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  CYCLE COUNTER / SEQUENCER
////

reg             run;
reg     [3:0]   cycle_cntr;

assign  shift = run;
assign  o_RESULTBUF_EN = run;
assign  o_RESULTBUF_WE = run;

always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        run <= 1'b0;
        cycle_cntr <= 4'd0;
    end
    else begin
        if(run) begin
            if(cycle_cntr == 4'd9) begin
                run <= 1'b0;
                cycle_cntr <= 4'd0;
            end
            else begin
                cycle_cntr <= cycle_cntr + 4'd1;
            end
        end
        else begin
            if(start_zz) run <= 1'b1;
        end
    end
end



///////////////////////////////////////////////////////////
//////  RESULT BUFFER ADDRESS COUNTER
////

reg     [OAW-1:0]   resultbuf_addr;
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        resultbuf_addr <= {OAW{1'b0}};
    end
    else begin
        if(run) resultbuf_addr <= (resultbuf_addr == {OAW{1'b1}}) ? {OAW{1'b0}} : resultbuf_addr + {{OAW-1{1'b0}}, 1'b1};
    end
end

assign  o_RESULTBUF_DATA = result[0];
assign  o_RESULTBUF_ADDR = resultbuf_addr;



///////////////////////////////////////////////////////////
//////  
////

//interrupt generator
reg     [3:0]   intcntr;
assign  o_ARMINT = |{intcntr[2:0]};
always_ff @(posedge i_CLK) begin
    if(i_RST) begin
        o_DONELED <= 1'b0;
        intcntr <= 4'd0;
    end
    else begin
        if(resultbuf_addr > (IMGNUM*10)-1) begin
            o_DONELED <= 1'b1;
            intcntr <= intcntr == 4'd8 ? 4'd8 : intcntr + 4'd1;
        end
    end
end


endmodule
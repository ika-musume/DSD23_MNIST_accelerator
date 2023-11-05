module dsdmnist_sequencer #(parameter IAW = 0, parameter OAW = 0, parameter IMGNUM = 1) (
    input   wire                i_CLK,
    input   wire                i_RST_n,

    //host interface
    input   wire                i_STARTSW,
    output  wire                o_ARMINT,
    output  reg                 o_DONELED,

    //image rom control
    output  wire    [IAW-1:0]   o_IMGROM_ADDR, //image rom address
    output  wire                o_IMGROM_RST,
    output  wire                o_IMGROM_HOLD,
    output  wire    [4:0]       o_IMGROM_DATA_OFFSET,
    output  wire                o_IMGROM_DATA_OFFSET_WE,

    //integrate buffer control
    output  wire    [9:0]       o_WEIGHTROM_PA_ADDR, //port a is read only
    output  wire    [9:0]       o_WEIGHTROM_PB_ADDR, //port b r/w
    output  wire                o_WEIGHTROM_PB_WE,

    //shift register control
    output  wire    [3:0]       o_SR_BYTE_ADDR, //byte address
    output  wire                o_SR_BYTE_WE, //byte write
    output  wire                o_SR_WORD_RST, //
    output  wire                o_SR_WORD_WE, //word write
    output  wire    [15:0]      o_SR_WORD_MASK,
    output  wire                o_SR_CHAIN_RST, //sr reset
    output  wire                o_SR_CHAIN_SHIFT, //sr shift

    //operator control
    output  wire                o_ACC_RST, //reset accumulator
    output  wire                o_ACC_EN, //accumulation/bypass

    //post calculator control
    output  wire                o_ACCVAL_LD,
    output  wire                o_COEFF_SEL,

    //output buffer control
    output  wire                o_RESULTBUF_EN,
    output  wire                o_RESULTBUF_WE,
    output  wire    [OAW-1:0]   o_RESULTBUF_ADDR
);



///////////////////////////////////////////////////////////
//////  STATE MACHINE
////

localparam  RST  = 3'd0; //reset state
localparam  INIT = 3'd1; //initialize adder tree, image prefetch
localparam  RUN  = 3'd2; //
localparam  DONE = 3'd3; //done

//fsm state
reg     [2:0]   calc_state = RST;

//image rom counter
reg     [$clog2(IMGNUM)-1:0]    image_cntr;

//interrupt generator
reg     [3:0]   intcntr;
assign  o_ARMINT = |{intcntr[2:0]};

//prefetch frontend
reg                 prefetch_run;
reg                 prefetch_done;

//operator frontend
reg                 operation_run;
reg                 operation_done;

//common control signal
reg                 sr_prefetch_word_rst, sr_bufwr_word_rst;
wire                sr_word_rst = sr_prefetch_word_rst | sr_bufwr_word_rst;
reg                 sr_prefetch_shift, sr_bufwr_shift;
wire                sr_shift = sr_prefetch_shift | sr_bufwr_shift;
reg                 sr_prefetch_chain_rst, sr_bufwr_chain_rst;
wire                sr_chain_rst = sr_prefetch_chain_rst | sr_bufwr_chain_rst;

//weightrom
reg     [9:0]       weightrom_pa_addr;
reg     [9:0]       weightrom_prefetch_pb_addr, weightrom_pb_addr;
reg                 weightrom_prefetch_wrrq, weightrom_bufwr_wrrq;
wire                weightrom_pb_we = weightrom_prefetch_wrrq | weightrom_bufwr_wrrq;

assign  o_SR_WORD_RST = sr_word_rst;


always_ff @(posedge i_CLK) begin
    if(!i_RST_n) begin
        prefetch_run <= 1'b0;
        operation_run <= 1'b0;
        intcntr <= 3'd0;
        o_DONELED <= 1'b0;
        calc_state <= RST;
    end
    else begin
        if(calc_state == RST) begin
            if(i_STARTSW) begin
                calc_state <= INIT;
                prefetch_run <= 1'b1;
            end
        end
        else if(calc_state == INIT) begin
            if(prefetch_done) begin
                calc_state <= RUN;
                operation_run <= 1'b1;
            end
            prefetch_run <= 1'b0;
        end
        else if(calc_state == RUN) begin
            operation_run <= 1'b0;
            if(operation_done) begin
                if(image_cntr == IMGNUM) calc_state <= DONE;
                else begin
                    calc_state <= INIT;
                    prefetch_run <= 1'b1;
                end
            end
        end
        else if(calc_state == DONE) begin
            o_DONELED <= 1'b1;
            intcntr <= intcntr == 4'd8 ? 4'd8 : intcntr + 4'd1;
        end
    end 
end



///////////////////////////////////////////////////////////
//////  PREFETCH SEQUENCER
////

localparam  PREFETCH_STOP = 1'b0;
localparam  PREGETCH_RUN = 1'b1;

//image prefetch
reg     [5:0]       imgrom_prefetch_cycle_cntr;
reg     [IAW-1:0]   imgrom_addr_cntr;
reg     [4:0]       imgrom_data_offset;
reg                 imgrom_data_offset_we;
reg                 imgrom_rst;
reg                 imgrom_hold;
reg                 sr_word_we;
reg     [15:0]      sr_word_mask;

//image prefetch
assign  o_IMGROM_ADDR = imgrom_addr_cntr;
assign  o_IMGROM_RST = imgrom_rst;
assign  o_IMGROM_HOLD = imgrom_hold;
assign  o_IMGROM_DATA_OFFSET = imgrom_data_offset;
assign  o_IMGROM_DATA_OFFSET_WE = imgrom_data_offset_we;
assign  o_SR_WORD_WE = sr_word_we;
assign  o_SR_WORD_MASK = sr_word_mask;

reg             prefetch_state;
always_ff @(posedge i_CLK) begin
    if(!i_RST_n) prefetch_state <= PREFETCH_STOP;
    else begin
        if(prefetch_state == PREFETCH_STOP) begin
            if(prefetch_run) prefetch_state <= PREGETCH_RUN;
        end
        else begin
            if(prefetch_done) prefetch_state <= PREFETCH_STOP;
        end
    end
end

always_ff @(posedge i_CLK) begin
    if(!i_RST_n) begin
        //prefetch done
        prefetch_done <= 1'b0;

        //common
        sr_prefetch_shift <= 1'b0;

        //image prefetch
        imgrom_prefetch_cycle_cntr <= 6'd54;
        imgrom_addr_cntr <= {IAW{1'b1}};
        
        imgrom_rst <= 1'b1;
        imgrom_hold <= 1'b1;
        imgrom_data_offset <= 5'd0;
        imgrom_data_offset_we <= 1'b0;
        weightrom_prefetch_wrrq <= 1'b0;
        weightrom_prefetch_pb_addr <= 10'd0;

        sr_word_we <= 1'b0;
        sr_prefetch_word_rst <= 1'b0;
        sr_word_mask <= 16'h0000;
        sr_prefetch_shift <= 1'b0;
        sr_prefetch_chain_rst <= 1'b1;
    end
    else begin
        if(prefetch_state == PREFETCH_STOP) begin
            //prefetch done
            prefetch_done <= 1'b0;

            //common
            sr_prefetch_shift <= 1'b0;

            //image prefetch
            imgrom_prefetch_cycle_cntr <= 6'd54;
            imgrom_addr_cntr <= imgrom_addr_cntr;
            
            imgrom_rst <= 1'b1;
            imgrom_hold <= 1'b1;
            imgrom_data_offset <= 5'd0;
            imgrom_data_offset_we <= 1'b0;
            weightrom_prefetch_wrrq <= 1'b0;
            weightrom_prefetch_pb_addr <= 10'd0;

            sr_word_we <= 1'b0;
            sr_prefetch_word_rst <= 1'b0;
            sr_word_mask <= 16'h0000;
            sr_prefetch_shift <= 1'b0;
            sr_prefetch_chain_rst <= 1'b0;
        end
        else begin
            //prefetch done
            if(imgrom_prefetch_cycle_cntr == 6'd53) prefetch_done <= 1'b1;
            else prefetch_done <= 1'b0;

            //count up cycle-address
            if(imgrom_prefetch_cycle_cntr == 6'd54) imgrom_prefetch_cycle_cntr <= 6'd0;
            else imgrom_prefetch_cycle_cntr <= imgrom_prefetch_cycle_cntr + 6'd1; //master prefetch cycle counter
            
            if(imgrom_hold || imgrom_prefetch_cycle_cntr > 6'd49) imgrom_addr_cntr <= imgrom_addr_cntr;
            else imgrom_addr_cntr <= imgrom_addr_cntr == {IAW{1'b1}} ? {IAW{1'b0}} : imgrom_addr_cntr + {{IAW-1{1'b0}}, 1'b1}; //imgrom address counter !DO NOT RESET!

            //negate imgrome reset
                 if(imgrom_prefetch_cycle_cntr == 6'd0) imgrom_rst <= 1'b1;
            else if(imgrom_prefetch_cycle_cntr > 6'd51) imgrom_rst <= 1'b1;
            else                                        imgrom_rst <= 1'b0;

            //negate word reset
                 if(imgrom_prefetch_cycle_cntr == 6'd0) sr_prefetch_word_rst <= 1'b1;
            else                                        sr_prefetch_word_rst <= 1'b0;

            //hold imgrom update
            if(imgrom_prefetch_cycle_cntr == 6'd33) imgrom_hold <= 1'b1;
            //else if(imgrom_prefetch_cycle_cntr == 6'd34) imgrom_hold <= 1'b1;
            else                                    imgrom_hold <= 1'b0;
            
            //chain reset for last line
                 if(imgrom_prefetch_cycle_cntr == 6'd36) sr_prefetch_chain_rst <= 1'b1;
            else                                         sr_prefetch_chain_rst <= 1'b0;

            //write enable
                 if(imgrom_prefetch_cycle_cntr == 6'd2)  sr_word_we <= 1'b1;
            else if(imgrom_prefetch_cycle_cntr == 6'd53) sr_word_we <= 1'b0;

            //word mask
            if(imgrom_prefetch_cycle_cntr == 6'd52) sr_word_mask <= 16'b1111_1111_1111_0000;
            else sr_word_mask <= 16'h0000;

            //shift enable
                 if(imgrom_prefetch_cycle_cntr == 6'd3) sr_prefetch_shift <= 1'b1;
            else if(imgrom_prefetch_cycle_cntr == 6'd53) sr_prefetch_shift <= 1'b0;

            //rom write
                 if(imgrom_prefetch_cycle_cntr == 6'd19) begin weightrom_prefetch_wrrq <= 1'b1; weightrom_prefetch_pb_addr <= 10'd960; end
            else if(imgrom_prefetch_cycle_cntr == 6'd36) begin weightrom_prefetch_wrrq <= 1'b1; weightrom_prefetch_pb_addr <= 10'd961; end
            else if(imgrom_prefetch_cycle_cntr == 6'd53) begin weightrom_prefetch_wrrq <= 1'b1; weightrom_prefetch_pb_addr <= 10'd962; end
            else                                         begin weightrom_prefetch_wrrq <= 1'b0; weightrom_prefetch_pb_addr <= 10'd0; end

            //data offset revise
                 if(imgrom_prefetch_cycle_cntr == 6'd0 ) begin imgrom_data_offset <= 5'd0;  imgrom_data_offset_we <= 1'b1; end
            else if(imgrom_prefetch_cycle_cntr == 6'd18) begin imgrom_data_offset <= 5'd22; imgrom_data_offset_we <= 1'b1; end
            else if(imgrom_prefetch_cycle_cntr == 6'd35) begin imgrom_data_offset <= 5'd28; imgrom_data_offset_we <= 1'b1; end
            else if(imgrom_prefetch_cycle_cntr == 6'd53) begin imgrom_data_offset <= 5'd0;  imgrom_data_offset_we <= 1'b1; end
            else                                                                            imgrom_data_offset_we <= 1'b0;
        end
    end
end



///////////////////////////////////////////////////////////
//////  LAYER CALCULATION SEQUENCER
////

localparam  OPERATION_STOP = 1'b0;
localparam  OPERATION_RUN = 1'b1;

//control bits
reg     [1:0]       layer_cntr; //0-2 layer
reg     [9:0]       operation_cycle_cntr;
reg                 rom_acc_stop;

//shift register
reg     [3:0]       sr_byte_addr_cntr;

//accmumulator
reg                 acc_rst;
reg                 acc_en;
reg                 accval_ld;

//postcalc
reg                 coeff_sel;

//output buffer write
reg                 result_write;

//operation control
reg             operation_state;
always_ff @(posedge i_CLK) begin
    if(!i_RST_n) operation_state <= OPERATION_STOP;
    else begin
        if(operation_state == OPERATION_STOP) begin
            if(operation_run) operation_state <= OPERATION_RUN;
        end
        else begin
            if(operation_done) operation_state <= OPERATION_STOP;
        end
    end
end


always_ff @(posedge i_CLK) begin
    if(!i_RST_n) begin
        image_cntr <= {$clog2(IMGNUM){1'b0}};
        operation_done <= 1'b0;
        layer_cntr <= 2'd0;

        rom_acc_stop <= 1'b0;

        sr_bufwr_word_rst <= 1'b0;
        sr_bufwr_chain_rst <= 1'b0;

        weightrom_pa_addr <= 10'd0;
        weightrom_pb_addr <= 10'd960;
        weightrom_bufwr_wrrq <= 1'b0;

        acc_rst <= 1'b1;
        acc_en <= 1'b0;

        accval_ld <= 1'b0;
        coeff_sel <= 1'b0;

        result_write <= 1'b0;
    end
    else begin
        if(operation_state == OPERATION_STOP) begin
            operation_cycle_cntr <= 10'd0;
            operation_done <= 1'b0;
            layer_cntr <= 2'd0;

            rom_acc_stop <= 1'b0;

            sr_bufwr_word_rst <= 1'b0;

            sr_bufwr_chain_rst <= 1'b0;

            weightrom_pa_addr <= 10'd0;
            weightrom_pb_addr <= 10'd960;
            weightrom_bufwr_wrrq <= 1'b0;

            acc_rst <= 1'b1;
            acc_en <= 1'b0;

            accval_ld <= 1'b0;
            coeff_sel <= 1'b0;

            result_write <= 1'b0;
        end
        else begin
            operation_cycle_cntr <= operation_cycle_cntr == 10'd1023 ? 10'd0 : operation_cycle_cntr + 10'd1;

            if(layer_cntr == 0) begin
                coeff_sel <= 1'b0; //l1 coefficient
                if(rom_acc_stop == 1'b0) begin
                    weightrom_pa_addr <= weightrom_pa_addr == 10'd767 ? 10'd0 : weightrom_pa_addr + 10'd1; //weights
                    weightrom_pb_addr <= weightrom_pb_addr == 10'd962 ? 10'd960 : weightrom_pb_addr + 10'd1; //image

                    //negate reset
                    acc_rst <= 1'b0;

                    //accumulator enable
                        if(weightrom_pb_addr[1:0] == 2'd0) acc_en <= 1'b0;
                    else if(weightrom_pb_addr[1:0] == 2'd1) acc_en <= 1'b1;
                    else if(weightrom_pb_addr[1:0] == 2'd2) acc_en <= 1'b1;
                    else                                    acc_en <= 1'b0;

                    //load accumulator value to postcalc
                        if(weightrom_pb_addr[1:0] == 2'd2) accval_ld <= 1'b1;
                    else                                    accval_ld <= 1'b0;

                    if(operation_cycle_cntr == 10'd767) rom_acc_stop <= 1'b1;

                    if(operation_cycle_cntr == 10'd0) begin sr_bufwr_word_rst <= 1'b1; sr_bufwr_chain_rst <= 1'b1; end
                    else                              begin sr_bufwr_word_rst <= 1'b0; sr_bufwr_chain_rst <= 1'b0; end
                end
                else begin
                    //write once
                    weightrom_pb_addr <= 10'd920;
                    if(operation_cycle_cntr == 10'd778) weightrom_bufwr_wrrq <= 1'b1;
                    else weightrom_bufwr_wrrq <= 1'b0;

                    acc_en <= 1'b0;
                    accval_ld <= 1'b0;

                    //next layer
                    if(operation_cycle_cntr == 10'd779) begin 
                        layer_cntr <= 2'd1; 
                        rom_acc_stop <= 1'b0; 
                        weightrom_pa_addr <= 10'd768;
                        weightrom_pb_addr <= 10'd920;
                        acc_rst <= 1'b1;
                    end
                end
            end
            else if(layer_cntr == 2'd1) begin
                coeff_sel <= 1'b1; //l2 coefficient
                if(rom_acc_stop == 1'b0) begin
                    weightrom_pa_addr <= weightrom_pa_addr == 10'd895 ? 10'd768 : weightrom_pa_addr + 10'd1; //weights
                    weightrom_pb_addr <= 10'd920; //L1 values

                    //negate reset
                    acc_rst <= 1'b0;

                    accval_ld <= 1'b1;

                    if(operation_cycle_cntr == 10'd907) rom_acc_stop <= 1'b1;

                    if(operation_cycle_cntr == 10'd780) begin sr_bufwr_word_rst <= 1'b1; sr_bufwr_chain_rst <= 1'b1; end
                    else                                begin sr_bufwr_word_rst <= 1'b0; sr_bufwr_chain_rst <= 1'b0; end
                end
                else begin
                    //write once
                    weightrom_pb_addr <= 10'd921;
                    if(operation_cycle_cntr == 10'd918) weightrom_bufwr_wrrq <= 1'b1;
                    else weightrom_bufwr_wrrq <= 1'b0;

                    accval_ld <= 1'b0;

                    //next layer
                    if(operation_cycle_cntr == 10'd920) begin 
                        layer_cntr <= 2'd2; 
                        rom_acc_stop <= 1'b0; 
                        weightrom_pa_addr <= 10'd896;
                        weightrom_pb_addr <= 10'd921;
                        acc_rst <= 1'b1;
                    end
                end
            end
            else if(layer_cntr == 2'd2) begin
                if(rom_acc_stop == 1'b0) begin
                    weightrom_pa_addr <= weightrom_pa_addr == 10'd905 ? 10'd896 : weightrom_pa_addr + 10'd1; //weights
                    weightrom_pb_addr <= 10'd921; //L2 values

                    //negate reset
                    acc_rst <= 1'b0;

                        if(operation_cycle_cntr == 10'd927) result_write <= 1'b1;
                    else if(operation_cycle_cntr == 10'd937) result_write <= 1'b0;

                    if(operation_cycle_cntr == 10'd939) rom_acc_stop <= 1'b1;
                end
                else begin
                    layer_cntr <= 2'd0;

                    weightrom_pa_addr <= 10'd0;
                    weightrom_pa_addr <= 10'd0;

                    image_cntr <= image_cntr + {{$clog2(IMGNUM)-1{1'b0}}, 1'b1};

                    operation_done <= 1'b1;
                end
            end
        end
    end
end

//delay chain for the pipeline control
reg     [5:0]   acc_en_dly;
reg     [6:0]   accval_ld_dly;
reg     [2:0]   sr_byte_we_dly;
always_ff @(posedge i_CLK) begin
    acc_en_dly[0] <= acc_en;
    acc_en_dly[5:1] <= acc_en_dly[4:0];

    accval_ld_dly[0] <= accval_ld;
    accval_ld_dly[6:1] <= accval_ld_dly[5:0];
end

//byte write counter, this will automatically write values to buffers
always_ff @(posedge i_CLK) begin
    sr_byte_we_dly[0] <= accval_ld_dly[6];
    sr_byte_we_dly[2:1] <= sr_byte_we_dly[1:0];

    if(acc_rst) sr_byte_addr_cntr <= 4'd5;
    else begin
        if(sr_byte_we_dly[1]) begin
            sr_byte_addr_cntr <= sr_byte_addr_cntr == 4'd15 ? 4'd0 : sr_byte_addr_cntr + 4'd1;
        end
        else begin
            sr_byte_addr_cntr <= sr_byte_addr_cntr;
        end
    end

    if(sr_byte_addr_cntr == 16'd15 && o_SR_BYTE_WE) sr_bufwr_shift <= 1'b1;
    else sr_bufwr_shift <= 1'b0;
end

//result buffer writer
reg     [OAW-1:0]   resultbuf_addr;
reg                 resultbuf_en, resultbuf_we;

assign  o_RESULTBUF_ADDR = resultbuf_addr;
assign  o_RESULTBUF_EN = resultbuf_en;
assign  o_RESULTBUF_WE = resultbuf_we;

always_ff @(posedge i_CLK) begin
    if(!i_RST_n) begin
        resultbuf_en <= 1'b0;
        resultbuf_we <= 1'b0;

        resultbuf_addr <= {OAW{1'b0}};
    end
    else begin
        if(result_write) begin
            resultbuf_en <= 1'b1;
            resultbuf_we <= 1'b1;
        end
        else begin
            resultbuf_en <= 1'b0;
            resultbuf_we <= 1'b0;
        end

        if(resultbuf_en) begin
            resultbuf_addr <= resultbuf_addr == {OAW{1'b1}} ? {OAW{1'b0}} : resultbuf_addr + {{OAW-1{1'b0}}, 1'b1};
        end
    end
end



//common
assign  o_SR_CHAIN_RST = sr_chain_rst;
assign  o_SR_CHAIN_SHIFT = sr_shift;

//weightrom
assign  o_WEIGHTROM_PA_ADDR = weightrom_pa_addr;
assign  o_WEIGHTROM_PB_ADDR = prefetch_state ? weightrom_prefetch_pb_addr : weightrom_pb_addr;
assign  o_WEIGHTROM_PB_WE = weightrom_pb_we;

//accmumulator
assign  o_ACC_RST = acc_rst;
assign  o_ACC_EN = acc_en_dly[5];

//postcalc
assign  o_ACCVAL_LD = accval_ld_dly[6];
assign  o_COEFF_SEL = coeff_sel;

//sr
assign  o_SR_BYTE_ADDR = sr_byte_addr_cntr;
assign  o_SR_BYTE_WE = sr_byte_we_dly[2];



endmodule
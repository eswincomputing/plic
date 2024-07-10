// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module plic_int_detect
#(parameter NUM_IRQ=48, 
            UNIT_IRQ_NUM=32  //this parameter is used to group number of sync cells for future low power design (turn off a group of sync cell clock)
 )
(

  input  logic                        clk_i          ,
  input  logic                        rst_n_i        ,
  input  logic                        test_mode_i    ,
  
  input  logic  [NUM_IRQ-1:0]         irq_i          ,             
  input  logic  [NUM_IRQ-1:0]         irq_mask_i     ,
  
  //input  logic [$clog2(NUM_IRQ)-1:0]  claim_id_i     ,
  //input  logic                        claim_vld_i    , 
  
  output logic [NUM_IRQ-1:0]          irq_o           //irq 

);
 
  localparam UNIT_WIDTH = $clog2(UNIT_IRQ_NUM);
  localparam LEFT_OVER_IRQ_NUM = NUM_IRQ - (NUM_IRQ/UNIT_IRQ_NUM)*UNIT_IRQ_NUM;
  localparam NUM_OF_UNIT = (LEFT_OVER_IRQ_NUM ==0) ? (NUM_IRQ >> UNIT_WIDTH) : (NUM_IRQ >> UNIT_WIDTH) + 1;
  localparam IRQ_OF_LAST_UNIT =  (LEFT_OVER_IRQ_NUM ==0)  ? UNIT_IRQ_NUM : LEFT_OVER_IRQ_NUM;
 
  logic  [NUM_IRQ-1:0]         synced_irq   ;
  logic  [NUM_IRQ-1:0]         irq_det      ;
  
  //logic  [NUM_OF_UNIT-1:0]     sync_clk_en  ;
  //
  //
  // always_comb
  // begin 
  // for (int i=0; i < NUM_OF_UNIT-1; i++) begin
  //   sync_clk_en[i] = | irq_i[i*UNIT_IRQ_NUM-:UNIT_IRQ_NUM];
  // end
  // sync_clk_en[NUM_OF_UNIT-1] = | irq_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+LEFT_OVER_IRQ_NUM-1-:LEFT_OVER_IRQ_NUM];
  // 
  // end

 
   generate 
   genvar i;
   genvar m;

   for (i=0; i < (NUM_OF_UNIT-1); i++) 
   begin
    for (m=0; m < UNIT_IRQ_NUM; m++) begin 
    `ifndef ERI_EN
      sync_cell inst_irq_sync 
      (
        .clk_i  (clk_i      ), 
        .rst_n_i(rst_n_i    ),
        .din    (irq_i[i*UNIT_IRQ_NUM+m]      ),
        .dout   (synced_irq[i*UNIT_IRQ_NUM+m] )
      );
    `else
   crm_bit_sync 
    inst_irq_sync
    (
    .clk   	 (clk_i)      ,  //I ,1
    .rst_b      (rst_n_i)   ,  //I ,1
    .async_in   (irq_i[i*UNIT_IRQ_NUM+m] )       , //I ,1
    .sync_out   (synced_irq[i*UNIT_IRQ_NUM+m]) //O ,1
    );
    `endif
    end  
   end
   
   endgenerate

   generate 
   genvar k;
   
   for (k=0; k < IRQ_OF_LAST_UNIT; k++) begin 
    `ifndef ERI_EN
      sync_cell inst_irq_sync 
      (
        .clk_i  (clk_i      ), 
        .rst_n_i(rst_n_i    ),
        .din    (irq_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+k]      ),
        .dout   (synced_irq[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+k] )
      );
    `else
   crm_bit_sync 
    inst_irq_sync
    (
    .clk   	 (clk_i)      ,  //I ,1
    .rst_b      (rst_n_i)   ,  //I ,1
    .async_in   (irq_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+k] )       , //I ,1
    .sync_out   (synced_irq[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+k]) //O ,1
    );

    `endif

    end  

   endgenerate
   
   
   always @(posedge clk_i or negedge rst_n_i)
   begin : int_detect
     if(!rst_n_i) begin
       for (int i=0; i < NUM_IRQ; i++) begin 
         irq_det[i]  <= 0;
       end            
	 end
     else begin
       for (int i=0; i < NUM_IRQ; i++) begin 
         if ( ~ irq_mask_i[i] ) begin 
            irq_det[i] <= 1'b0;
         end
         else if ( ~ irq_det[i] & irq_mask_i[i] & synced_irq[i] ) begin 
           irq_det[i] <= 1'b1;
         end 
       end   
	 end 
   end 
   
   assign irq_o = irq_det;
 

endmodule

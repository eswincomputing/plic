// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module plic_irq_arb_tree
#(parameter NUM_IRQ=512, PRIO_BIT=5, UNIT_IRQ_NUM=16, STAGING =1
 )
 //staging means that arb units output are registered and then arb. 
(

  input  logic                        clk_i          ,
  input  logic                        rst_n_i        ,
  input  logic                        test_mode_i    ,
  
  input  logic  [NUM_IRQ-1:0]         irq_i          ,             
  input  logic  [NUM_IRQ-1:0]         irq_en_i       ,
  
  input  logic  [PRIO_BIT-1:0]        irq_th_i       ,  //interrupt threshold
  
  input  logic  [PRIO_BIT-1:0]        irq_pri_i  [NUM_IRQ-1:0]  ,
  
  output logic                        irq_o          , //irq 
  output logic  [$clog2(NUM_IRQ)-1:0] irq_id_o       ,
  output logic  [PRIO_BIT-1:0]        irq_pri_o 

);
 
   localparam UNIT_WIDTH = $clog2(UNIT_IRQ_NUM);
   localparam LEFT_OVER_IRQ_NUM = NUM_IRQ - (NUM_IRQ/UNIT_IRQ_NUM)*UNIT_IRQ_NUM;
   localparam NUM_OF_UNIT = (LEFT_OVER_IRQ_NUM ==0) ? (NUM_IRQ >> UNIT_WIDTH) : (NUM_IRQ >> UNIT_WIDTH) + 1;
   localparam IRQ_OF_LAST_UNIT =  (LEFT_OVER_IRQ_NUM ==0)  ? UNIT_IRQ_NUM : LEFT_OVER_IRQ_NUM;
 

   //each arb unit outputs
   
   logic [NUM_OF_UNIT-1:0]      unit_irq              ;
   logic [$clog2(NUM_IRQ)-1:0]  unit_id  [NUM_OF_UNIT];
   logic  [PRIO_BIT-1:0]        unit_pri [NUM_OF_UNIT]; 

   logic [NUM_OF_UNIT-1:0]      unit_irq_r              ;
   logic [$clog2(NUM_IRQ)-1:0]  unit_id_r  [NUM_OF_UNIT];
   logic  [PRIO_BIT-1:0]        unit_pri_r [NUM_OF_UNIT-1:0]; 
   
   logic                            final_stage_irq;
   logic  [$clog2(NUM_OF_UNIT)-1:0] final_stage_irq_idx;
   logic  [PRIO_BIT-1:0]            final_stage_irq_pri;  
   
   generate 
   
   if (NUM_OF_UNIT >1) begin 
   genvar i;
   //here loop count is NUM_OF_UNIT -1. it means that last arb unit irq number might be less than NUM_IRQ.
   // for example, when IRQ number is 48 and unit number is 32. the last one is 16 (48-32)
   for (i=0; i < (NUM_OF_UNIT-1); i++) 
   begin : irq_arb_unit
     plic_irq_arb
      #(.NUM_IRQ(UNIT_IRQ_NUM), 
        .PRIO_BIT(PRIO_BIT),
        .ID_BASE(i*UNIT_IRQ_NUM),
        .ID_WIDTH($clog2(NUM_IRQ))
       ) inst_irq_arb_unit
       (
         
         //.clk_i         (clk_i       ),
         //.rst_n_i       (rst_n_i     ),
         //.test_mode_i   (test_mode_i ),
         .irq_i         (irq_i[i*UNIT_IRQ_NUM+: UNIT_IRQ_NUM] ),             
         .irq_en_i      (irq_en_i[i*UNIT_IRQ_NUM+: UNIT_IRQ_NUM]    ),
         .irq_pri_i     (irq_pri_i[i*UNIT_IRQ_NUM+: UNIT_IRQ_NUM]   ),
         .irq_o         (unit_irq[i]    ), //irq 
         .irq_id_o      (unit_id[i]     ),
         .irq_pri_o     (unit_pri[i] )
       
       ); 
   end
   end
   
   plic_irq_arb
      #(.NUM_IRQ(IRQ_OF_LAST_UNIT), 
        .PRIO_BIT(PRIO_BIT),
        .ID_BASE((NUM_OF_UNIT-1)*UNIT_IRQ_NUM),
        .ID_WIDTH($clog2(NUM_IRQ))
       ) last_irq_arb_unit
       (
         
         //.clk_i         (clk_i       ),
         //.rst_n_i       (rst_n_i     ),
         //.test_mode_i   (test_mode_i ),
         .irq_i         (irq_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+: IRQ_OF_LAST_UNIT] ),             
         .irq_en_i      (irq_en_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+: IRQ_OF_LAST_UNIT]    ),
         .irq_pri_i     (irq_pri_i[(NUM_OF_UNIT-1)*UNIT_IRQ_NUM+: IRQ_OF_LAST_UNIT]   ),
         .irq_o         (unit_irq[NUM_OF_UNIT-1]    ), //irq 
         .irq_id_o      (unit_id[NUM_OF_UNIT-1]  ),
         .irq_pri_o     (unit_pri[NUM_OF_UNIT-1] )
       
       ); 
   endgenerate
   
   
   generate
   
   if (STAGING==1) begin 
      always @(posedge clk_i or negedge rst_n_i)
      begin : staging_proc
        if(!rst_n_i) begin
          unit_irq_r <= 0;
          for (int i=0; i < NUM_OF_UNIT; i++) begin 
            unit_id_r[i]  <= 0;
            unit_pri_r[i] <= 0;
          end            
	    end
        else begin
	      unit_irq_r <= unit_irq;
          for (int i=0; i < NUM_OF_UNIT; i++) begin 
            unit_id_r[i]  <= unit_id[i];
            unit_pri_r[i] <= unit_pri[i];
          end
	    end
      end 
 
   
   
   end
   else begin
	 assign unit_irq_r =  unit_irq;
     //assign unit_id_r  = unit_id ;
     assign unit_pri_r = unit_pri;
     
     always_comb
     begin 
       for (int i=0; i < NUM_OF_UNIT ; i++) begin     
         unit_id_r[i] =  unit_id[i]; 
       end 
     end 
   end   
   
   endgenerate
   
  
  
  //Please make sure that  NUM_OF_UNIT < UNIT_IRQ_NUM;   
   generate 
   if (NUM_OF_UNIT > 1) begin 
   plic_irq_arb
   #(.NUM_IRQ(NUM_OF_UNIT), 
     .PRIO_BIT(PRIO_BIT),
     .ID_BASE('0),
     .ID_WIDTH($clog2(NUM_OF_UNIT))
    ) inst_final_irq_arb
    (
      
      //.clk_i         (clk_i       ),
      //.rst_n_i       (rst_n_i     ),
      //.test_mode_i   (test_mode_i ),
      .irq_i         (unit_irq_r ),             
      .irq_en_i      ({NUM_OF_UNIT{1'b1}}  ),
      .irq_pri_i     (unit_pri_r  ),
      .irq_o         (final_stage_irq      ), //irq 
      .irq_id_o      (final_stage_irq_idx  ),
      .irq_pri_o     (final_stage_irq_pri  )
    
    );
    end    
    else begin 
      assign final_stage_irq     = unit_irq_r[0];
      assign final_stage_irq_idx = unit_id_r[0];
      assign final_stage_irq_pri = unit_pri_r[0];
    
    end
    
    endgenerate
 
 
   assign irq_o     = (final_stage_irq_pri > irq_th_i) ? final_stage_irq : 1'b0;
   assign irq_id_o  = (final_stage_irq_pri > irq_th_i) ? unit_id_r[final_stage_irq_idx] : 0;
   assign irq_pri_o = (final_stage_irq_pri > irq_th_i) ? final_stage_irq_pri : 0;
     

endmodule

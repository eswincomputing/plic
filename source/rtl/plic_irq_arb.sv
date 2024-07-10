// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module base_irq_arb 
#(parameter NUM_IRQ=32, Pri_LVL=0, PRIO_BIT =5, ID_WIDTH=5
 )
(

  input  logic  [NUM_IRQ-1:0]         irq_i          ,             
  input  logic  [NUM_IRQ-1:0]         irq_en_i       ,
  
  input  logic  [PRIO_BIT-1:0]        irq_pri_i  [NUM_IRQ-1:0]  ,
  
  output logic                        irq_o          , //irq 
  output logic  [ID_WIDTH-1:0]        irq_id_o       

);
 
 //logic done;

 //assign irq_o = (| irq_i) & (| irq_en_i) & done; 

 always_comb
 begin 
  irq_o = 1'b0;
  irq_id_o = 0;
  for (int i=NUM_IRQ-1; i >= 0; i--) begin //smallest ID with same priority wins the arbitration
    if (irq_i[i] & irq_en_i[i] & irq_pri_i[i] == Pri_LVL) begin
      irq_id_o = i;
      irq_o    = 1'b1;
     end
  end    
 end
endmodule 


module plic_irq_arb
#(parameter NUM_IRQ=32, ID_BASE=0, PRIO_BIT=3, ID_WIDTH=5
 )
(

  //input  logic                        clk_i          ,
  //input  logic                        rst_n_i        ,
  //input  logic                        test_mode_i    ,
  
  input  logic  [NUM_IRQ-1:0]         irq_i          ,             
  input  logic  [NUM_IRQ-1:0]         irq_en_i       ,
  
  input  logic  [PRIO_BIT-1:0]        irq_pri_i  [NUM_IRQ-1:0]  ,
  
  output logic                        irq_o          , //irq 
  output logic  [ID_WIDTH-1:0]        irq_id_o       ,
  output logic  [PRIO_BIT-1:0]        irq_pri_o 

);

  localparam NUM_ARB_UNIT = 2 ** PRIO_BIT;

  logic [NUM_ARB_UNIT-1:0]      lvl_irq_val;
  logic [ID_WIDTH-1:0]          lvl_irq_id [NUM_ARB_UNIT-1:0];
  logic [PRIO_BIT-1:0]          final_lvl_idx;

  generate 
   genvar i;
   for (i=0; i < NUM_ARB_UNIT; i++) 
   begin : lvl_arb
     
     base_irq_arb
      #(.NUM_IRQ(NUM_IRQ), 
        .Pri_LVL(i),
        .PRIO_BIT(PRIO_BIT),
        .ID_WIDTH(ID_WIDTH)
       ) inst_lvl_arb
       (
         .irq_i         (irq_i          ),             
         .irq_en_i      (irq_en_i       ),
         .irq_pri_i     (irq_pri_i      ),
         .irq_o         (lvl_irq_val[i] ),
         .irq_id_o      (lvl_irq_id[i]  )
       ); 
   end
 endgenerate

 always_comb
 begin
    final_lvl_idx = 0;
    for (int i=0; i < NUM_ARB_UNIT; i++) begin
      if (lvl_irq_val[i] ) begin
        final_lvl_idx = i;
      end
   end   
end    

assign irq_o = lvl_irq_val[final_lvl_idx];
assign irq_pri_o  = final_lvl_idx;
assign irq_id_o   = lvl_irq_id[final_lvl_idx] + ID_BASE;
 
endmodule

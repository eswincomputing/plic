// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */
module plic_arb_tb 
(


);


logic clk;
logic rst_n;

logic [31:0] irq_i;

logic [31:0] irq_en;

logic [4:0] irq_lvl [31:0];

logic  arb_irq;

logic [5:0]  arb_irq_id;

logic [4:0] arb_irq_lvl;

initial forever #10 clk = ~ clk;


initial 
begin
   clk = 1'b0;
   rst_n =1'b0;
   irq_i =32'h0;
   irq_en = 32'h0;
   for (int i=0 ; i < 32; i++) begin
     irq_lvl[i] = 0;
   end

   
   #100;
   rst_n =1'b1;
   @(posedge clk);
   
   irq_i = 32'h0;
   irq_en = 32'hffff_ffff;

   for (int i=0 ; i < 32; i=i+2) begin
    irq_i[i] = 1'b1;
   end

   for (int i=0 ; i < 32; i++) begin
     if ( i >=0  & i < 8 )  
       irq_lvl[i] = 10;
     else if ( i >=8 & i < 16)  
       irq_lvl[i] = 8;
     else if ( i>= 16 & i < 24)  
        irq_lvl[i] = 20;
     else 
        irq_lvl[i] = 15;
  end

    #1 ;

   //update lvl

   @(posedge clk);
   
   irq_i = 32'h0;

   for (int i=1 ; i < 32; i++) begin
    irq_i[i] = 1'b1;
   end

   for (int i=0 ; i < 32; i++) begin 
     if ( i >=0  & i < 8 )  
       irq_lvl[i] = 8;
     else if ( i >=8 & i < 16)  
       irq_lvl[i] = 8;
     else if ( i>= 16 & i < 24)  
        irq_lvl[i] = 8;
     else 
        irq_lvl[i] = 15;
   end
   //update lvl

   #1;

   @(posedge clk);
   
   irq_i = 32'h0;

   for (int i=1 ; i < 32; i++) begin 
    irq_i[i] = 1'b1;
   end

   for (int i=0 ; i < 32; i++) begin 
     if ( i >=0  & i < 8 )  
       irq_lvl[i] = 8;
     else if ( i >=8 & i < 16)  
       irq_lvl[i] = 24;
     else if ( i>= 16 & i < 24)  
        irq_lvl[i] = 8;
     else 
        irq_lvl[i] = 15;
   end

   #1;

   @(posedge clk);



   $finish;
   

end

plic_irq_arb
#(.NUM_IRQ(32),
  .ID_BASE(32),
  .PRIO_BIT(5),
  .ID_WIDTH(6)
 ) dut
(
  
  .irq_i     (irq_i ),             
  .irq_en_i  (irq_en ),
  .irq_pri_i (irq_lvl ),
  .irq_o     (arb_irq ), //irq 
  .irq_id_o  (arb_irq_id ),
  .irq_pri_o (arb_irq_lvl )

);


 
endmodule

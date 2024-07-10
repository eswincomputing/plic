// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */
module plic_tb 
(


);

localparam src0_priv  = 32'hC000_0000;
localparam src1_priv  = 32'hC000_0004;
localparam src2_priv  = 32'hC000_0008;
localparam src3_priv  = 32'hC000_000C;
localparam src4_priv  = 32'hC000_0010;
localparam src5_priv  = 32'hC000_0014;
localparam src6_priv  = 32'hC000_0018;
localparam src7_priv  = 32'hC000_001C;
localparam src8_priv  = 32'hC000_0020;
localparam src9_priv  = 32'hC000_0024;
localparam src10_priv = 32'hC000_0028;
localparam src11_priv = 32'hC000_002C;
localparam src12_priv = 32'hC000_0030;
localparam src13_priv = 32'hC000_0034;
localparam src14_priv = 32'hC000_0038;
localparam src15_priv = 32'hC000_003C;
localparam src16_priv = 32'hC000_0040;
localparam src17_priv = 32'hC000_0044;
localparam src18_priv = 32'hC000_0048;
localparam src19_priv = 32'hC000_004C;

localparam int_pending0 = 32'hC000_1000;
localparam int_pending1 = 32'hC000_1004;

localparam hart0_inten_0 = 32'hC000_2000;
localparam hart0_inten_1 = 32'hC000_2004;



localparam hart0_mthreshold   = 32'hC020_0000;
localparam hart0_mclaim       = 32'hC020_0004;

localparam hart0_sthreshold   = 32'hC020_1000;
localparam hart0_sclaim       = 32'hC020_1004;

logic apb_clk;
logic rst_n;
logic        psel       ;
logic        penable    ;
logic        pwrite     ;
logic [31:0] paddr      ;
logic [31:0] pwdata     ;
logic [31:0] prdata     ;
logic        pready     ;
logic        pslv_err   ;
logic [2:0]  pprot      ;
logic [3:0]  pstrb      ;
logic [47:1] global_int;
logic [3:0] hart_mmode_irq_o;
logic [3:0] hart_smode_irq_o;


logic [31:0] rdata;

initial forever #10 apb_clk = ~ apb_clk;


initial 
begin
   apb_clk = 1'b0;
   rst_n =1'b0;
   psel       = 0;
   penable    = 0;
   pwrite     = 0;
   paddr      = 0;
   pwdata     = 0;
   pprot      = 0;
   pstrb      = 4'hf;
   global_int = 0;
   
   #100
   rst_n =1'b1;
   @(posedge apb_clk);
   apb_read(src0_priv,rdata );
   apb_write(src0_priv,3 );
   apb_read(src0_priv,rdata );
   
   apb_read(src1_priv,rdata );
   apb_write(src1_priv,5 );
   apb_read(src1_priv,rdata ); 

   apb_write(src2_priv,5 );
   
   apb_write(src3_priv,6 );
   
   apb_write(src4_priv,6 );
   
   apb_write(src5_priv,7 );
   
   apb_write(src6_priv,7 );
   
   apb_write(src7_priv,3 );
   
   apb_write(src8_priv,3 );
   
   
   apb_write(hart0_inten_0,8'hff );
   
   // raise interrupt
   global_int[8:1] = 8'b1100_0010;
    
   repeat (5) @(posedge apb_clk);
   
   global_int[8:1] = 8'b0000_0000;
   
   repeat (2) @(posedge apb_clk);
   
   apb_read(int_pending0,rdata );
   
   apb_write(hart0_mthreshold, 2 );
   
   apb_read(hart0_mclaim,rdata ); //winner is interrupt 2
   
   repeat (2) @(posedge apb_clk);
   
   apb_write(hart0_mclaim,2 ); //write 2 to complete
   
   repeat (2) @(posedge apb_clk);
   

   repeat(30) @(posedge apb_clk);
   $finish;
   

end

logic [0:0] harts_did [4];
logic [3:0] hart_mexg_irq;

assign harts_did[0] =0;
assign harts_did[1] =0;
assign harts_did[2] =0;
assign harts_did[3] =0;




plic_top
#(.NUM_HART(4),
  .NUM_DOMAIN(2),      
  .NUM_IRQ(48),
  .ADDR_WIDTH(32),
  .DATA_WIDTH(32),
  .PRIO_BIT(5),
  .MEM_ADDR_WIDTH(26),
  .UNIT_IRQ_NUM(32),
  .IRQ_STAGING(1) 
 ) dut
(
  .pclk_i             (apb_clk          ),
  .prst_n_i           (rst_n            ),
  .test_mode_i        (1'b1             ),                                                                                                                                     
  .psel_i             (psel             ),
  .penable_i          (penable          ),
  .pwrite_i           (pwrite           ),
  .paddr_i            (paddr            ),
  .pwdata_i           (pwdata           ),                                                     
  .prdata_o           (prdata           ),
  .pready_o           (pready           ),
  .pslv_err_o         (pslv_err         ),                                                      
  .pprot_i            (pprot            ), // pprot[0] =0 normal, =1 privilege                                                          // pprot[1] =0 sec,    =1 nonse                                                        // pprot[2] =0 data  , =1 code                                               
  .acc_did_i          ('0               ),
  .harts_did_i        (harts_did        ),
  .pstrb_i            (pstrb            ),                                            
  .global_interrupt_i (global_int       ), 
  .hart_mmode_irq_o   (hart_mmode_irq_o ), //hart machine mode interrupt
  .hart_smode_irq_o   (hart_smode_irq_o ),//hart supervisor mode interrupt
  .hart_mexg_irq_o    (hart_mexg_irq)

);

 task apb_write(input [31:0] addr, input [31:0] data);
        @(posedge apb_clk);
            psel     =  1'b1     ;
            penable  =  1'b0     ;
            pwrite   =  1'b1     ;
            paddr    =  addr     ;
            pwdata   =  data     ;
        @(negedge apb_clk);
 
        @(posedge apb_clk);
            penable  =  1'b1     ;
        @(negedge apb_clk);
        
        @(posedge apb_clk);
        while(pready != 1'b1) @(posedge apb_clk);
            psel     =  1'b0     ;
            penable  =  1'b0     ;
            pwrite   =  1'b0     ;
            paddr    =  32'b0    ;
            pwdata   =  32'b0    ;
        repeat (10) @(posedge apb_clk);
 endtask //apb_write


task apb_read(input [31:0] addr, output [31:0] data);
    @(posedge apb_clk);
        psel     =  1'b1     ;
        penable  =  1'b0     ;
        pwrite   =  1'b0     ;
        paddr    =  addr     ;
    @(negedge apb_clk);

    @(posedge apb_clk);
        penable  =  1'b1     ;
    @(negedge apb_clk);

    @(posedge apb_clk); 
    while(pready != 1'b1) @(posedge apb_clk);
        data     =  prdata     ;
        psel     =  1'b0     ;
        penable  =  1'b0     ;
        pwrite   =  1'b0     ;
        paddr    =  32'b0    ;
    repeat (10) @(posedge apb_clk);
endtask //apb_read
 

 
endmodule

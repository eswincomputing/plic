// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */
module plic_top
#(parameter NUM_HART  =4, NUM_DOMAIN=4, NUM_IRQ=`PLIC_INT_NUM + 16 , ADDR_WIDTH=32, DATA_WIDTH=32, PRIO_BIT=`PLIC_PRIO_BIT, MEM_ADDR_WIDTH=26, UNIT_IRQ_NUM=32, IRQ_STAGING=1,
   DOMAIN_W = (NUM_DOMAIN==1) ? 1 : $clog2(NUM_DOMAIN)                 
  //IRQ_STAGING =0 or 1. 1 means insert 1 stage flop in arb tree. 0 means 0
 )
(

  input  logic                      pclk_i             ,
  input  logic                      prst_n_i           ,
  input  logic                      test_mode_i        ,
                                                       
   //APB4 interface                                                                               
  input  logic                      psel_i             ,
  input  logic                      penable_i          ,
  input  logic                      pwrite_i           ,
  input  logic [ADDR_WIDTH-1:0]     paddr_i            ,
  input  logic [DATA_WIDTH-1:0]     pwdata_i           ,
  input  logic [DOMAIN_W-1:0]       acc_did_i     ,  // access domain id
  input  logic [DOMAIN_W-1:0]       harts_did_i [NUM_HART],  // current harts domain id
                                                       
  output  logic [DATA_WIDTH-1:0]    prdata_o           ,
  output  logic                     pready_o           ,
  output  logic                     pslv_err_o         ,
                                                       
  input   logic [2:0]               pprot_i            , // pprot[0] =0 normal, =1 privilege  
                                                         // pprot[1] =0 sec,    =1 nonsec
                                                         // pprot[2] =0 data  , =1 code       
                                                         // pprot[1:0] = 2'b11 machine mode, 2'b01= supervisor mode, 2'b00 = user mode.                                                          
  input   logic [DATA_WIDTH/8-1:0]  pstrb_i            ,                                            
  
  input  logic  [NUM_IRQ-1:1]       global_interrupt_i , 
  //interrupt inputs and outputs
  output  logic [NUM_HART-1:0]        hart_mmode_irq_o , //hart machine mode interrupt
  output  logic [NUM_HART-1:0]        hart_smode_irq_o , //hart supervisor mode interrupt
  `ifdef RVFI
  output  logic [$clog2(NUM_IRQ)-1:0] rvfi_hart_mmode_irq_id  [NUM_HART] , //hart machine mode interrupt id , used for trace purpose 
  output  logic [$clog2(NUM_IRQ)-1:0] rvfi_hart_smode_irq_id  [NUM_HART][NUM_DOMAIN] , //hart supervisor mode interrupt id , used for trace purpose 
  `endif
  output  logic [NUM_HART-1:0]        hart_mexg_irq_o    //hart supervisor exchange interrupt                                ,

);

logic acc_err;
logic pri_acc;
logic sec_acc;
logic data_acc;
logic mem_csb ;
logic [MEM_ADDR_WIDTH-1:0] mem_addr;
logic                      mem_rwb ;
logic [DATA_WIDTH/8-1:0]   mem_wm     ;
logic [DATA_WIDTH-1:0]     mem_wdata;
logic [DATA_WIDTH-1:0]     mem_rdata;
logic [1:0]                acc_priv_mode ; 
logic [DOMAIN_W-1:0]       acc_did  ;
logic [NUM_DOMAIN-1:0]     hart_smode_irq [NUM_HART]; //hart supervisor mode interrupt
logic [NUM_IRQ-1:0]        global_interrupt;
logic                      gated_clk;

assign global_interrupt[0] = 1'b0;
assign global_interrupt[NUM_IRQ-1:1] = global_interrupt_i; 


apb2sram
#(.ADDR_WIDTH(ADDR_WIDTH),
  .DOMAIN_W(DOMAIN_W),
  .DATA_WIDTH(DATA_WIDTH), 
  .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
  .REG_INPUT(1)
 ) inst_bif
(
  .pclk_i      (pclk_i      ),
  .prst_n_i    (prst_n_i    ),
  .test_mode_i (test_mode_i ),                                  
  .psel_i      (psel_i      ),
  .acc_did_i   (acc_did_i   ), 
  .penable_i   (penable_i   ),
  .pwrite_i    (pwrite_i    ),
  .paddr_i     (paddr_i     ),
  .pwdata_i    (pwdata_i    ),           
  .prdata_o    (prdata_o    ),
  .pready_o    (pready_o    ),
  .pslv_err_o  (pslv_err_o  ),          
  .pprot_i     (pprot_i     ),                                             
  .pstrb_i     (pstrb_i     ),                                            
  .mem_rdy_i   (1'b1        ), 
  .error_i     (acc_err     ),
  .pri_acc_o   (pri_acc     ), 
  .sec_acc_o   (sec_acc     ),
  .data_acc_o  (data_acc    ),
  .mem_addr_o  (mem_addr    ),
  .mem_csb_o   (mem_csb     ), 
  .mem_rwb_o   (mem_rwb     ), 
  .mem_wm_o    (mem_wm      ), 
  .mem_wdata_o (mem_wdata   ),
  .acc_priv_mode_o (acc_priv_mode  ), 
  .acc_did_o       (acc_did        ), 
  .mem_rdata_i (mem_rdata   ),
  .gated_clk_o (gated_clk   )
);

//logic [NUM_IRQ-1:0]    int2arb                  ; //this is from interrupt detection logic outputs;
logic [NUM_IRQ-1:0]    hart_mint_en   [NUM_HART];
logic [PRIO_BIT-1:0]   int_pri_lvl    [NUM_IRQ-1:0] ; //this is from register file module.

logic [NUM_IRQ-1:0]    hart_sint_en   [NUM_HART][NUM_DOMAIN];

logic [PRIO_BIT-1:0]   hart_mint_th   [NUM_HART]; //core X interrupt machine mode threshold
logic [PRIO_BIT-1:0]   hart_sint_th   [NUM_HART][NUM_DOMAIN]; //core X interrupt supervisor mode threshold

logic [$clog2(NUM_IRQ)-1:0] hart_mmode_irq_id  [NUM_HART] ; //hart machine mode interrupt id
logic [PRIO_BIT-1:0]        hart_mmode_irq_lvl [NUM_HART] ; //hart machine mode interrupt lvl
                                                          
logic [$clog2(NUM_IRQ)-1:0] hart_smode_irq_id  [NUM_HART][NUM_DOMAIN] ; //hart supervisor mode interrupt id
logic [PRIO_BIT-1:0]        hart_smode_irq_lvl [NUM_HART][NUM_DOMAIN] ;//hart supervisor mode interrupt lvl

logic [NUM_IRQ-1:0]         int_pending                   ;
logic [NUM_IRQ-1:0]         irq_mask                      ;

generate 
genvar i;

for (i=0; i < NUM_HART; i++) 
begin : hart_mmode_int_arb  
  plic_irq_arb_tree
  #(.NUM_IRQ(NUM_IRQ),
    .PRIO_BIT(PRIO_BIT),
    .UNIT_IRQ_NUM(UNIT_IRQ_NUM),
    .STAGING(IRQ_STAGING)
   ) inst_m_irq_arb_tree
   //staging means that arb units output are registered and then arb. 
  (
  
    .clk_i         (pclk_i                 ) ,
    .rst_n_i       (prst_n_i               ) ,
    .test_mode_i   (test_mode_i            ) ,
    .irq_i         (int_pending            ) ,             
    .irq_en_i      (hart_mint_en[i]        ) , 
    .irq_th_i      (hart_mint_th[i]        ) ,  //interrupt threshold 
    .irq_pri_i     (int_pri_lvl            ) ,  //irq prio level array
    .irq_o         (hart_mmode_irq_o[i]    ) , //irq 
    .irq_id_o      (hart_mmode_irq_id[i]   ) ,
    .irq_pri_o     (hart_mmode_irq_lvl[i]  )
  
  );
end //for loop
endgenerate  


generate 
genvar m;
genvar n;

for (m=0; m < NUM_HART; m++)
begin : inst_hart
for (n=0; n < NUM_DOMAIN; n++)
begin: smode_domain_int_arb
  plic_irq_arb_tree
  #(.NUM_IRQ(NUM_IRQ),
    .PRIO_BIT(PRIO_BIT),
    .UNIT_IRQ_NUM(UNIT_IRQ_NUM),
    .STAGING(IRQ_STAGING)
   ) inst_s_irq_arb_tree
   //staging means that arb units output are registered and then arb. 
  (
  
    .clk_i         (pclk_i                  ) ,
    .rst_n_i       (prst_n_i                ) ,
    .test_mode_i   (test_mode_i             ) ,
    .irq_i         (int_pending             ) ,             
    .irq_en_i      (hart_sint_en[m][n]      ) , 
    .irq_th_i      (hart_sint_th[m][n]      ) ,  //interrupt threshold 
    .irq_pri_i     (int_pri_lvl             ) ,  //irq prio level array
    .irq_o         (hart_smode_irq[m][n]    ) , //irq 
    .irq_id_o      (hart_smode_irq_id[m][n] ) ,
    .irq_pri_o     (hart_smode_irq_lvl[m][n])
  
  );
end //for loopplic_top.sv
end
endgenerate 

logic [DOMAIN_W-1:0]   harts_did [NUM_HART] ;

always @(posedge pclk_i or negedge prst_n_i)
begin : harts_did_reg
  if(!prst_n_i) begin
    for (int i=0; i < NUM_HART; i++) begin 
      harts_did[i]  <= 0;
    end            
  end
  else begin
    for (int i=0; i < NUM_HART; i++) begin 
      harts_did[i] <= harts_did_i[i];
    end   
  end 
end 

logic [NUM_HART-1:0]  hart_smode_irq_d;

always_comb
begin : smode_irq_sel_proc
  for (int i=0; i < NUM_HART; i++) begin 
    hart_smode_irq_d[i] = 1'b0;
    for (int j=0; j < NUM_DOMAIN; j++) begin 
      if ( j == harts_did[i]) begin 
        hart_smode_irq_d[i] = hart_smode_irq[i][j];
      end      
    end 
  end 
end   

always @(posedge pclk_i or negedge prst_n_i)
begin : smode_irq_proc
  if(!prst_n_i) begin
    hart_smode_irq_o <= 0;
  end
  else begin
    hart_smode_irq_o <= hart_smode_irq_d;
  end 
end 


plic_reg_file
#(.NUM_HART(NUM_HART),
  .NUM_DOMAIN(NUM_DOMAIN), 
  .NUM_IRQ(NUM_IRQ),
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .PRIO_BIT(PRIO_BIT),
  .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
  .DOMAIN_W(DOMAIN_W)
 ) inst_regfile
(
  .free_running_clk_i   (pclk_i             ),
  .pclk_i               (gated_clk          ),
  .prst_n_i             (prst_n_i           ),
  .test_mode_i          (test_mode_i        ),
  .pri_acc_i            (pri_acc            ), //
  .sec_acc_i            (sec_acc            ),
  .data_acc_i           (data_acc           ),
  .mem_addr_i           (mem_addr           ),
  .acc_priv_mode_i      (acc_priv_mode      ), 
  .acc_did_i            (acc_did            ), 
  .harts_did_i          (harts_did          ),
  .mem_csb_i            (mem_csb            ), // '0' = memory selected;
  .mem_rwb_i            (mem_rwb            ), // '0' = rd, '1' =wr
  .mem_wm_i             (mem_wm             ), // the write data (byte) is masked out when wm[i] is low;
  .mem_wdata_i          (mem_wdata          ),
  .mem_rdata_o          (mem_rdata          ),
  .error_o              (acc_err            ),  
  .core_mint_en_o       (hart_mint_en       ),
  .core_sint_en_o       (hart_sint_en       ),
  .reg_int_pri_lvl_o    (int_pri_lvl        ),
  .int_pending_i        (int_pending        ),  //after sync
  .irq_mask_o           (irq_mask           ),
  .mint_arb_winner_id_i (hart_mmode_irq_id  ),  //winner id
  .sint_arb_winner_id_i (hart_smode_irq_id  ),  //winner id
  .reg_core_mint_th_o   (hart_mint_th       ), //core X interrupt machine mode threshold
  .reg_core_sint_th_o   (hart_sint_th       ),  //core X interrupt supervisor mode threshold
  .mexg_irq_o           (hart_mexg_irq_o    )
  
);


 plic_int_detect
#( .NUM_IRQ(NUM_IRQ), 
   .UNIT_IRQ_NUM(UNIT_IRQ_NUM)
 ) inst_int_det
(
  .clk_i        (pclk_i             ),
  .rst_n_i      (prst_n_i           ),
  .test_mode_i  (test_mode_i        ),
  .irq_i        (global_interrupt   ),             
  .irq_mask_i   (irq_mask           ),
  .irq_o        (int_pending        ) //irq 

);  

 `ifdef RVFI
 assign  rvfi_hart_mmode_irq_id = hart_mmode_irq_id ;
 assign  rvfi_hart_smode_irq_id = hart_smode_irq_id ;
 `endif

endmodule

// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module plic_hart_reg_file
#(parameter NUM_IRQ=1024, NUM_DOMAIN=16, HART_ID=0, DATA_WIDTH=32, PRIO_BIT=5, MEM_ADDR_WIDTH=14,
  DOMAIN_W = (NUM_DOMAIN==1) ? 1 : $clog2(NUM_DOMAIN)
 )
(

  input  logic                            free_running_clk_i    ,
  input  logic                            clk_i                 ,
  input  logic                            rst_n_i               ,
  input  logic                            test_mode_i           ,
                                                                
  input   logic                           pri_acc_i             , //
  input   logic                           sec_acc_i             ,
  input   logic                           data_acc_i            ,
  input   logic [1:0]                     acc_priv_mode_i       ,  // 2'b00 = machine mode, 2'b01 = supervisor mode;
  input   logic                           mmode_acc_en_i        ,
  input   logic                           smode_acc_en_i        ,
  input   logic                           smode_per_i           ,
  input   logic [DOMAIN_W-1:0]            acc_did_i             ,  // current harts domain id
  input   logic [DOMAIN_W-1:0]            hart_did_i            ,  // current harts domain id
  input   logic                           hart_acc_csb_i        ,
  input   logic [MEM_ADDR_WIDTH-1:0]      hart_acc_addr_i       ,
  input   logic                           hart_acc_rwb_i        , // '0' = rd, '1' =wr
  input   logic [DATA_WIDTH/8 - 1:0]      hart_acc_wm_i         , // the write data (byte) is masked out when wm[i] is low;
  input   logic [DATA_WIDTH-1:0]          hart_acc_wdata_i      ,
  output  logic [DATA_WIDTH-1:0]          hart_acc_rdata_o      ,
  output  logic                           error_o               ,
  
 
  output  logic [NUM_IRQ-1:0]             hart_mint_en_o         ,
  output  logic [NUM_IRQ-1:0]             hart_sint_en_o [NUM_DOMAIN] ,
  output  logic [NUM_IRQ-1:0]             hart_irq_mask_o             ,
  output  logic                           hart_mexg_irq_o             ,         
  
  input   logic [$clog2(NUM_IRQ)-1:0]     hart_mint_arb_winner_id_i    ,  //winner id
  input   logic [$clog2(NUM_IRQ)-1:0]     hart_sint_arb_winner_id_i  [NUM_DOMAIN]   ,  //winner id
  
  output  logic [PRIO_BIT-1:0]            hart_mint_th_o,
  output  logic [PRIO_BIT-1:0]            hart_sint_th_o [NUM_DOMAIN]
  //core X interrupt machine mode threshold
  
);
 
   logic [DATA_WIDTH-1:0]          m_rdata;
   logic [DATA_WIDTH-1:0]          s_rdata [NUM_DOMAIN]; 
   
   logic                           m_acc_err;
   logic [NUM_DOMAIN-1:0]          s_acc_err; 
   //logic                           mmode_acc_en_i;
   //logic                           smode_acc_en_i;
   
   logic [NUM_IRQ-1:0]             mirq_mask ;
   logic [NUM_IRQ-1:0]             sirq_mask [NUM_DOMAIN] ;
   
   logic  MEXG_Rd_Sel;
   logic  MEXG_Rd_Sel_del;
     
   logic [NUM_DOMAIN-1:0]          reg_mexg;
   logic [DATA_WIDTH-1:0]          mexg_rdata;
   logic [DATA_WIDTH-1:0]          mrg_srdata;
   
   
 
 //machine mode
 plic_base_reg_file
#( .NUM_IRQ(NUM_IRQ),
   .DATA_WIDTH(DATA_WIDTH),
   .PRIO_BIT(PRIO_BIT), 
   .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
   .HART_ID(HART_ID),
   .MMODE('1), //machine mode
   .DOMAIN_ID('0),
   .DOMAIN_W(DOMAIN_W)
 ) mmode_regfile
(
  .clk_i                     (clk_i                      ),
  .rst_n_i                   (rst_n_i                    ),
  .test_mode_i               (test_mode_i                ),
  .pri_acc_i                 (pri_acc_i                  ),
  .sec_acc_i                 (sec_acc_i                  ),
  .data_acc_i                (data_acc_i                 ),
  .acc_priv_mode_i           (acc_priv_mode_i            ),
  .mmode_acc_en_i            (mmode_acc_en_i             ),
  .smode_acc_en_i            (1'b0                       ),
  .smode_per_i               (1'b1                       ),
  .acc_did_i                 (acc_did_i                  ),
  .hart_did_i                (hart_did_i                 ),
  .hart_acc_csb_i            (hart_acc_csb_i             ),
  .hart_acc_addr_i           (hart_acc_addr_i            ),
  .hart_acc_rwb_i            (hart_acc_rwb_i             ),
  .hart_acc_wm_i             (hart_acc_wm_i              ),
  .hart_acc_wdata_i          (hart_acc_wdata_i           ),
  .hart_acc_rdata_o          (m_rdata                    ),
  .error_o                   (m_acc_err                  ),
  .irq_mask_o                (mirq_mask                  ),
  .hart_int_en_o             (hart_mint_en_o             ),
  .hart_int_arb_winner_id_i  (hart_mint_arb_winner_id_i  ),
  .hart_int_th_o             (hart_mint_th_o             ) 
  
);
  
generate 
genvar k;

for (k=0; k < NUM_DOMAIN; k++) begin :smode_domain_regfile 
//supervisor mode
 plic_base_reg_file
#( .NUM_IRQ(NUM_IRQ),
   .DATA_WIDTH(DATA_WIDTH),
   .PRIO_BIT(PRIO_BIT), 
   .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
   .HART_ID(HART_ID),
   .MMODE('0), //supervisor mode
   .DOMAIN_ID(k),
   .DOMAIN_W(DOMAIN_W)
 ) smode_domain_reg
(
  .clk_i                     (clk_i                      ),
  .rst_n_i                   (rst_n_i                    ),
  .test_mode_i               (test_mode_i                ),
  .pri_acc_i                 (pri_acc_i                  ),
  .sec_acc_i                 (sec_acc_i                  ),
  .data_acc_i                (data_acc_i                 ),
  .acc_priv_mode_i           (acc_priv_mode_i            ),
  .mmode_acc_en_i            (mmode_acc_en_i             ),
  .smode_acc_en_i            (smode_acc_en_i             ),
  .smode_per_i               (smode_per_i                ),
  .hart_did_i                (hart_did_i                 ),
  .acc_did_i                 (acc_did_i                  ),
  .hart_acc_csb_i            (hart_acc_csb_i             ),
  .hart_acc_addr_i           (hart_acc_addr_i            ),
  .hart_acc_rwb_i            (hart_acc_rwb_i             ),
  .hart_acc_wm_i             (hart_acc_wm_i              ),
  .hart_acc_wdata_i          (hart_acc_wdata_i           ),
  .hart_acc_rdata_o          (s_rdata[k]                 ),
  .error_o                   (s_acc_err[k]               ),
  .irq_mask_o                (sirq_mask[k]               ),
  .hart_int_en_o             (hart_sint_en_o[k]          ),
  .hart_int_arb_winner_id_i  (hart_sint_arb_winner_id_i[k]  ),
  .hart_int_th_o             (hart_sint_th_o[k]             ) 
  
);

end
endgenerate 
  
  logic  mexg_acc_err;
  logic  MEXG_Sel;

  assign error_o = mexg_acc_err | m_acc_err | ( | s_acc_err);
  assign MEXG_Rd_Sel  =  ((hart_acc_addr_i == ('h20_0008 + HART_ID * 'h2_0000) && ~ hart_acc_csb_i && ~hart_acc_rwb_i )) ? 1'b1 : 1'b0; 
  assign MEXG_Sel     =  ((hart_acc_addr_i == ('h20_0008 + HART_ID * 'h2_0000) && ~ hart_acc_csb_i )) ? 1'b1 : 1'b0; 

  //always_comb
  //begin : reg_mexg_proc
  //  reg_mexg    = 0;
  //  hart_mexg_irq_o  = 1'b0;       
  //  for (int i=0; i < NUM_DOMAIN; i++) begin
  //    reg_mexg[i] = (hart_sint_arb_winner_id_i[i] !=0 & hart_did_i !=i) ? 1'b1 : 1'b0; 
  //  end
  //  hart_mexg_irq_o  = | reg_mexg; 
  //end  

  assign  hart_mexg_irq_o  = | reg_mexg; 


  //always @(posedge clk_i or negedge rst_n_i) 
  always @(posedge free_running_clk_i or negedge rst_n_i) 
  begin : reg_mexg_proc
    if(!rst_n_i) begin
	   reg_mexg <= 1'b0;	  
	end
    else begin
       for (int i=0; i < NUM_DOMAIN; i++) begin
         reg_mexg[i] <= (hart_sint_arb_winner_id_i[i] !=0 & hart_did_i !=i) ? 1'b1 : 1'b0; 
       end
    end     
  end  
 
  always @(posedge clk_i or negedge rst_n_i)
  begin : mexg_sel_del
    if(!rst_n_i) begin
	   MEXG_Rd_Sel_del <= 1'b0;	  
       mexg_acc_err <= 1'b0;
	end
    else begin
      mexg_acc_err <= 1'b0;
      if (mmode_acc_en_i | smode_acc_en_i )
        MEXG_Rd_Sel_del <= MEXG_Rd_Sel ;
      else if  (MEXG_Sel)
        mexg_acc_err <= 1'b1;
    end     
  end
      
  
  assign mexg_rdata = ( {DATA_WIDTH{MEXG_Rd_Sel_del}} & {{(DATA_WIDTH-NUM_DOMAIN){1'b0}},reg_mexg});
  
  always_comb
  begin : rdata_proc
    mrg_srdata = 0;      
    for (int i=0; i < NUM_DOMAIN; i++) begin
      mrg_srdata = mrg_srdata | s_rdata[i]; 
    end 
  end  
  
  assign hart_acc_rdata_o = m_rdata | mrg_srdata | mexg_rdata;
  
  
  always_comb
  begin 
    hart_irq_mask_o = mirq_mask;
    for (int i=0; i < NUM_DOMAIN; i++) begin      
      hart_irq_mask_o = hart_irq_mask_o & sirq_mask[i]  ;
    end    
  end 
    
   
endmodule

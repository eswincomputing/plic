// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */
`define DEBUG 

module plic_reg_file
#(parameter NUM_HART  =4, NUM_DOMAIN=16, NUM_IRQ=1024, ADDR_WIDTH=32, DATA_WIDTH=32, PRIO_BIT=5, MEM_ADDR_WIDTH=19,
  DOMAIN_W = (NUM_DOMAIN==1) ? 1 : $clog2(NUM_DOMAIN)
 )
(

  input  logic                            free_running_clk_i    ,
  input  logic                            pclk_i                ,
  input  logic                            prst_n_i              ,
  input  logic                            test_mode_i           ,
                                                                
  input   logic                           pri_acc_i             , //
  input   logic                           sec_acc_i             ,
  input   logic                           data_acc_i            ,
  input   logic [1:0]                     acc_priv_mode_i       ,  // 2'b00 = machine mode, 2'b01 = supervisor mode;
  input   logic [DOMAIN_W-1:0]            acc_did_i             ,  // access domain id
  input   logic [DOMAIN_W-1:0]            harts_did_i [NUM_HART],  // current harts domain id
  input   logic [MEM_ADDR_WIDTH-1:0]      mem_addr_i            ,
  input   logic                           mem_csb_i             , // '0' = memory selected;
  input   logic                           mem_rwb_i             , // '0' = rd, '1' =wr
  input   logic [DATA_WIDTH/8 - 1:0]      mem_wm_i              , // the write data (byte) is masked out when wm[i] is low;
  input   logic [DATA_WIDTH-1:0]          mem_wdata_i           ,
  output  logic [DATA_WIDTH-1:0]          mem_rdata_o           ,
  output  logic                           error_o               ,
  
  input   logic [NUM_IRQ-1:0]             int_pending_i         ,   //after sync
  output  logic [NUM_IRQ-1:0]             irq_mask_o            ,   //mask out the claim interrupt till it is completed. when a mask bit is zero, it also clear corespoding irq pending bit 
  
  output  logic [NUM_IRQ-1:0]             core_mint_en_o [NUM_HART]                   ,
  output  logic [NUM_IRQ-1:0]             core_sint_en_o [NUM_HART][NUM_DOMAIN]       ,
  output  logic [PRIO_BIT-1:0]            reg_int_pri_lvl_o [NUM_IRQ-1:0]             ,
  output  logic [NUM_HART-1:0]            mexg_irq_o                                  ,
  
  input   logic [$clog2(NUM_IRQ)-1:0]     mint_arb_winner_id_i [NUM_HART]             ,  //winner id
  input   logic [$clog2(NUM_IRQ)-1:0]     sint_arb_winner_id_i [NUM_HART][NUM_DOMAIN] ,  //winner id
  
  output  logic [PRIO_BIT-1:0]            reg_core_mint_th_o [NUM_HART]               , //core X interrupt machine mode threshold
  output  logic [PRIO_BIT-1:0]            reg_core_sint_th_o [NUM_HART][NUM_DOMAIN]    //core X interrupt supervisor mode threshold
  
);
   localparam PENDING_BASE = 'h1000;
   localparam SMODE_PER    = 'h20_0FFC;
   localparam NUM_INTP_REG =  ((NUM_IRQ % DATA_WIDTH) == 0) ? NUM_IRQ/DATA_WIDTH : NUM_IRQ/DATA_WIDTH + 1;
   localparam INTP_REMAINING = NUM_IRQ % DATA_WIDTH;

   
   logic [NUM_IRQ-1:0]             hart_irq_mask [NUM_HART]    ;
   logic [NUM_HART-1:0]            smode_acc_en;
   logic                           mmode_acc_en;
   logic                           acc_permitted;
   //logic [NUM_HART-1:0]            hart_sel;
   //logic                           common_reg_sel;
   logic [DATA_WIDTH-1:0]          hart_rdata [NUM_HART];
   logic [NUM_HART-1:0]            hart_acc_err;
   logic [DATA_WIDTH-1:0]          prio_rdata ; 
   logic [DATA_WIDTH-1:0]          pending_rdata;
   logic [DATA_WIDTH-1:0]          smode_per_rdata;
   
   logic [DATA_WIDTH-1:0]          comm_reg_rdata;
   logic [NUM_INTP_REG-1:0]       Pending_Rd_Sel;
      
   logic [NUM_IRQ-1:0] PriLvl_Wr_Sel;
   logic [NUM_IRQ-1:0] PriLvl_Rd_Sel;

   logic               SPer_Wr_Sel;
   logic               SPer_Rd_Sel;
   logic               smode_per_s;
   logic               common_reg_acc_err;
   logic               common_reg_acc_err_r;

   //assign common_reg_sel  = (mem_addr_i[23:16] =='0) ? 1'b1 : 1'b0;

   
   assign error_o       =  common_reg_acc_err_r | (| hart_acc_err); 
     
   assign mmode_acc_en =  (acc_priv_mode_i == 2'b11); //acc_priv_mode_i= 0 indicate machine mode;
   
   //when access is suppervisor mode and its domain id equals current one of harts domain ID, then its access to corresponding suppervisor DOMAIN ID registers are enabled. 
   always_comb
   begin : smode_reg_acc_en_proc
     //smode_acc_en = 0;
     for (int i=0; i < NUM_HART; i++) begin 
       smode_acc_en[i] = (acc_priv_mode_i ==2'b01);
     end 
   end   

   
   
   generate 
   genvar k;
   
   for (k=0; k < NUM_HART; k++) begin : hart_regfile 
   plic_hart_reg_file
   #( .NUM_IRQ(NUM_IRQ),
      .NUM_DOMAIN(NUM_DOMAIN),
      .HART_ID(k),
      .DATA_WIDTH(DATA_WIDTH),
      .PRIO_BIT(PRIO_BIT), 
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
      .DOMAIN_W(DOMAIN_W)
    ) hart_reg_file
   (
   
     .free_running_clk_i           (free_running_clk_i         ),
     .clk_i                        (pclk_i                     ),
     .rst_n_i                      (prst_n_i                   ),
     .test_mode_i                  (test_mode_i                ),                                                               
     .pri_acc_i                    (pri_acc_i                  ), 
     .sec_acc_i                    (sec_acc_i                  ),
     .data_acc_i                   (data_acc_i                 ),
     .acc_did_i                    (acc_did_i                  ),
     .acc_priv_mode_i              (acc_priv_mode_i            ), 
     .mmode_acc_en_i               (mmode_acc_en               ),
     .smode_acc_en_i               (smode_acc_en[k]            ),
     .smode_per_i                  (smode_per_s                ),
     .hart_did_i                   (harts_did_i[k]             ), 
     .hart_acc_csb_i               (mem_csb_i                  ),
     .hart_acc_addr_i              (mem_addr_i                 ),
     .hart_acc_rwb_i               (mem_rwb_i                  ), 
     .hart_acc_wm_i                (mem_wm_i                   ), 
     .hart_acc_wdata_i             (mem_wdata_i                ),
     .hart_acc_rdata_o             (hart_rdata[k]              ),
     .error_o                      (hart_acc_err[k]            ), 
     .hart_mint_en_o               (core_mint_en_o[k]          ),
     .hart_sint_en_o               (core_sint_en_o[k]          ),
     .hart_irq_mask_o              (hart_irq_mask[k]           ),
     .hart_mexg_irq_o              (mexg_irq_o[k]              ),          
     .hart_mint_arb_winner_id_i    (mint_arb_winner_id_i[k]    ),  //winner id
     .hart_sint_arb_winner_id_i    (sint_arb_winner_id_i[k]    ),  //winner id
     .hart_mint_th_o               (reg_core_mint_th_o[k]      ),
     .hart_sint_th_o               (reg_core_sint_th_o[k]      )
     
   );
   end
   endgenerate


   always_comb
   begin 
     irq_mask_o = hart_irq_mask[0];
     for (int i=1; i < NUM_HART; i++) begin     
       irq_mask_o = irq_mask_o  & hart_irq_mask[i]; 
     end 
   end 

   //Prio Level registers handling  

   always_comb
   begin : PriLvlreg_sel_proc
     for (int i=0; i< NUM_IRQ; i++)
     begin
        PriLvl_Wr_Sel[i] =  ( mem_addr_i == 4*i & ~ mem_csb_i &   mem_rwb_i ) ? 1'b1 : 1'b0;
		PriLvl_Rd_Sel[i] =  ( mem_addr_i == 4*i & ~ mem_csb_i & ~ mem_rwb_i ) ? 1'b1 : 1'b0;
     end
   end
 
 
   assign reg_int_pri_lvl_o[0] = 0;

   always @(posedge pclk_i or negedge prst_n_i)
   begin : prio_regs_proc
     if(!prst_n_i) begin
	   for (int i=1; i< NUM_IRQ; i++) begin
		 reg_int_pri_lvl_o[i] <= 0;	
	   end	
	 end
     else begin
	   for (int i=1; i< NUM_IRQ; i++) begin 
         if ((mmode_acc_en | ((| smode_acc_en) & smode_per_s)) & PriLvl_Wr_Sel[i] & mem_wm_i[0]) begin   
           reg_int_pri_lvl_o[i] <= mem_wdata_i[PRIO_BIT-1:0] ;
	     end
	   end	 
	 end
   end 
  
   //Smode access permission register  

   always_comb
   begin : smode_perm_proc
     begin
        SPer_Wr_Sel =  (mem_addr_i == SMODE_PER & ~ mem_csb_i &   mem_rwb_i ) ? 1'b1 : 1'b0;
		SPer_Rd_Sel =  (mem_addr_i == SMODE_PER & ~ mem_csb_i & ~ mem_rwb_i ) ? 1'b1 : 1'b0;
     end
   end
 
 
   always @(posedge pclk_i or negedge prst_n_i)
   begin : smode_per_reg_proc
     if(!prst_n_i) begin
		smode_per_s <= 1'b0;	
	 end
     else begin
       if (mmode_acc_en && SPer_Wr_Sel && mem_wm_i[0]) begin   
         smode_per_s <= mem_wdata_i[0] ;
	   end
	 end
   end 

   assign smode_per_rdata =    {{(DATA_WIDTH-1){1'b0}}, SPer_Rd_Sel & smode_per_s};
 
   //interrupt pending register read selection

   always_comb
   begin : pending_reg_sel_proc
     for (int i=0; i < NUM_INTP_REG; i++) 
     begin
        Pending_Rd_Sel[i] =  (mem_addr_i == (PENDING_BASE + 4*i) && ~ mem_csb_i && ~ mem_rwb_i ) ? 1'b1 : 1'b0;
     end 
   end
   
   //access violation process
   //machine mode can write Priority level, Supervisor mode permission;
   //supervisor mode can read all common registers. 
   //otherwise, it give error. 

   assign common_reg_acc_err =   ~ mmode_acc_en &  SPer_Wr_Sel
                               | ( ~ (mmode_acc_en | ((| smode_acc_en) & smode_per_s)) & (| PriLvl_Wr_Sel))
                               | (~ (| smode_acc_en) & ~ mmode_acc_en) & ( (| PriLvl_Rd_Sel) | SPer_Rd_Sel |  ( |Pending_Rd_Sel)); 

   always @(posedge pclk_i or negedge prst_n_i)
   begin : acc_err_proc 
     if(!prst_n_i) begin
		common_reg_acc_err_r <= 1'b0;	
	 end
     else begin
        common_reg_acc_err_r <=  common_reg_acc_err;
	 end
   end 

   //common register read data process
 
   always @(posedge pclk_i or negedge prst_n_i)
   begin : rd_del_proc
     if(!prst_n_i) begin
		comm_reg_rdata <= '0;       
	 end
     else begin
        if ( ~common_reg_acc_err)
	      comm_reg_rdata  <= prio_rdata | pending_rdata | smode_per_rdata ;       
        else 
          comm_reg_rdata <= 0;
	 end
   end 
   
   always_comb
   begin : prio_rdata_proc
      prio_rdata = 0 ;
      for (int m=0; m < NUM_IRQ; m++) begin 
        prio_rdata = prio_rdata | ( {DATA_WIDTH{PriLvl_Rd_Sel[m]}} &  {{(DATA_WIDTH-PRIO_BIT){1'b0}},reg_int_pri_lvl_o[m]} );
      end  
   end 
  
   generate
   if (INTP_REMAINING == 0) begin :INTP_RD1

     always_comb
     begin : pending_rdata_proc
        pending_rdata = 0 ;
        if ( | Pending_Rd_Sel) begin 
          for (int i=0; i < NUM_INTP_REG; i++) begin
            pending_rdata = pending_rdata | {DATA_WIDTH{Pending_Rd_Sel[i]}} & int_pending_i[i*DATA_WIDTH+:DATA_WIDTH];
         end
        end   
     end

   end else begin :INTP_RD2

    always_comb
    begin : pending_rdata_proc
      pending_rdata = 0 ;
       if ( | Pending_Rd_Sel) begin 
         for (int i=0; i < NUM_INTP_REG-1; i++) begin
           pending_rdata = pending_rdata | {DATA_WIDTH{Pending_Rd_Sel[i]}} & int_pending_i[i*DATA_WIDTH+:DATA_WIDTH];
        end
         pending_rdata = pending_rdata | { {DATA_WIDTH-INTP_REMAINING{1'b0}}, {INTP_REMAINING{Pending_Rd_Sel[NUM_INTP_REG-1]}} & int_pending_i[NUM_IRQ-1:DATA_WIDTH*(NUM_INTP_REG-1)]};
       end   
    end

   end// generate else 
   endgenerate

   //always_comb
   //begin : pending_rdata_proc
   //  pending_rdata = 0 ;
   //   if ( | Pending_Rd_Sel) begin 
   //     for (int i=0; i < NUM_IRQ/DATA_WIDTH; i++) begin
   //       pending_rdata = pending_rdata | {DATA_WIDTH{Pending_Rd_Sel[i]}} & int_pending_i[i*DATA_WIDTH+:DATA_WIDTH];
   //    end
   //   end   
   //end
   
   always_comb
   begin : mem_rdata_proc
     mem_rdata_o = comm_reg_rdata ;
     for (int m=0; m < NUM_HART; m++) begin 
       mem_rdata_o = mem_rdata_o | hart_rdata[m];
     end  
   end 
   
   
endmodule   

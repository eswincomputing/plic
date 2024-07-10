// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module plic_base_reg_file
#(parameter NUM_IRQ=1024, DATA_WIDTH=32, PRIO_BIT=5, MEM_ADDR_WIDTH=14, HART_ID=0, MMODE =1'b1, DOMAIN_ID =0, 
  DOMAIN_W =4
 )
(

  input  logic                            clk_i                 ,
  input  logic                            rst_n_i               ,
  input  logic                            test_mode_i           ,
                                                                
  input   logic                           pri_acc_i             , //
  input   logic                           sec_acc_i             ,
  input   logic                           data_acc_i            ,
  input   logic [1:0]                     acc_priv_mode_i       ,  // 2'b00 = machine mode, 2'b01 = supervisor mode;
  input   logic                           mmode_acc_en_i        ,  //access en (machine mode or supervisor mode
  input   logic                           smode_acc_en_i        ,  //access en (machine mode or supervisor mode
  input   logic                           smode_per_i           ,  //access en (machine mode or supervisor mode
  input   logic [DOMAIN_W-1:0]            hart_did_i            ,  // current harts domain id
  input   logic [DOMAIN_W-1:0]            acc_did_i             ,  // current harts domain id
  input   logic                           hart_acc_csb_i        ,
  input   logic [MEM_ADDR_WIDTH-1:0]      hart_acc_addr_i       ,
  input   logic                           hart_acc_rwb_i        , // '0' = rd, '1' =wr
  input   logic [DATA_WIDTH/8 - 1:0]      hart_acc_wm_i         , // the write data (byte) is masked out when wm[i] is low;
  input   logic [DATA_WIDTH-1:0]          hart_acc_wdata_i      ,
  output  logic [DATA_WIDTH-1:0]          hart_acc_rdata_o      ,
  output  logic                           error_o               ,
  
  output  logic [NUM_IRQ-1:0]             irq_mask_o            ,   //mask out the claim interrupt till it is completed. when a mask bit is zero, it also clear corespoding irq pending bit 
  
  output  logic [NUM_IRQ-1:0]             hart_int_en_o         ,
        
  
  input   logic [$clog2(NUM_IRQ)-1:0]     hart_int_arb_winner_id_i    ,  //winner id
  
  output  logic [PRIO_BIT-1:0]            hart_int_th_o                //core X interrupt machine mode threshold
  
);
   
   localparam EN_OFFSET = (MMODE == 1) ? 'h2000 + HART_ID * 'h1000     : 'h2080 + HART_ID * 'h1000 + DOMAIN_ID * 'h80;
   localparam TH_OFFSET = (MMODE == 1) ? 'h20_0000 + HART_ID * 'h2_0000 : 'h20_1000 + HART_ID * 'h2_0000 + DOMAIN_ID * 'h1000;
   localparam NUM_INTEN_REG =  ((NUM_IRQ % DATA_WIDTH) == 0) ? NUM_IRQ/DATA_WIDTH : NUM_IRQ/DATA_WIDTH + 1;
   localparam INTEN_REMAINING = NUM_IRQ % DATA_WIDTH;

   logic [DATA_WIDTH-1:0]           masked_wdata;

   logic [NUM_IRQ-1:0]              hart_int_mask ;
   logic [NUM_IRQ-1:0]              reg_core_int_en;
   
   logic [NUM_INTEN_REG-1:0] IntEn_Wr_Sel;
   logic [NUM_INTEN_REG-1:0] IntEn_Rd_Sel;
   logic                            TH_Wr_Sel;
   logic                            TH_Rd_Sel;
   logic                            CLAIM_Wr_Sel;
   logic                            CLAIM_Rd_Sel;
   //logic                            MEXG_Wr_Sel;
   //logic                            MEXG_Rd_Sel;
   logic [NUM_INTEN_REG-1:0] IntEn_Wr_Sel_tmp;
   logic [NUM_INTEN_REG-1:0] IntEn_Rd_Sel_tmp;
   logic                            TH_Wr_Sel_tmp   ;
   logic                            TH_Rd_Sel_tmp   ;
   logic                            CLAIM_Wr_Sel_tmp;
   logic                            CLAIM_Rd_Sel_tmp;
 
   //logic [(NUM_IRQ-1)/DATA_WIDTH:0] IntEn_Rd_Sel_r;  
   //logic                            TH_Rd_Sel_r;
   //logic                            CLAIM_Rd_Sel_r;
   //logic                            MEXG_Rd_Sel_r;
   
   logic [DATA_WIDTH-1:0]           inten_rdata;
   logic [DATA_WIDTH-1:0]           th_rdata ; //HART machine threshold
   logic [DATA_WIDTH-1:0]           claim_rdata ; //all hart mclaim 
   
   
   //logic [NUM_DOMAIN-1:0]           hart_smode_mexg;  //these are from number of smode_mexg outputs. 
   
    logic acc_per_err;

    // when not access right, there is register write and read, it reports err;
    // when there is access right, but there is no smode permission, it reports err;

    // Int_enable register write need permission, smode_acc_en_i,  smode_per, no need for domain_id match.  
    // Int_enable register read does not need smode_per, no need domain_id match
    // the other registers (threshold, claim/complete registers)  write/read access need smode_acc_en & acc_did == domain_id.  no need for smode_per. 


assign acc_per_err =       ( ~ (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)  & smode_per_i) & ( | IntEn_Wr_Sel_tmp))
                         | ( ~ (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)) & ( TH_Rd_Sel_tmp | CLAIM_Rd_Sel_tmp | TH_Wr_Sel_tmp | CLAIM_Wr_Sel_tmp  | (| IntEn_Rd_Sel_tmp) ));   

    assign    TH_Wr_Sel_tmp    =  (hart_acc_addr_i == TH_OFFSET) & ~ hart_acc_csb_i &  hart_acc_rwb_i  ? 1'b1 : 1'b0;
	assign    TH_Rd_Sel_tmp    =  (hart_acc_addr_i == TH_OFFSET) & ~ hart_acc_csb_i & ~hart_acc_rwb_i  ? 1'b1 : 1'b0;
     
    assign    CLAIM_Wr_Sel_tmp =  (hart_acc_addr_i == TH_OFFSET + 'h4) & ~ hart_acc_csb_i &  hart_acc_rwb_i  ? 1'b1 : 1'b0;
	assign    CLAIM_Rd_Sel_tmp =  (hart_acc_addr_i == TH_OFFSET + 'h4) & ~ hart_acc_csb_i & ~hart_acc_rwb_i  ? 1'b1 : 1'b0;

    assign    TH_Wr_Sel    =  (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)) & TH_Wr_Sel_tmp;
	assign    TH_Rd_Sel    =  (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)) & TH_Rd_Sel_tmp;
     
    assign    CLAIM_Wr_Sel =  (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)) & CLAIM_Wr_Sel_tmp;
	assign    CLAIM_Rd_Sel =  (mmode_acc_en_i | smode_acc_en_i & (acc_did_i == DOMAIN_ID)) & CLAIM_Rd_Sel_tmp;
   
   always @(posedge clk_i or negedge rst_n_i)
   begin : acc_err_proc
     if(!rst_n_i) begin
	    error_o <= '0;	       
	 end
     else begin
        error_o <= acc_per_err;        
	 end
   end 
   


   always_comb
   begin : IntEn_sel_proc
       for (int i=0; i < NUM_INTEN_REG; i++) 
       begin
	  	  IntEn_Rd_Sel_tmp[i] =  (hart_acc_addr_i == EN_OFFSET + 4*i) & ~ hart_acc_csb_i &  ~ hart_acc_rwb_i ? 1'b1 : 1'b0;
          IntEn_Wr_Sel_tmp[i] =  (hart_acc_addr_i == EN_OFFSET + 4*i) & ~ hart_acc_csb_i &    hart_acc_rwb_i ? 1'b1 : 1'b0;
    	  IntEn_Rd_Sel[i] =  (mmode_acc_en_i | smode_acc_en_i  & (acc_did_i == DOMAIN_ID) ) & IntEn_Rd_Sel_tmp[i];
          IntEn_Wr_Sel[i] =  (mmode_acc_en_i | smode_acc_en_i  & (acc_did_i == DOMAIN_ID) & smode_per_i) & IntEn_Wr_Sel_tmp[i];

       end 
   end
 
        
   always_comb
   begin : mem_wdata_mask
     for (int i=0; i < (DATA_WIDTH/8); i++) begin 
       masked_wdata[i*8+:8] = hart_acc_wdata_i[i*8+:8] & {8{hart_acc_wm_i[i]}};
     end 
   end   
 
   generate
   if (INTEN_REMAINING == 0) begin : INTEN_WR_1

     always @(posedge clk_i or negedge rst_n_i)
     begin : inten_regs_proc
       if(!rst_n_i) begin
          reg_core_int_en <= '0;	       
       end
       else begin
         for (int i=0; i < NUM_INTEN_REG ; i++) begin
           if (IntEn_Wr_Sel[i]) begin   
             for (int j=0; j < (DATA_WIDTH/8); j++) begin 
               if (hart_acc_wm_i[j])
                  reg_core_int_en[i*DATA_WIDTH+j*8+:8]    <=  hart_acc_wdata_i[j*8+:8];
             end //for j     
           end//if
         end //for i           
         //IRQ 0 enable bit is tied to zero according to the spec.
         reg_core_int_en[0] <= 1'b0;        
       end //else
     end //always begin 

  end else begin : INTEN_WR_2

     always @(posedge clk_i or negedge rst_n_i)
     begin : inten_regs_proc
       if(!rst_n_i) begin
          reg_core_int_en <= '0;	       
       end
       else begin
         for (int i=0; i < NUM_INTEN_REG-1 ; i++) begin
           if (IntEn_Wr_Sel[i]) begin   
             for (int j=0; j < (DATA_WIDTH/8); j++) begin 
               if (hart_acc_wm_i[j])
                 reg_core_int_en[i*DATA_WIDTH+j*8+:8]    <=  hart_acc_wdata_i[j*8+:8];
             end     
           end//if
         end //for i                 
         if (IntEn_Wr_Sel[NUM_INTEN_REG-1]) begin 
           for (int w=0; w < INTEN_REMAINING; w++) begin 
             reg_core_int_en[(NUM_INTEN_REG-1)*DATA_WIDTH+w]    <=  hart_acc_wdata_i[w] & hart_acc_wm_i[w/8]  ;
           end //for w
         end //if
         //IRQ 0 enable bit is tied to zero according to the spec.
         reg_core_int_en[0] <= 1'b0;        
      end //else
     end  
   end    
  endgenerate

   
   always @(posedge clk_i or negedge rst_n_i)
   begin : mint_claim_complete_mask_proc
     if(!rst_n_i) begin
	     hart_int_mask <= {NUM_IRQ{1'b1}};	     
	 end
     else begin
	   //machine mode int mask
	   if (CLAIM_Rd_Sel ) begin   
         hart_int_mask[hart_int_arb_winner_id_i] <= 1'b0; 
	   end
       if (CLAIM_Wr_Sel ) begin   
         if ( masked_wdata < NUM_IRQ)  begin
           hart_int_mask[masked_wdata] <= 1'b1;
         end  
	   end         
	 end
   end 

   assign hart_int_en_o =reg_core_int_en & hart_int_mask;
   
   assign irq_mask_o    = hart_int_mask;
   
   
   always @(posedge clk_i or negedge rst_n_i)
   begin : mthresh_reg_wr_proc
     if(!rst_n_i) begin
		 hart_int_th_o <= 0;	  
	 end
     else begin
	   if (TH_Wr_Sel & hart_acc_wm_i[0]) begin  
         hart_int_th_o <= hart_acc_wdata_i[PRIO_BIT-1:0] & {PRIO_BIT{hart_acc_wm_i[0]}};  //assum PRIO_BIT is less then 8 bits;
	   end
     end       
   end 
  
   always @(posedge clk_i or negedge rst_n_i)
   begin : rdata_proc
     if(!rst_n_i) begin
	   hart_acc_rdata_o <= '0;	  
	 end
     else begin
       hart_acc_rdata_o <= th_rdata | claim_rdata  | inten_rdata  ;
     end     
   end     
 
   generate
   if (INTEN_REMAINING == 0) begin :INTEN_RD1

      always_comb
      begin : minten_rd_proc
         inten_rdata = '0 ;
         if ( | IntEn_Rd_Sel) begin 
           for (int i=0; i < NUM_INTEN_REG; i++) begin  
              inten_rdata = inten_rdata | {DATA_WIDTH{IntEn_Rd_Sel[i]}} & reg_core_int_en[i*DATA_WIDTH+:DATA_WIDTH] ;
           end //for i 
         end //if   
      end //always

   end else begin :INTEN_RD2

      always_comb
      begin : minten_rd_proc
        inten_rdata = '0 ;
        if ( | IntEn_Rd_Sel) begin 
           for (int i=0; i < NUM_INTEN_REG-1; i++) begin  
              inten_rdata = inten_rdata | {DATA_WIDTH{IntEn_Rd_Sel[i]}} & reg_core_int_en[i*DATA_WIDTH+:DATA_WIDTH] ;
           end //for i 
           inten_rdata = inten_rdata | { {DATA_WIDTH-INTEN_REMAINING{1'b0}}, {INTEN_REMAINING{IntEn_Rd_Sel[NUM_INTEN_REG-1]}} & reg_core_int_en[NUM_IRQ-1:DATA_WIDTH*(NUM_INTEN_REG-1)]};
        end //if   
      end//always

   end// generate else 
   endgenerate

   assign th_rdata    =  ( {DATA_WIDTH{TH_Rd_Sel}} &  {{(DATA_WIDTH-PRIO_BIT){1'b0}},hart_int_th_o});
   assign claim_rdata =  ( {DATA_WIDTH{CLAIM_Rd_Sel}} &  {{(DATA_WIDTH-$clog2(NUM_IRQ)){1'b0}},hart_int_arb_winner_id_i} );
   
   
   //assign hart_acc_rdata_o =  th_rdata | claim_rdata  | inten_rdata  ;
   
   
endmodule

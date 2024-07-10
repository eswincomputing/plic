// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */
module apb2sram
#(parameter ADDR_WIDTH  =32, DOMAIN_W=1, DATA_WIDTH=32, MEM_ADDR_WIDTH=13, REG_INPUT=1
 )
(
  input  logic                      pclk_i      ,
  input  logic                      prst_n_i    ,
  input  logic                      test_mode_i ,
                                              
  //APB4 interface                            
                                              
  input  logic                      psel_i   ,
  input  logic                      penable_i,
  input  logic                      pwrite_i ,
  input  logic [ADDR_WIDTH-1:0]     paddr_i  ,
  input  logic [DATA_WIDTH-1:0]     pwdata_i ,
  input  logic [DOMAIN_W-1:0]       acc_did_i             ,  // access domain id
                                              
  output  logic [DATA_WIDTH-1:0]    prdata_o  ,
  output  logic                     pready_o  ,
  output  logic                     pslv_err_o,
                                              
  input   logic [2:0]               pprot_i   , // pprot[0] =0 normal, =1 privilege 
                                                // pprot[1] =0 sec,    =1 nonsec
                                                // pprot[2] =0 data  , =1 code                                               
  input   logic [DATA_WIDTH/8-1:0]  pstrb_i   ,                                            
  
  //memory interface
  input  logic                      mem_rdy_i , 
  input  logic                      error_i   ,
  output logic                      pri_acc_o , //
  output logic                      sec_acc_o ,
  output logic                      data_acc_o,
  output logic [MEM_ADDR_WIDTH-1:0] mem_addr_o,
  output logic                      mem_csb_o , // '0' = memory selected;
  output logic                      mem_rwb_o , // '0' = rd, '1' =wr
  output logic [DATA_WIDTH/8 - 1:0] mem_wm_o  , // the write data (byte) is masked out when wm[i] is low;
  output logic [DATA_WIDTH-1:0]     mem_wdata_o  ,
  input  logic [DATA_WIDTH-1:0]     mem_rdata_i  ,
  output  logic [1:0]               acc_priv_mode_o       ,  // 2'b11 = machine mode, 2'b01 = supervisor mode, 2'b00 = user mode;
  output  logic [DOMAIN_W-1:0]      acc_did_o ,                // access domain id
  output  logic                     gated_clk_o 

);
 
  typedef enum logic [1:0]  { IDLE=0, SETUP=1, ACCESS= 2} state_t; 
  
  state_t  cur_st, nxt_st;
  
    
  logic                      wr    ;
  logic [ADDR_WIDTH-1:0]     addr  ;
  logic [DATA_WIDTH-1:0]     wdata ;
  logic [1:0]                acc_priv_mode ;  // 0 = machine mode, 1 = supervisor mode;
  logic [DOMAIN_W-1:0]       acc_did       ;  // access domain id

  logic                      gated_clk;

  logic                      clk_en;

  assign  clk_en = (cur_st != IDLE | psel_i) ? 1'b1 : 1'b0;

  assign gated_clk_o = gated_clk;

   clkgate inst_clkgate
   (
     .out (gated_clk),
     .en  (clk_en   ),
     .test_en( test_mode_i),
     .in  (pclk_i)
   );


  always_comb
  begin :apb_fsm_comb
     nxt_st = cur_st;
     case(cur_st)
       IDLE :
          begin
            if (psel_i & ~ penable_i) begin 
              nxt_st = SETUP;
            end
          end 
       SETUP:
          begin
            if (psel_i & penable_i) begin 
              nxt_st = ACCESS;
            end              
          end
       ACCESS:
          begin
            if (pready_o == 1'b1) begin
              if (psel_i & ~ penable_i) begin 
                nxt_st = SETUP; 
              end
              else if (~psel_i & ~ penable_i) begin 
                nxt_st = IDLE; 
              end               
            end
          end            
     default : nxt_st = IDLE;                      
   endcase   
  end    


  always @(posedge gated_clk or negedge prst_n_i)    
  begin
    if (!prst_n_i)
      begin
        cur_st <= IDLE;
      end 
    else
      begin
        cur_st <= nxt_st; 
      end 
  end

  generate
  if (REG_INPUT) begin
    
    //logic ins_wait;
    
    always @(posedge gated_clk or negedge prst_n_i)    
    begin
      if (!prst_n_i)
        begin
          wr    <= 0;
          addr  <= 0;
          wdata <= 0;
          //ins_wait <= 0;
          acc_priv_mode <= 0;
          acc_did <= 0;
        end 
      else
        begin
          if (nxt_st == SETUP) begin 
            wr    <= pwrite_i;
            addr  <= paddr_i ;
            wdata <= pwdata_i;
            acc_priv_mode <= pprot_i[1:0];
            acc_did  <= acc_did_i;
          end 
          //ins_wait <= (nxt_st == SETUP) ? 1'b1 : 1'b0;
        end 
    end
    
    assign mem_csb_o   = (cur_st == SETUP & penable_i) ? 1'b0 : 1'b1;
    
    assign pready_o = (cur_st == SETUP & penable_i)  ? 1'b0 :
                      (cur_st == ACCESS) ? mem_rdy_i : 1'b1;
   
  end 
  else begin 
    assign wr    = pwrite_i;
    assign addr  = paddr_i ;
    assign wdata = pwdata_i;
    assign acc_priv_mode = pprot_i[1:0];
    assign acc_did       = acc_did_i;
    
    assign mem_csb_o   = (cur_st == SETUP & penable_i) ? 1'b0 : 1'b1;
    
    assign pready_o = (cur_st == SETUP & penable_i) ? mem_rdy_i : 1'b1;
    
  end 
  endgenerate 

    assign mem_addr_o  =  addr[MEM_ADDR_WIDTH-1:0] ;
    assign mem_rwb_o   =  wr;
    assign mem_wdata_o =  wdata;
    assign prdata_o    =  mem_rdata_i;
    assign acc_priv_mode_o = acc_priv_mode;
    assign acc_did_o       = acc_did;
    
    assign pslv_err_o  = (pready_o & cur_st == ACCESS & penable_i) ? error_i : 1'b0;
    

    
    assign mem_wm_o  = pstrb_i;
    assign pri_acc_o = pprot_i[0];
    assign sec_acc_o = ~pprot_i[1];
    assign data_acc_o = pprot_i[2];
   
  
endmodule

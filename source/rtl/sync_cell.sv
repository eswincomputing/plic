// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */


module sync_cell 
# (parameter DEPTH=2)
(
  input logic clk_i,
  input logic rst_n_i,
  input logic din,
  output logic dout
);

 logic [DEPTH-1:0] sync_ff;
 
always@(posedge clk_i or negedge rst_n_i)

  begin
    if (!rst_n_i)
       sync_ff <= '0;
    else
       sync_ff <= {sync_ff[DEPTH-2:0],din};
  end
  
  assign dout = sync_ff[DEPTH-1];
 
endmodule

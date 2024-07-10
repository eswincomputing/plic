// SPDX-License-Identifier: MPL-2.0
/*
 *
 * Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
 *
 */

module clkgate(
  output logic out,
  input  logic en,
  input  logic test_en,
  input  logic in
);


 `ifdef FPGA
    assign out = in;
 `else
    logic en_latched /*verilator clock_enable*/;

    always @(*) begin
       if (!in) begin
          en_latched = en || test_en;
       end
    end

    assign out = en_latched && in;
 `endif

endmodule

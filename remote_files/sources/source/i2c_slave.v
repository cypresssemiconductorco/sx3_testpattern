//////////////////////////////////////////////////////////////////////////////////
//	(c) 2020-2021, Cypress Semiconductor Corporation (an Infineon company) or an affiliate of Cypress Semiconductor Corporation.  All rights reserved.
//
//	This software, including source code, documentation and related materials ("Software") is owned by Cypress Semiconductor Corporation or one of its affiliates ("Cypress") and is protected by and subject to worldwide patent protection (United States and foreign), United States copyright laws and international treaty provisions.  Therefore, you may use this Software only as provided in the license agreement accompanying the software package from which you obtained this Software ("EULA").
//	If no EULA applies, Cypress hereby grants you a personal, non-exclusive, non-transferable license to copy, modify, and compile the Software source code solely for use in connection with Cypress's integrated circuit products.  Any reproduction, modification, translation, compilation, or representation of this Software except as specified above is prohibited without the express written permission of Cypress.
//
//	Disclaimer: THIS SOFTWARE IS PROVIDED AS-IS, WITH NO WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, NONINFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. Cypress reserves the right to make changes to the Software without notice. Cypress does not assume any liability arising out of the application or use of the Software or any product or circuit described in the Software. Cypress does not authorize its products for use in any products where a malfunction or failure of the Cypress product may reasonably be expected to result in significant property damage, injury or death ("High Risk Product"). By including Cypress's product in a High Risk Product, the manufacturer of such system or application assumes all risk of such use and in doing so agrees to indemnify Cypress against all liability.
//
// Design Name:		testptrn
// Module Name:		i2c_slave
// Target Devices:	LFE5U-45F-8BG381I
// Description: I2C Slave module acts as the interface between FPGA and SX3. This module has a set of registers that can be used by SX3 to control the functionality of the FPGA.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
`include "parameters.v"

`timescale 1ns/100ps

module i2c_slave (

	//	Global Inputs
   	input	clock_i,
	input	reset_n_i,

	//	Interface Inouts
	inout	sl_sda_io,
	inout	sl_scl_io,

	//	Control Signals
	output	slfifo_st_vidrst_o,
	output	slfifo_st_audrst_o,
	output	yuv_420_en,
	output	[15:0] img_wt_o,
	output	[15:0] img_ht_o,
	output	[31:0] img_size_o,
	output	interleaved_en_o,
	output	cam_app_en_o,
	output	aud_app_en_o,
	output	uvc_header_en_o,
	output	[15:0]	slfifo_uvc_buf_size_o,
	output	still_cap_en_o,
	output	[1:0] gpif_buf_wdt_o,
	output	cam_int_en_o
);

parameter [5:0]fpga_reg_ct   = 6'd40;
parameter [6:0]fpga_sl_addr  = 7'b0001101;
parameter fpga_major_version = 'h01;
parameter fpga_minor_version = 'h08;

//I2C Slave state
parameter [2:0]START_D = 3'b000;
parameter [2:0]SLAVE_D = 3'b001;
parameter [2:0]SL_ACK  = 3'b010;
parameter [2:0]ADDR_D  = 3'b011;
parameter [2:0]WRITE_D = 3'b100;
parameter [2:0]READ_D  = 3'b101;
parameter [2:0]STOP_D  = 3'b110;
parameter [2:0]MS_CLK  = 3'b111;

integer i;

reg [31:0] img_size='d0;
reg yuv_420_en_r1='d0;
reg yuv_420_en_r2='d0;
reg vid_en_r1='d0;
reg vid_en_r2='d0;
reg aud_en_r1='d0;
reg aud_en_r2='d0;
reg slfifo_st_vidrst1='d0;
reg slfifo_st_vidrst2='d0;
reg slfifo_st_audrst1='d0;
reg slfifo_st_audrst2='d0;
reg interleaved_en_r='d0;
reg [31:0] mult_out1='d0;
reg [31:0] mult_out2='d0;

wire start_bit;
wire stop_bit;
wire sclk;

reg sda;
reg sda_r1;
reg sda_r2;
reg scl_r1;
reg scl_r2;
reg rd_wr;
reg [7:0]fpga_reg[39:0];
reg [7:0]read_data;
reg [7:0]sclk_ct;
reg [4:0]read_ct;
reg [6:0]slave_addr;
reg [2:0]state;
reg [3:0]byte_ct;
reg [7:0]data_r;
reg [5:0]addr_r;
reg [15:0] addr;
reg [7:0]data;

reg cam_int_en_r1='d0;
reg cam_int_en_r2='d0;
reg cam_app_en_r1='d0;
reg cam_app_en_r2='d0;
reg uvc_header_en_r='d0;
reg aud_app_en_r1='d0;
reg aud_app_en_r2='d0;
reg [15:0]slfifo_uvc_buf_size1='d0;
reg [15:0]slfifo_uvc_buf_size2='d0;

localparam [7:0] INIT_GPIF_WDT=4;

wire [15:0] img_ht;
wire [15:0] img_wt;

reg [15:0] img_ht_r='d0;
reg [15:0] img_wt_r='d0;

reg [1:0] gpif_bud_wdt_r1='d0;
reg [1:0] gpif_bud_wdt_r2='d0;
reg still_cap_en_r1='d0;
reg still_cap_en_r2='d0;

assign sl_sda_io = sda ? 1'bz : 1'b0;
assign sl_scl_io = 1'bZ;


always @(posedge clock_i, negedge reset_n_i)
begin
	if(!reset_n_i)begin
		sda_r1 <= 1'b1;
		sda_r2 <= 1'b1;
	end
	else begin
		sda_r1 <= sl_sda_io;
		sda_r2 <= sda_r1;
	end
end
assign start_bit = ((!sda_r1)&(sda_r2)&(sl_scl_io));
assign stop_bit = ((sda_r1)&(!sda_r2)&(sl_scl_io));

always @(posedge clock_i, negedge reset_n_i)
begin
	if(!reset_n_i)begin
		scl_r1 <= 1'b1;
		scl_r2 <= 1'b1;
	end
	else begin
		scl_r1 <= ~sl_scl_io;
		scl_r2 <= scl_r1;
	end
end
assign sclk_r = (scl_r1)&(!scl_r2);
assign sclk_f = (!scl_r1)&(scl_r2);

always@(posedge clock_i, negedge reset_n_i)
begin
	if(!reset_n_i)begin
		sclk_ct <= 8'd0;
	end
	else if((stop_bit)||(start_bit))begin
		sclk_ct <= 8'd0;
	end
	else if((state == WRITE_D)||(state == READ_D))begin
		sclk_ct <= sclk_ct;
	end
	else if(sclk_r)begin
		sclk_ct <= sclk_ct + 1'b1;
	end
	else if((state == START_D)||(state == STOP_D))begin
		sclk_ct <= 8'd0;
	end
end
genvar gi;
always@(posedge clock_i, negedge reset_n_i)
	 begin
		if(!reset_n_i)begin
			state <= START_D;
			addr <= 'd0;
			data_r <= 8'd0;
			data <= 8'd0;
			read_data <= 8'd0;
			read_ct <= 5'd8;
			byte_ct <= 4'd0;
			addr_r <= 6'd0;
			sda <= 1'b1;
			slave_addr <= 7'd0;
			fpga_reg[0] <= 'd0;	//	DMA Channel reset
			fpga_reg[1] <= fpga_major_version;
			fpga_reg[2] <= fpga_minor_version;
			fpga_reg[9] <= 8'h00;	//	Video App En
			fpga_reg[10] <= 8'h00;	// Audio App En
			fpga_reg[11] <= 8'h00;	// UVC Header En
			fpga_reg[12] <= 8'hbf;	// UVC Buffer size
			fpga_reg[13] <= 8'hd0;
			fpga_reg[14] <= 8'h00;	// Still Capture En
			fpga_reg[15] <= INIT_GPIF_WDT;	// Bus width
			fpga_reg[33] <= 8'h04;	//	Image Height [Default - 1080]
			fpga_reg[34] <= 8'h38;
			fpga_reg[35] <= 8'h07;	//	Image Width [Default - 1920]
			fpga_reg[36] <= 8'h80;
			fpga_reg[37] <= 8'h00;	// yuv422_420 En
			fpga_reg[38] <= 8'h00;	// Interlaced En
		end
		else begin
			fpga_reg[1] <= fpga_major_version;
			fpga_reg[2] <= fpga_minor_version;
			if(slfifo_st_vidrst2)
				fpga_reg[0][0] <= 'd0;
			if(slfifo_st_audrst2)
				fpga_reg[0][1] <= 'd0;
			case(state)
				START_D : begin
					sda <= 1'b1;
					byte_ct <= 4'd0;
					if(start_bit)begin
						state <= SLAVE_D;
					end
				end
				SLAVE_D : begin
					sda <= 1'b1;
					read_ct <= 5'd8;
					if(sclk_r)begin
						byte_ct <= byte_ct + 1'b1;
						if(byte_ct == 4'd8)begin
							rd_wr <= sl_sda_io;
							if(fpga_sl_addr == slave_addr)begin
								state <= SL_ACK;
							end
							else begin
								state <= START_D;
							end
						end
						else begin
							slave_addr <= {slave_addr[5:0],sl_sda_io};
						end
					end
				end
				SL_ACK : begin
					sda <= 1'b0;
					byte_ct <= 4'd0;
					if((rd_wr)&&(sclk_f)&&(sclk_ct == 8'd9))begin
						state <= READ_D;
						if(fpga_reg_ct > addr_r)begin
							read_data <= fpga_reg[addr[5:0]];
							addr_r <= addr[5:0] + 1'b1;
						end
						else begin
							read_data <= 8'd0;
						end
					end
					else if((sclk_r)&&((sclk_ct == 8'd9)||(sclk_ct == 8'd18)))begin // for 16-BIT register Addressing
						state <= ADDR_D;
					end
					else if((sclk_r)&&(sclk_ct == 8'd27))begin // for 16-BIT register Addressing
						state <= WRITE_D;
						addr_r <= addr[5:0];
					end
					else if((sclk_r)&&(sclk_ct > 8'd27))begin // for 16-BIT register Addressing
						state <= WRITE_D;
						if(fpga_reg_ct > addr_r)begin
							fpga_reg[addr_r] <= data_r;
							data <= data_r;
							addr_r <= addr_r + 1'b1;
						end
					end
				end
				MS_CLK : begin
					sda <= 1'b1;
					byte_ct <= 4'd0;
					if((sclk_f)&&(!sl_sda_io))begin
						state <= READ_D;
						if(fpga_reg_ct > addr_r)begin
							addr_r <= addr_r + 1'b1;
							read_data <= fpga_reg[addr_r];
						end
						else begin
							read_data <= 8'd0;
						end
						read_ct <= 5'd8;
					end
					else if((sclk_f)&&(sl_sda_io))begin
						state <= STOP_D;
					end
				end
				ADDR_D : begin
					sda <= 1'b1;
					if(sclk_r)begin
						read_ct <= 5'd8;
						byte_ct <= byte_ct + 1'b1;
						if(byte_ct == 4'd7)begin
							addr <= {addr[14:0],sl_sda_io}; // for 16-BIT register Addressing
							state <= SL_ACK;
						end
						else begin
							addr <= {addr[14:0],sl_sda_io}; // for 16-BIT register Addressing
						end
					end
				end
				WRITE_D : begin
					sda <= 1'b1;
					if(start_bit)begin
						state <= SLAVE_D;
					end
					else if(stop_bit)begin
						state <= START_D;
					end
					if(sclk_r)begin
						byte_ct <= byte_ct + 1'b1;
						if(byte_ct == 4'd7)begin
							data_r <= {data_r[6:0],sl_sda_io};
							state <= SL_ACK;
						end
						else begin
							data_r <= {data_r[6:0],sl_sda_io};
						end
					end
				end
				READ_D : begin
					if(stop_bit)begin
						state <= START_D;
					end
					if(sclk_r)begin
						if(read_ct == 5'd0)begin
							sda <= 1'b1;
							state <= MS_CLK;
						end
						else begin
							sda <= (read_data[(read_ct - 1'b1)])  ? 1'b1 : 1'b0;
							read_ct <= read_ct - 1'b1;
						end
					end
				end
				STOP_D : begin
					sda <= 1'b1;
					if(stop_bit)begin
						state <= START_D;
					end
					read_ct <= 5'd8;
				end
			endcase
		end
	 end

assign img_wt = {fpga_reg[35],fpga_reg[36]};
assign img_ht = {fpga_reg[33],fpga_reg[34]};

always @(posedge clock_i) begin
	if((img_ht=='d1080)&(img_wt=='d1920))
		mult_out1 <= 'd2073600;
	else if((img_ht=='d2160)&(img_wt=='d3840))
		mult_out1 <= 'd8294400;
	else if((img_ht=='d720)&(img_wt=='d1280))
		mult_out1 <= 'd921600;
	else if((img_ht=='d576)&(img_wt=='d720))
		mult_out1 <= 'd414720;
	else if((img_ht=='d480)&(img_wt=='d720))
		mult_out1 <= 'd345600;
	else if((img_ht=='d480)&(img_wt=='d640))
		mult_out1 <= 'd307200;
	else
		mult_out1 <= 'd2073600;
end
always @(posedge clock_i) begin
	cam_int_en_r1 	<= fpga_reg[16][0];
	cam_int_en_r2	<= cam_int_en_r1;
	gpif_bud_wdt_r1 <= fpga_reg[15][2:0] - 3'd1;
	gpif_bud_wdt_r2 <= gpif_bud_wdt_r1;
	still_cap_en_r1 <= fpga_reg[14][0];
	still_cap_en_r2 <= still_cap_en_r1;
	uvc_header_en_r <= fpga_reg[11][0];
	aud_app_en_r1	<= fpga_reg[10][0];
	aud_app_en_r2	<= aud_app_en_r1;
	cam_app_en_r1	<= fpga_reg[9][0];
	cam_app_en_r2	<= cam_app_en_r1;
	yuv_420_en_r2	<= yuv_420_en_r1;
	slfifo_st_vidrst1 <= fpga_reg[0][0];
	slfifo_st_vidrst2 <= slfifo_st_vidrst1;
	slfifo_st_audrst1 <= fpga_reg[0][1];
	slfifo_st_audrst2 <= slfifo_st_audrst1;
	slfifo_uvc_buf_size1 <= {fpga_reg[12],fpga_reg[13]};
	slfifo_uvc_buf_size2 <= slfifo_uvc_buf_size1;
end
always @(posedge clock_i) begin
	img_wt_r <= img_wt;
	img_ht_r <= img_ht;
	mult_out2 <= mult_out1;
	img_size <= mult_out2;
	yuv_420_en_r1 <= fpga_reg[37][0];
	interleaved_en_r <= fpga_reg[38][0];
end

assign	slfifo_st_vidrst_o = slfifo_st_vidrst1;
assign	slfifo_st_audrst_o = slfifo_st_audrst1;
assign	yuv_420_en = yuv_420_en_r2;
assign	img_ht_o = img_ht_r;
assign	img_wt_o = img_wt_r;
assign	img_size_o = img_size;
assign	interleaved_en_o = interleaved_en_r;
assign	cam_app_en_o = cam_app_en_r2;
`ifdef SLFIFO_INTERFACE_AUD
assign	aud_app_en_o = cam_app_en_r2;
`else
assign	aud_app_en_o = aud_app_en_r2;
`endif
assign	uvc_header_en_o = uvc_header_en_r;
assign	slfifo_uvc_buf_size_o = slfifo_uvc_buf_size2;
assign	still_cap_en_o = still_cap_en_r2;
assign	gpif_buf_wdt_o = gpif_bud_wdt_r2;
assign	cam_int_en_o = cam_int_en_r2;

endmodule


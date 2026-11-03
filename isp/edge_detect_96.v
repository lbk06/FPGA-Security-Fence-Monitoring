module edge_detect_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter EDGE_TH    = 11'd80,
    parameter BIN_TH     = 8'd128
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input      [1:0]    I_mode,
    input               I_tready,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [95:0]   O_tdata,
    output reg          O_tvalid,
    output              O_tready
);

assign O_tready = I_tready;

// ---------------------------------------------------------------------------
// 第 0 级：把 awb 输出先打一拍。awb 的"乘法器 -> 增益加法"是整条视频链上最长
// 的组合路径（实测 13 级逻辑、10.97ns），先在本模块入口断开，后面所有运算
// （灰度、Sobel、模式选择）都从寄存器出发，余量才够。
// 行缓存写地址/行列计数一并跟着这一拍，保证地址与数据仍然对齐。
// ---------------------------------------------------------------------------
reg [95:0] S_in_data;
reg        S_in_v, S_in_tl, S_in_tu;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        S_in_data <= 96'd0;
        S_in_v    <= 1'b0;
        S_in_tl   <= 1'b0;
        S_in_tu   <= 1'b0;
    end else begin
        S_in_data <= I_tdata;
        S_in_v    <= I_tvalid;
        S_in_tl   <= I_tlast;
        S_in_tu   <= I_tuser;
    end
end

wire [23:0] pix0 = S_in_data[95:72];
wire [23:0] pix1 = S_in_data[71:48];
wire [23:0] pix2 = S_in_data[47:24];
wire [23:0] pix3 = S_in_data[23:0];

// Low-cost luminance approximation: R/4 + G/2 + B/4.  Its maximum is
// 253, so it cannot overflow an 8-bit result and requires no divider.
wire [7:0] gray0 = {2'b0,pix0[23:18]} + {1'b0,pix0[15:9]} + {2'b0,pix0[7:2]};
wire [7:0] gray1 = {2'b0,pix1[23:18]} + {1'b0,pix1[15:9]} + {2'b0,pix1[7:2]};
wire [7:0] gray2 = {2'b0,pix2[23:18]} + {1'b0,pix2[15:9]} + {2'b0,pix2[7:2]};
wire [7:0] gray3 = {2'b0,pix3[23:18]} + {1'b0,pix3[15:9]} + {2'b0,pix3[7:2]};

localparam IMG_WIDTH_GRP = (IMG_WIDTH >> 2);

// Use two grayscale samples per 4-pixel input beat.  Each sample represents
// a neighbouring pair of pixels, providing 640 horizontal edge samples while
// keeping the two line buffers small enough for this device.
wire [8:0] pair_sum0 = {1'b0,gray0} + {1'b0,gray1};
wire [8:0] pair_sum1 = {1'b0,gray2} + {1'b0,gray3};
wire [7:0] pair0 = pair_sum0[8:1];
wire [7:0] pair1 = pair_sum1[8:1];

(* ram_style = "block" *) reg [15:0] line1_mem [0:IMG_WIDTH_GRP-1];
(* ram_style = "block" *) reg [15:0] line2_mem [0:IMG_WIDTH_GRP-1];

reg [10:0] x_grp;
reg [10:0] y_pos;

wire [15:0] top_word = line2_mem[x_grp];
wire [15:0] mid_word = line1_mem[x_grp];
wire [15:0] bot_word = {pair0,pair1};

wire [7:0] top0 = top_word[15:8];
wire [7:0] top1 = top_word[7:0];
wire [7:0] mid0 = mid_word[15:8];
wire [7:0] mid1 = mid_word[7:0];

reg [7:0] top_prev2, top_prev1;
reg [7:0] mid_prev2, mid_prev1;
reg [7:0] bot_prev2, bot_prev1;

function [13:0] sobel_mag;
    input [7:0] a00, a01, a02;
    input [7:0] a10, a11, a12;
    input [7:0] a20, a21, a22;
    reg signed [12:0] gx_f;
    reg signed [12:0] gy_f;
    reg [12:0] abs_gx_f;
    reg [12:0] abs_gy_f;
    begin
        gx_f = -$signed({1'b0,a00}) + $signed({1'b0,a02})
             - ($signed({1'b0,a10}) <<< 1) + ($signed({1'b0,a12}) <<< 1)
             - $signed({1'b0,a20}) + $signed({1'b0,a22});
        gy_f =  $signed({1'b0,a00}) + ($signed({1'b0,a01}) <<< 1) + $signed({1'b0,a02})
             - $signed({1'b0,a20}) - ($signed({1'b0,a21}) <<< 1) - $signed({1'b0,a22});
        abs_gx_f = gx_f[12] ? (~gx_f + 1'b1) : gx_f;
        abs_gy_f = gy_f[12] ? (~gy_f + 1'b1) : gy_f;
        sobel_mag = abs_gx_f + abs_gy_f;
    end
endfunction

// Two Sobel windows are evaluated per input beat. Each result is duplicated
// to its corresponding pair of output pixels.
wire [13:0] mag0 = sobel_mag(top_prev2,top_prev1,top0,
                             mid_prev2,mid_prev1,mid0,
                             bot_prev2,bot_prev1,pair0);
wire [13:0] mag1 = sobel_mag(top_prev1,top0,top1,
                             mid_prev1,mid0,mid1,
                             bot_prev1,pair0,pair1);

wire window_valid = (y_pos >= 11'd2) && (x_grp != 11'd0) && !S_in_tu;

// ---------------------------------------------------------------------------
// 流水线：第 0 级(awb 入口寄存) -> 第 1 级(灰度/Sobel) -> 第 2 级(模式选择输出)
// 三种延迟对所有模式一致（3 拍），切换时不错像素、不撕裂。
// ---------------------------------------------------------------------------
reg [95:0] S_p1_data;   // 原图直通数据
reg [31:0] S_p1_gray;   // 4 个像素灰度（灰度/二值模式用）
reg [27:0] S_p1_mag;    // {mag0, mag1}
reg        S_p1_wv;     // 窗口有效（前两行/首列不算）
reg        S_v1, S_tl1, S_tu1;

wire [7:0] g0 = S_p1_gray[31:24];
wire [7:0] g1 = S_p1_gray[23:16];
wire [7:0] g2 = S_p1_gray[15:8];
wire [7:0] g3 = S_p1_gray[7:0];

wire [23:0] grayp0 = {g0, g0, g0};
wire [23:0] grayp1 = {g1, g1, g1};
wire [23:0] grayp2 = {g2, g2, g2};
wire [23:0] grayp3 = {g3, g3, g3};

wire bin0 = (g0 >= BIN_TH);
wire bin1 = (g1 >= BIN_TH);
wire bin2 = (g2 >= BIN_TH);
wire bin3 = (g3 >= BIN_TH);

wire [23:0] binp0 = bin0 ? 24'hffffff : 24'h000000;
wire [23:0] binp1 = bin1 ? 24'hffffff : 24'h000000;
wire [23:0] binp2 = bin2 ? 24'hffffff : 24'h000000;
wire [23:0] binp3 = bin3 ? 24'hffffff : 24'h000000;

wire edge0 = S_p1_wv && (S_p1_mag[27:14] >= EDGE_TH);
wire edge1 = S_p1_wv && (S_p1_mag[13:0]  >= EDGE_TH);

wire [23:0] out0 = edge0 ? 24'hffffff : 24'h000000;
wire [23:0] out1 = edge1 ? 24'hffffff : 24'h000000;

// 四种显示模式：00=原图直通  01=Sobel 边缘  10=灰度  11=二值
// 模式先在本地打一拍再进选择器，避免跨模块组合路径拖长时序。
reg [1:0]  S_mode_d;
reg [95:0] S_effect_out;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) S_mode_d <= 2'b01;
    else         S_mode_d <= I_mode;
end

always @(*) begin
    case(S_mode_d)
        2'b00:   S_effect_out = S_p1_data;                          // 原图直通
        2'b10:   S_effect_out = {grayp3, grayp2, grayp1, grayp0};   // 灰度
        2'b11:   S_effect_out = {binp3, binp2, binp1, binp0};       // 二值
        default: S_effect_out = {out0, out0, out1, out1};           // Sobel
    endcase
end

// ---------------------------------------------------------------------------
// 第 1 级：行缓存读写、Sobel 窗口、模式锁存
// ---------------------------------------------------------------------------
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        S_v1  <= 1'b0;
        S_tl1 <= 1'b0;
        S_tu1 <= 1'b0;
        S_p1_data <= 96'd0;
        S_p1_gray <= 32'd0;
        S_p1_mag  <= 28'd0;
        S_p1_wv   <= 1'b0;
        x_grp    <= 11'd0;
        y_pos    <= 11'd0;
        top_prev2 <= 8'd0; top_prev1 <= 8'd0;
        mid_prev2 <= 8'd0; mid_prev1 <= 8'd0;
        bot_prev2 <= 8'd0; bot_prev1 <= 8'd0;
        // Do not clear line memories here.  A reset loop turns the 10-Kbit
        // buffers into slice registers on this device.  The first two rows
        // are masked by window_valid and naturally initialize both buffers.
    end else begin
        S_v1  <= S_in_v;
        S_tl1 <= S_in_tl;
        S_tu1 <= S_in_tu;

        if(S_in_v) begin
            S_p1_data <= S_in_data;
            S_p1_gray <= {gray3, gray2, gray1, gray0};
            S_p1_mag  <= {mag0, mag1};
            S_p1_wv   <= window_valid;

            line2_mem[x_grp] <= mid_word;
            line1_mem[x_grp] <= bot_word;

            top_prev2 <= top0; top_prev1 <= top1;
            mid_prev2 <= mid0; mid_prev1 <= mid1;
            bot_prev2 <= pair0; bot_prev1 <= pair1;

            if(S_in_tu) begin
                x_grp <= 11'd1;
                y_pos <= 11'd0;
            end else if(x_grp == IMG_WIDTH_GRP - 1) begin
                x_grp <= 11'd0;
                if(y_pos == IMG_HEIGHT - 1)
                    y_pos <= 11'd0;
                else
                    y_pos <= y_pos + 1'b1;
                top_prev2 <= 8'd0; top_prev1 <= 8'd0;
                mid_prev2 <= 8'd0; mid_prev1 <= 8'd0;
                bot_prev2 <= 8'd0; bot_prev1 <= 8'd0;
            end else begin
                x_grp <= x_grp + 1'b1;
            end
        end
    end
end

// ---------------------------------------------------------------------------
// 第 2 级：模式选择 + 输出寄存
// ---------------------------------------------------------------------------
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        O_tlast  <= 1'b0;
        O_tuser  <= 1'b0;
        O_tdata  <= 96'd0;
        O_tvalid <= 1'b0;
    end else begin
        O_tlast  <= S_tl1;
        O_tuser  <= S_tu1;
        O_tvalid <= S_v1;

        if(S_v1)
            O_tdata <= S_effect_out;
        else
            O_tdata <= 96'd0;
    end
end

endmodule

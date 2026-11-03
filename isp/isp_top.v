module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [1:0]  	I_mode			,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,

    // 围栏应用：人员（前景目标）检测结果（axi4s_video_aclk 时钟域）
    output          O_mo_update		,
    output          O_mo_valid		,
    output [10:0]   O_mo_x1			,
    output [10:0]   O_mo_y1			,
    output [10:0]   O_mo_x2			,
    output [10:0]   O_mo_y2			,
    output [13:0]   O_mo_cnt		,
    output          O_mo_alarm		,
    output [3:0]    O_mo_dbg
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

    wire         edge_O_tlast;  //synthesis keep
    wire         edge_O_tuser;  //synthesis keep
    wire [ 95:0] edge_O_tdata;  //synthesis keep
    wire         edge_O_tvalid;  //synthesis keep
    wire         edge_O_tready;  //synthesis keep

    assign awb_O_tready = edge_O_tready;
    assign edge_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast    ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720),  // 图像高度
    .IMG_WIDTH           (1280), // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

awb #(
    .IMG_HEIGHT(720),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

edge_detect_96 #(
    .IMG_WIDTH (1280),
    .IMG_HEIGHT(720),
    .EDGE_TH   (11'd80)
) u_edge_detect_96 (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_mode  (I_mode),
    .I_tlast (awb_O_tlast),
    .I_tuser (awb_O_tuser),
    .I_tdata (awb_O_tdata),
    .I_tvalid(awb_O_tvalid),
    .I_tready(awb_O_tready),
    .O_tlast (edge_O_tlast),
    .O_tuser (edge_O_tuser),
    .O_tdata (edge_O_tdata),
    .O_tvalid(edge_O_tvalid),
    .O_tready(edge_O_tready)
);

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( edge_O_tuser	    ),
        .I_96b_valid        ( edge_O_tvalid 		),
        .I_96b_data         ( edge_O_tdata		),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);

//------------------------------------------------------------------
// 围栏应用：人员检测直接取 awb 输出（算法处理之前的原图），
// 因此无论显示档位是原图/Sobel/灰度/二值，检测都基于真实画面。
// 纯观察支路，不驱动任何 ready，对现有显示通路零改动。
//------------------------------------------------------------------
motion_bbox_detector_96 #(
    .IMG_WIDTH  (1280),
    .IMG_HEIGHT (720),
    .DIFF_TH    (8),
    .BBOX_TH    (32),
    .MIN_CELLS  (8),
    .HOLD_FRAMES(60)
) u_motion_bbox_detector_96 (
    .I_clk         (axi4s_video_aclk),
    .I_rst_n       (I_rst_n         ),
    .I_tdata       (awb_O_tdata     ),
    .I_tvalid      (awb_O_tvalid    ),
    .I_tuser       (awb_O_tuser     ),
    .O_update      (O_mo_update     ),
    .O_valid       (O_mo_valid      ),
    .O_x1          (O_mo_x1         ),
    .O_y1          (O_mo_y1         ),
    .O_x2          (O_mo_x2         ),
    .O_y2          (O_mo_y2         ),
    .O_cnt         (O_mo_cnt        ),
    .O_alarm       (O_mo_alarm      ),
    .O_dbg         (O_mo_dbg        )
);
	
endmodule

//==============================================================================
// motion_bbox_detector_96 : 背景建模 + 前景外接矩形（4 像素/拍输入）
//------------------------------------------------------------------------------
// 这里用的是视频监控里最经典、也是 FPGA 上唯一可行的"人物框"方案：
//   背景建模 -> 前景分割 -> 目标外接矩形（不依赖神经网络）。
//
// 1) 空间抽样：8x8 像素一格，共 160x90 = 14400 格，每拍 4 个像素，
//    偶数拍取第 0 个像素 => x = 0,8,16,...，每 8 行取一行。
// 2) 背景建模：每格保存一个 8bit 背景灰度，每帧按 alpha = 1/32 滑动更新，
//    第一帧直接把当前画面写成背景；背景稳下来后才开始判定。
// 3) 前景判定：|当前灰度 - 背景| > DIFF_TH 即为前景点（计入面积）；
//    差值 > BBOX_TH 的强前景点参与外接框，避免传感器弱噪声把框撑大。
// 4) 帧末统计：前景点数 >= MIN_CELLS、外接框宽高 >= 3 格、且不覆盖整屏，
//    则判为"有人"，输出外接矩形并保持 HOLD_FRAMES 帧再撤框，避免闪烁。
//
// 注意：网格地址必须用完整坐标位宽（gx = bx[8:1]，0..159；gy = by[9:3]，
// 0..89），取窄了会把 14400 个格子压到左上角一小片，检测必然失效。
//==============================================================================
module motion_bbox_detector_96 #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter DIFF_TH     = 20,     // 前景判定阈值（灰度差）
    parameter BBOX_TH     = 32,     // 参与外接框的强前景阈值
    parameter MIN_CELLS   = 60,     // 判"有人"的最小前景格数
    parameter HOLD_FRAMES = 60,     // 目标消失后保持框的帧数
    // 围栏区域（网格坐标，1 格 = 8 像素）：像素 320..960 x 180..540
    parameter FENCE_GX1   = 40,
    parameter FENCE_GY1   = 22,
    parameter FENCE_GX2   = 120,
    parameter FENCE_GY2   = 67
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire [95:0] I_tdata,     // 4 个像素打包（[23:0]=第 0 个像素）
    input  wire        I_tvalid,
    input  wire        I_tuser,     // 帧首拍（仅做诊断，不再用于帧同步）

    output reg         O_update,    // 新结果锁存脉冲（1 拍）
    output reg         O_valid,     // 当前存在目标（含保持期）
    output reg  [10:0] O_x1,        // 目标外接框（全分辨率像素坐标）
    output reg  [10:0] O_y1,
    output reg  [10:0] O_x2,
    output reg  [10:0] O_y2,
    output reg  [13:0] O_cnt,       // 本帧前景格数
    output reg         O_alarm,     // 围栏报警：区域内运动格数达标（含保持期）
    output wire [3:0]  O_dbg        // {cnt>=MIN, bg就绪, 见过帧末, 见过tuser}
);

    //------------------------------------------------------------------
    // 网格几何（160 x 90 = 14400）
    //------------------------------------------------------------------
    localparam [8:0]  BEAT_LAST   = (IMG_WIDTH / 4) - 1;   // 319
    localparam [13:0] GRID_COLS   = IMG_WIDTH / 8;         // 160
    localparam integer GRID_ROWS  = IMG_HEIGHT / 8;        // 90
    localparam integer GRID_PIXELS= GRID_ROWS * (IMG_WIDTH / 8);

    //------------------------------------------------------------------
    // 行列计数（按有效拍推进）
    // 关键：不再用 tuser 复位。这条链路上 tuser 经 demosaic/awb 多级流水后
    // 已经不能保证"每帧一次"，用它复位会把行计数打乱甚至永远到不了帧末，
    // 于是帧末判决从不执行、前景计数恒为 0（屏上状态块永远灰色）。
    // 这里完全按几何自计时：每行 320 拍、共 720 行，计数器自然回卷即一帧。
    //------------------------------------------------------------------
    reg [8:0]  S_bx;      // 拍号 0..319
    reg [9:0]  S_by;      // 行号 0..719

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_bx <= 9'd0;
            S_by <= 10'd0;
        end
        else if (I_tvalid) begin
            if (S_bx == BEAT_LAST) begin
                S_bx <= 9'd0;
                S_by <= (S_by >= (IMG_HEIGHT - 1)) ? 10'd0 : (S_by + 10'd1);
            end
            else begin
                S_bx <= S_bx + 9'd1;
            end
        end
    end

    reg [95:0] S_in_data;
    reg        S_in_v;
    reg        S_in_tu;
    reg [8:0]  S_in_bx;
    reg [9:0]  S_in_by;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_in_data <= 96'd0;
            S_in_v    <= 1'b0;
            S_in_tu   <= 1'b0;
            S_in_bx   <= 9'd0;
            S_in_by   <= 10'd0;
        end
        else begin
            S_in_data <= I_tdata;
            S_in_v    <= I_tvalid;
            S_in_tu   <= I_tvalid & I_tuser;
            S_in_bx   <= S_bx;
            S_in_by   <= S_by;
        end
    end

    //------------------------------------------------------------------
    // 格子灰度：一格 8x8 = 64 个像素的 G 通道平均值
    // 每拍打包 4 像素，同一格的奇偶两拍合成该行的 8 像素（row_sum），
    // 再由"每格一块 12bit 行和累加器"把 8 行加起来，右移 3 位即均值。
    // 注意：累加器必须是"每格一个"，存在 RAM 里按行读-改-写。
    // 之前用一个全局累加器是错的：光栅扫描下它会横跨整行 160 个格子
    // 累加，14 位瞬间溢出，"格子灰度"变成整行和的截断垃圾值，
    // 全屏格子都在无规律跳动，于是整屏都是前景、外接框盖满屏幕。
    //------------------------------------------------------------------
    wire [9:0]  S_g4 = S_in_data[15:8] + S_in_data[39:32]
                     + S_in_data[63:56] + S_in_data[87:80];

    reg  [9:0]  S_h_acc;      // 同格偶数拍的 4 像素和

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            S_h_acc <= 10'd0;
        else if (S_in_v && (S_in_bx[0] == 1'b0))
            S_h_acc <= S_g4;
    end

    wire [10:0] S_row_sum = {1'b0, S_h_acc} + {1'b0, S_g4};   // 一行 8 像素和

    // 格子最后一行（by[2:0]==7）的奇数拍：该格 8 行全部扫完，可出灰度
    wire S_odd      = S_in_v && (S_in_bx[0] == 1'b1);
    wire S_sample   = S_odd && (S_in_by[2:0] == 3'd7);

    // 帧末：最后一拍（第 719 行、第 319 拍）到来时给出一个单拍脉冲。
    // 完全由几何自计时得到，不依赖 tuser，保证每帧必然触发一次。
    wire S_fin_trig = S_in_v && (S_in_bx == BEAT_LAST) && (S_in_by == (IMG_HEIGHT - 1));

    wire [7:0]  S_gx   = S_in_bx[8:1];                  // 0..159
    wire [6:0]  S_gy   = S_in_by[9:3];                  // 0..89
    wire [13:0] S_row  = ({7'd0, S_gy} << 7) + ({7'd0, S_gy} << 5);  // gy*160
    wire [13:0] S_addr = S_row + {6'd0, S_gx};

    //------------------------------------------------------------------
    // 背景存储：14400 x 8bit，单写口 + 单读口
    //------------------------------------------------------------------
    // 强制推断为块 RAM；若被推断成寄存器/分布式 RAM 会耗尽 LUT。
    (* ram_style = "block" *) reg [7:0] S_bg_mem [0:GRID_PIXELS-1];
    reg [7:0] S_bg_rd;

    reg        S_bg_we;
    reg [13:0] S_bg_wa;
    reg [7:0]  S_bg_wd;

    always @(posedge I_clk) begin
        if (S_bg_we)
            S_bg_mem[S_bg_wa] <= S_bg_wd;
        S_bg_rd <= S_bg_mem[S_addr];
    end

    //------------------------------------------------------------------
    // 每格行和累加器：14400 x 12bit（8 行 x 8 像素，最大 2040）
    // 光栅扫描到某格的任意一行时，把它那一行的 8 像素和累加进去；
    // 格子第 0 行直接写入（相当于清零重启），第 7 行累加完即为整格 64
    // 像素和。读-改-写用同一块 1R1W RAM：本拍读、下一拍写回。
    //------------------------------------------------------------------
    (* ram_style = "block" *) reg [11:0] S_ac_mem [0:GRID_PIXELS-1];
    reg [11:0] S_ac_rd;

    reg        S_ac_we;
    reg [13:0] S_ac_wa;
    reg [11:0] S_ac_wd;

    always @(posedge I_clk) begin
        if (S_ac_we)
            S_ac_mem[S_ac_wa] <= S_ac_wd;
        S_ac_rd <= S_ac_mem[S_addr];
    end

    wire [11:0] S_ac_val = (S_in_by[2:0] == 3'd0) ? {4'd0, S_row_sum[10:3]}
                                                 : (S_ac_rd + {4'd0, S_row_sum[10:3]});

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_ac_we <= 1'b0;
            S_ac_wa <= 14'd0;
            S_ac_wd <= 12'd0;
        end
        else begin
            S_ac_we <= S_odd;
            S_ac_wa <= S_addr;
            S_ac_wd <= S_ac_val;
        end
    end

    wire [7:0] S_gray = S_ac_val[10:3];     // 8 行和 ÷8 = 整格 64 像素平均值

    //------------------------------------------------------------------
    // 第 1 级：与背景读出口对齐（灰度、坐标、地址同步打一拍）
    //------------------------------------------------------------------
    reg        S_s1_en;
    reg [7:0]  S_s1_gray;
    reg [7:0]  S_s1_bg;
    reg [7:0]  S_s1_gx;
    reg [6:0]  S_s1_gy;
    reg [13:0] S_s1_addr;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_s1_en   <= 1'b0;
            S_s1_gray <= 8'd0;
            S_s1_bg   <= 8'd0;
            S_s1_gx   <= 8'd0;
            S_s1_gy   <= 7'd0;
            S_s1_addr <= 14'd0;
            S_bg_we   <= 1'b0;
            S_bg_wa   <= 14'd0;
        end
        else begin
            S_s1_en   <= S_sample;
            S_s1_gray <= S_gray;
            S_s1_bg   <= S_bg_rd;
            S_s1_gx   <= S_gx;
            S_s1_gy   <= S_gy;
            S_s1_addr <= S_addr;

            S_bg_we <= S_s1_en;          // 延后一拍写，避开同地址读写冲突
            S_bg_wa <= S_s1_addr;
        end
    end

    // 背景慢速滑动平均：alpha = 1/32，但保证最小步长为 1，
    // 使缓慢光照漂移能被跟随；否则 alpha=0 会让背景冻结在首帧，
    // 整屏渐渐变成"前景"，只有特别剧烈的变化才能成框。
    wire [7:0] S_d1     = (S_s1_gray > S_s1_bg) ? (S_s1_gray - S_s1_bg)
                                                : (S_s1_bg - S_s1_gray);
    wire [7:0] S_alpha  = (S_d1 >> 5) | {7'd0, (S_d1 != 8'd0)};
    // 强前景（差值 > 2*DIFF_TH）不做滑动平均，防止运动目标被快速吸进
    // 背景；但也不能永久冻结——否则目标停住/光照突变后该格永远超阈值，
    // 报警挂死。改为每 16 帧只允许背景向当前灰度靠 1 级（慢速泄漏），
    // 持续运动的目标差值远大于泄漏速度，不受影响；锁死的格子最终会被
    // 吸收回背景，报警自动解除。
    wire S_bg_strong = (S_d1 > (DIFF_TH * 2));
    wire [7:0] S_bg_new = (S_s1_gray > S_s1_bg) ? (S_s1_bg + S_alpha)
                                                : (S_s1_bg - S_alpha);
    wire [7:0] S_bg_leak = (S_s1_gray > S_s1_bg) ? (S_s1_bg + 8'd1)
                                                 : (S_s1_bg - 8'd1);

    //------------------------------------------------------------------
    // 背景初始化：首帧直接写入；第 2 帧起才开始做前景判定
    //------------------------------------------------------------------
    reg [1:0] S_frame_no;
    reg [2:0] S_fin_d;
    reg       S_ref_ready;
    reg [1:0] S_leak_frm;   // 慢速泄漏节拍：每 4 帧前景格背景靠 1 级

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_frame_no  <= 2'd0;
            S_fin_d     <= 3'd0;
            S_ref_ready <= 1'b0;
            S_bg_wd     <= 8'd0;
            S_leak_frm  <= 2'd0;
        end
        else begin
            S_fin_d <= {S_fin_d[1:0], S_fin_trig};

            if (S_fin_trig && (S_frame_no != 2'd3))
                S_frame_no <= S_frame_no + 2'd1;

            if (S_fin_trig)
                S_leak_frm <= S_leak_frm + 2'd1;

            if (S_fin_d[2] && (S_frame_no >= 2'd2))
                S_ref_ready <= 1'b1;

            // 背景更新：未就绪时直接填入当前灰度（快速建背景）；
            // 就绪后非强前景做 1/32 滑动平均；强前景每 4 帧泄漏 1 级，
            // 既保住运动目标，又避免格子被永久锁死导致报警挂死。
            if (S_s1_en)
                S_bg_wd <= !S_ref_ready ? S_s1_gray :
                           !S_bg_strong ? S_bg_new  :
                           (S_leak_frm == 2'd0) ? S_bg_leak : S_bg_rd;
        end
    end

    //------------------------------------------------------------------
    // 前景判定 + 计数/外接框累加
    // 围栏模式：只统计落在围栏区域（网格坐标）内的前景格数，
    // 区域内运动格数达标即报警，不再关心是不是"人"。
    //------------------------------------------------------------------
    wire S_fg_any  = S_s1_en && S_ref_ready && (S_d1 > DIFF_TH);

    wire S_in_fence = (S_s1_gx >= FENCE_GX1) && (S_s1_gx <= FENCE_GX2) &&
                      (S_s1_gy >= FENCE_GY1) && (S_s1_gy <= FENCE_GY2);

    reg [13:0] S_cnt;
    reg [13:0] S_cnt_in;
    reg [7:0]  S_xmin;
    reg [7:0]  S_xmax;
    reg [6:0]  S_ymin;
    reg [6:0]  S_ymax;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_cnt         <= 14'd0;
            S_cnt_in      <= 14'd0;
            S_xmin        <= 8'd255;
            S_xmax        <= 8'd0;
            S_ymin        <= 7'd127;
            S_ymax        <= 7'd0;
        end
        else if (S_fin_trig) begin
            S_cnt         <= 14'd0;
            S_cnt_in      <= 14'd0;
            S_xmin        <= 8'd255;
            S_xmax        <= 8'd0;
            S_ymin        <= 7'd127;
            S_ymax        <= 7'd0;
        end
        else if (S_fg_any) begin
            S_cnt <= S_cnt + 14'd1;
            if (S_in_fence)
                S_cnt_in <= S_cnt_in + 14'd1;
            if (S_s1_gx < S_xmin) S_xmin <= S_s1_gx;
            if (S_s1_gx > S_xmax) S_xmax <= S_s1_gx;
            if (S_s1_gy < S_ymin) S_ymin <= S_s1_gy;
            if (S_s1_gy > S_ymax) S_ymax <= S_s1_gy;
        end
    end

    //------------------------------------------------------------------
    // 帧末判决：尺寸合理 + 格数达标 + 框不接近整屏 + 框内填充率够高
    // 填充率是关键：真正的人是一块紧凑连通体，框内填充通常 40% 以上，
    // 而光照漂移/噪声是零散分布，填充率只有百分之几。这里取 1/8
    // （12.5%）作下限，既挡得住散点噪声，又不会把稀疏一点的人形拒掉。
    //------------------------------------------------------------------
    wire [7:0] S_bw = S_xmax - S_xmin;
    wire [6:0] S_bh = S_ymax - S_ymin;

    wire S_size_ok  = (S_bw >= 8'd2) && (S_bh >= 7'd2);
    wire S_area_ok  = (S_cnt >= MIN_CELLS);
    wire S_cap_ok   = (S_bw <= 8'd140) && (S_bh <= 7'd80);
    wire [8:0]  S_bw1      = {1'b0, S_bw} + 9'd1;               // 1..160
    wire [7:0]  S_bh1      = {1'b0, S_bh} + 8'd1;               // 1..90
    wire [14:0] S_box_area = S_bw1 * S_bh1;                     // 最大 14400
    wire [16:0] S_cnt16    = {2'b00, S_cnt} << 4;
    // 行走中的人前景 = 新位置 + 刚离开的位置，外接框被拉宽且填充稀疏，
    // 填充率放宽到 1/16，否则"内部行走"会被拒、只有"边缘进入"能成框
    wire S_fill_ok  = (S_cnt16 >= {2'b00, S_box_area});
    wire S_hit      = S_size_ok && S_area_ok && S_cap_ok && S_fill_ok;

    // 围栏报警：区域内运动格数达标 + 目标形状"像人"才报警。
    // 人形特征（无神经网络条件下的启发式）：
    //   1) 外接框高 >= 宽的一半：行走时旧位置残影会把框拉宽到约 2 倍体宽，
    //      高度仍接近人体全高，故用 bh >= bw/2 而不是 bh >= bw
    //   2) 框高 >= 10 格（80 像素）：滤掉小动物/小物件
    //   3) 框内填充率 >= 1/16：滤掉零散噪点
    wire S_person_like = S_size_ok && S_fill_ok &&
                         ({1'b0, S_bh} >= {1'b0, S_bw[7:1]}) && (S_bh >= 7'd10);

    reg [5:0] S_hold;
    reg [5:0] S_alm_hold;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_update   <= 1'b0;
            O_valid    <= 1'b0;
            O_x1       <= 11'd0;
            O_y1       <= 11'd0;
            O_x2       <= 11'd0;
            O_y2       <= 11'd0;
            O_cnt      <= 14'd0;
            O_alarm    <= 1'b0;
            S_hold     <= 6'd0;
            S_alm_hold <= 6'd0;
        end
        else begin
            O_update <= 1'b0;

            if (S_fin_trig) begin
                O_update <= 1'b1;
                O_cnt    <= S_cnt_in;

                // ---- 围栏报警（人形判定 + 迟滞 + 保持）----
                // 触发：区域内前景 >= 2*MIN_CELLS 且目标形状像人
                // 维持：区域内前景格数 >= MIN_CELLS/2（触发已卡过形状，
                //       维持阶段只看运动是否还在，避免形状抖动掉报警）
                // 解除：格数 < MIN_CELLS/2 且保持期结束
                if (!O_alarm) begin
                    if ((S_cnt_in >= (MIN_CELLS * 2)) && S_person_like) begin
                        O_alarm    <= 1'b1;
                        S_alm_hold <= HOLD_FRAMES;
                    end
                end
                else begin
                    if (S_cnt_in >= (MIN_CELLS / 2)) begin
                        S_alm_hold <= HOLD_FRAMES;      // 仍有运动：续期
                    end
                    else if (S_alm_hold != 6'd0) begin
                        S_alm_hold <= S_alm_hold - 6'd1;
                    end
                    else begin
                        O_alarm <= 1'b0;
                    end
                end

                if (S_hit) begin
                    O_valid <= 1'b1;
                    S_hold  <= HOLD_FRAMES;
                    O_x1    <= {S_xmin, 3'b000};
                    O_x2    <= {S_xmax, 3'b000} + 11'd7;
                    O_y1    <= {S_ymin, 3'b000};
                    O_y2    <= {S_ymax, 3'b000} + 11'd7;
                end
                else if (S_hold != 6'd0) begin
                    S_hold <= S_hold - 6'd1;    // 目标短暂丢失：保持原框
                end
                else begin
                    O_valid <= 1'b0;
                    // 诊断用：未成框时也把本帧原始外接框送出去，
                    // 屏幕上用蓝色画出，便于分清"没算出框"和"框被判据拒掉"
                    O_x1    <= {S_xmin, 3'b000};
                    O_x2    <= {S_xmax, 3'b000} + 11'd7;
                    O_y1    <= {S_ymin, 3'b000};
                    O_y2    <= {S_ymax, 3'b000} + 11'd7;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 屏上诊断：把帧末判决的四个子条件逐帧锁存到 4 个诊断格，
    // 绿色=该条件通过。哪一格是红/灰，就说明成框卡在那一条。
    //   dbg[0] 尺寸够大   dbg[1] 格数达标
    //   dbg[2] 框不接近整屏   dbg[3] 框内填充率 >= 12.5%
    //------------------------------------------------------------------
    reg S_l_size, S_l_area, S_l_cap, S_l_fill;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_l_size <= 1'b0;
            S_l_area <= 1'b0;
            S_l_cap  <= 1'b0;
            S_l_fill <= 1'b0;
        end
        else if (S_fin_trig) begin
            S_l_size <= S_size_ok;
            S_l_area <= S_area_ok;
            S_l_cap  <= S_cap_ok;
            S_l_fill <= S_fill_ok;
        end
    end

    assign O_dbg = {S_l_fill, S_l_cap, S_l_area, S_l_size};

endmodule

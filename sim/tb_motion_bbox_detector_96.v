//==============================================================================
// tb_motion_bbox_detector_96
// 人形判定测试台：模拟 1280x720@60 的 96bit(4像素/拍) AXI-Stream 原图流，
// 依次注入以下场景，检查 O_alarm 是否符合预期：
//   场景0  纯静态背景          -> 不报警（背景建模）
//   场景1  人(40x120, 竖高)走过围栏 -> 报警
//   场景2  人离开              -> 报警保持后自动解除
//   场景3  球(40x40, 矮)滚过围栏   -> 不报警（高度不够）
//   场景4  横箱(160x40)移过围栏    -> 不报警（宽大于高）
//   场景5  小猫(30x24)穿过围栏     -> 不报警（太小）
// 运行：iverilog -g2005 -o tb_mo.vvp tb_motion_bbox_detector_96.v \
//          ../../hdl_source/isp/isp_top.v   // 或只例化 detector 源文件
// 说明：detector 内嵌在 isp_top.v 末尾，可用 -D 只编译该模块或把
//       motion_bbox_detector_96 单独拷出编译。
//==============================================================================
`timescale 1ns/1ps

module tb_motion_bbox_detector_96;

    localparam IMG_W   = 1280;
    localparam IMG_H   = 720;
    localparam BEATS   = IMG_W/4;        // 320 拍/行
    localparam GAP     = 8;              // 行间隔拍数（加速仿真，实际约47）
    localparam FRAMES  = 90;             // 总仿真帧数

    // 围栏（与 isp_top 例化一致：像素 320..960 x 180..540）
    localparam FEN_X1 = 320, FEN_Y1 = 180, FEN_X2 = 960, FEN_Y2 = 540;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [95:0] tdata = 96'd0;
    reg         tvalid = 1'b0;
    reg         tuser = 1'b0;

    wire        up, val, alm;
    wire [10:0] x1, y1, x2, y2;
    wire [13:0] cnt;
    wire [3:0]  dbg;

    // 被测模块（与 isp_top 例化参数一致；HOLD_FRAMES 缩短以便仿真）
    motion_bbox_detector_96 #(
        .IMG_WIDTH  (IMG_W),
        .IMG_HEIGHT (IMG_H),
        .DIFF_TH    (8),
        .BBOX_TH    (32),
        .MIN_CELLS  (8),
        .HOLD_FRAMES(8)
    ) dut (
        .I_clk   (clk), .I_rst_n (rst_n),
        .I_tdata (tdata), .I_tvalid (tvalid), .I_tuser (tuser),
        .O_update(up), .O_valid(val),
        .O_x1(x1), .O_y1(y1), .O_x2(x2), .O_y2(y2),
        .O_cnt(cnt), .O_alarm(alm), .O_dbg(dbg)
    );

    always #4.85 clk = ~clk;            // ≈103MHz

    //--------------------------------------------------------------------------
    // 场景脚本：每帧一个移动物体（像素坐标），无物体时全 0 表示静态
    //--------------------------------------------------------------------------
    integer frame_no = 0;

    // 物体参数（当前帧有效）：使能 + 矩形
    reg        obj_en;
    reg [11:0] obj_x1, obj_y1, obj_x2, obj_y2;

    // 人：40x120，从围栏左侧走入再走出
    localparam PERSON_W = 40, PERSON_H = 120;

    always @(*) begin
        obj_en = 1'b0;
        obj_x1 = 0; obj_y1 = 0; obj_x2 = 0; obj_y2 = 0;

        // 场景1：帧 5..24，人从左向右穿过围栏（y 固定在 300..420）
        if (frame_no >= 5 && frame_no < 25) begin
            obj_en = 1'b1;
            obj_x1 = 280 + (frame_no-5)*24;            // 每帧右移 24 像素
            obj_y1 = 300;
            obj_x2 = obj_x1 + PERSON_W - 1;
            obj_y2 = obj_y1 + PERSON_H - 1;
        end
        // 场景3：帧 45..60，球 40x40 穿过围栏
        else if (frame_no >= 45 && frame_no < 60) begin
            obj_en = 1'b1;
            obj_x1 = 280 + (frame_no-45)*32;
            obj_y1 = 340;
            obj_x2 = obj_x1 + 39;
            obj_y2 = obj_y1 + 39;
        end
        // 场景4：帧 65..75，横箱 160x40 移过围栏
        else if (frame_no >= 65 && frame_no < 75) begin
            obj_en = 1'b1;
            obj_x1 = 280 + (frame_no-65)*32;
            obj_y1 = 340;
            obj_x2 = obj_x1 + 159;
            obj_y2 = obj_y1 + 39;
        end
        // 场景5：帧 80..88，小猫 30x24 穿过围栏
        else if (frame_no >= 80 && frame_no < 88) begin
            obj_en = 1'b1;
            obj_x1 = 280 + (frame_no-80)*40;
            obj_y1 = 400;
            obj_x2 = obj_x1 + 29;
            obj_y2 = obj_y1 + 23;
        end
    end

    //--------------------------------------------------------------------------
    // 像素生成：背景灰度 100，物体灰度 190（对比度 90，远超 DIFF_TH=8）
    //--------------------------------------------------------------------------
    function [7:0] pix_gray;
        input [11:0] px, py;
        begin
            if (obj_en && px >= obj_x1 && px <= obj_x2 &&
                         py >= obj_y1 && py <= obj_y2)
                pix_gray = 8'd190;
            else
                pix_gray = 8'd100;
        end
    endfunction

    //--------------------------------------------------------------------------
    // AXI-Stream 激励：每行 320 拍有效 + GAP 拍间隔，720 行一帧
    //--------------------------------------------------------------------------
    integer bx = 0;        // 拍号
    integer by = 0;        // 行号
    integer gp = 0;        // 间隔计数

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tvalid <= 1'b0; tuser <= 1'b0; tdata <= 96'd0;
            bx <= 0; by <= 0; gp <= 0;
        end
        else begin
            tuser <= 1'b0;
            if (gp != 0) begin
                tvalid <= 1'b0;
                gp <= gp - 1;
            end
            else begin
                tvalid <= 1'b1;
                if (bx == 0 && by == 0)
                    tuser <= 1'b1;
                // 4 个像素打包：G 在 [15:8]/[39:32]/[63:56]/[87:80]
                tdata <= {
                    8'd0, pix_gray(bx*4+3, by), 8'd0,
                    8'd0, pix_gray(bx*4+2, by), 8'd0,
                    8'd0, pix_gray(bx*4+1, by), 8'd0,
                    8'd0, pix_gray(bx*4+0, by), 8'd0 };
                if (bx == BEATS-1) begin
                    bx <= 0;
                    gp <= GAP;
                    if (by == IMG_H-1) begin
                        by <= 0;
                        frame_no = frame_no + 1;
                        report_frame;
                        if (frame_no >= FRAMES) summary;
                    end
                    else
                        by <= by + 1;
                end
                else
                    bx <= bx + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // 帧末报告 + 判定
    //--------------------------------------------------------------------------
    integer err_cnt = 0;

    task report;
        input [127:0] tag;
        $display("[帧 %0d] %s  cnt_in=%0d  alarm=%b  dbg=%b%b%b%b",
                 frame_no, tag, cnt, alm, dbg[3], dbg[2], dbg[1], dbg[0]);
    endtask

    task expect;
        input exp_alm;
        input [127:0] tag;
        begin
            report(tag);
            if (alm !== exp_alm) begin
                err_cnt = err_cnt + 1;
                $display("  *** FAIL: 期望 alarm=%b 实际=%b", exp_alm, alm);
            end
        end
    endtask

    task report_frame;
        begin
            if (frame_no <= 4)                                  expect(1'b0, "静态背景      ");
            // 人完全进入围栏（左右边缘都在围栏内）才期望报警
            else if (frame_no >= 6  && frame_no < 25 &&
                     (280+(frame_no-5)*24) >= FEN_X1 &&
                     (280+(frame_no-5)*24) + PERSON_W <= FEN_X2) expect(1'b1, "人穿过围栏    ");
            else if (frame_no >= 25 && frame_no < 36)           report("人离开/保持   ");
            else if (frame_no >= 40 && frame_no < 45)           expect(1'b0, "人已离开      ");
            else if (frame_no >= 45 && frame_no < 60)           expect(1'b0, "球滚过围栏    ");
            else if (frame_no >= 65 && frame_no < 75)           expect(1'b0, "横箱过围栏    ");
            else if (frame_no >= 80 && frame_no < 88)           expect(1'b0, "小猫过围栏    ");
        end
    endtask

    task summary;
        begin
            $display("==============================================");
            if (err_cnt == 0)
                $display("全部场景符合预期：人形报警，误报物体均不报警");
            else
                $display("共 %0d 个场景不符合预期", err_cnt);
            $display("==============================================");
            $finish;
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end

endmodule

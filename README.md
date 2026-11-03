# 园区智能安防监控与电子围栏系统

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 赛道（安路科技选题）
> 全部算法以 Verilog 在 FPGA 内实时硬件实现，无 CPU 参与。

## 硬件平台

| 模块 | 型号 |
| ---- | ---- |
| FPGA | Anlogic PH1P35（PH1P35MDG324） |
| 摄像头 | SC520CS MIPI D-PHY（2-lane） |
| 显示输出 | HDMI 1280×720@60 |
| 存储 | DDR2 |

## 功能特性

1. 实时图像采集与显示（MIPI → ISP → DDR2 帧缓存 → HDMI）
2. Sobel 边缘检测
3. 运动目标检测（160×90 网格背景差分）
4. 人形特征判定（几何判据）
5. 电子围栏区域入侵检测
6. 报警输出（LED1）与报警迟滞
7. OSD 叠加（安路 logo、红色目标框、质心十字、实时坐标、状态灯与档位条）

## 核心算法

- **运动检测**：背景差分 160×90 网格（每格 16×16 像素区域统计），帧间差分提取运动区域
- **人形判定**：运动目标高度 ≥ 宽度/2，高度 ≥ 10 格，填充率 ≥ 1/16
- **报警迟滞**：连续 60 帧内 ≥ 16 格触发报警；< 4 格解除报警，避免误报抖动
- **电子围栏**：OSD 红色目标框 + 实时坐标 X:xxxx Y:yyy，区域内入侵即报警
- **OSD 叠加**：HDMI 输出端叠加安路 logo、目标框、质心十字、坐标与状态指示

## 资源占用（PH1P35，Anlogic TD 6.2.168116）

| 资源 | 用量 | 可用 | 占比 |
| ---- | ---: | ---: | ---: |
| LUT6 | 13664 | 21216 | 64.4% |
| 寄存器 REG | 14517 | 42432 | 34.2% |
| 块存储 ERAM | 55 | 108 | 50.9% |
| DSP | 9 | 40 | 22.5% |

布局布线时序全部收敛（详细时序报告见 `td_project/design_top_wrapper_route.timingsummary`）。

## 目录结构

```
.
├── td_project/                     # Anlogic TD 工程文件（.al/.sdc/时序报告）
│   └── camera_to_dsi_display.al    # 主工程（TD 打开此文件）
├── user_source/
│   ├── hdl_source/                 # RTL 源码
│   │   ├── design_top_wrapper.v    # 顶层：围栏判定、报警输出、跨时钟域同步
│   │   ├── hdmi_mixer.v            # OSD 叠加（logo/目标框/坐标/状态灯）
│   │   ├── isp/isp_top.v           # 运动检测 + 人形判定（motion_bbox_detector_96）
│   │   └── ...                     # ISP/MIPI/HDMI/DDR2 等驱动模块
│   ├── constraints_source/         # 引脚分配（pin.adc）与时序约束（timing.sdc）
│   ├── ip_source/                  # 自建 IP 源码
│   └── sim/                        # 仿真测试台
│       └── tb_motion_bbox_detector_96.v   # 6 场景运动检测测试
└── README.md
```

## 开发环境与烧录

1. 开发工具：Anlogic TD 6.2.168116
2. 打开工程：`td_project/camera_to_dsi_display.al`
3. 综合 → 布局布线 → 生成 Bitstream → 下载到开发板

## 说明

- `td_project/camera_to_dsi_display_Runs/` 为编译中间产物（未上传），打开工程重新编译即可生成
- 本仓库仅含源码与工程配置，不包含演示视频
# Spectacular Rec 对齐：差异说明与修复清单（以样例为准）

## 1. 目标与对齐基线

目标：让本项目（`spatial_data_recorder`）录制输出在**文件结构、编码参数、时间行为、标定/内参写法**上尽可能与 **Spectacular Rec** 产物一致，便于下游工具/脚本“直接替换输入”。

本仓库内置一份 Spectacular Rec 风格参考样例，可作为**对齐基线**：

- `docs/recording_2026-03-18_19-14-19/`

后文以该样例（记为 `spec`）与本应用录制输出（记为 `ours`）进行逐项对齐说明。

---

## 2. Spec（样例）关键参数摘要（建议作为验收标准）

### 2.1 文件结构（会话目录）

- `data.mov`：H.264 视频，**无音轨**
- `data.jsonl`：IMU + 帧元数据（JSON Lines）
- `calibration.json`：相机标定（两路时 `cameras` 为 2 项）
- `metadata.json`：最小元数据（样例只有 `device_model` / `platform`）
- `frames2/*.png`：深度逐帧 PNG（16-bit gray）

> 说明：样例的 `data.mov` 无音轨；当前项目已改为**只产出一个 `data.mov`**，并在开启音频时将音轨直接封装进该文件。  
> 如果某条下游工具链仍要求“纯视频 `data.mov`”，需要在消费前额外导出无音轨副本（见 §3.2、§4-P0-2、§5-2）。

### 2.2 深度帧序列 `frames2/*.png`

样例特征（可以用 PNG 头部直接验证）：

- Color type：0（grayscale）
- Bit depth：16
- 分辨率：**256×192**
- 像素语义：以 **mm** 存储（与 `data.jsonl` 的 `depthScale = 0.001` 对应，`depthMeters = pngValue * 0.001`）

### 2.3 `data.mov`（容器/编码）

样例特征：

- 仅 1 条 H.264 视频流（**无 44.1kHz PCM 音轨**）
- `nominal r_frame_rate`：约 **30/1**
- `avg_frame_rate`：约 30fps，帧间隔稳定在 ~33.3ms

### 2.4 `metadata.json`（schema）

样例 `metadata.json` 极简：

```json
{"device_model":"iPhone13,4","platform":"ios"}
```

即：**不包含** `audio_*`、`capture_mode`、`depth_mode_required` 等扩展字段。

### 2.5 `calibration.json`（两路时的关键点）

样例特征（重点）：

- `camera0` / `camera1` 的内参（`focalLengthX/Y`、`principalPointX/Y`）在样例里一致
- `camera1.imuToCamera` 相对 `camera0` 多了一个平移占位：`x = 0.1`（矩阵的 `[0][3]`）

### 2.6 `data.jsonl`（帧行 / 内参写法 / 排序行为）

样例特征（重点）：

- `frames[1]`（深度灰度）：
  - `colorFormat: "gray"`
  - `depthScale: 0.001`
  - `aligned: true`
  - **逐帧内参写法：与 `frames[0]` 完全一致**
- **行顺序不是严格按 `time` 全局递增**（这是 Spectacular 样例的“原始流行为”，不是 schema 差异）

---

## 3. Ours vs Spec：已知差异与含义（来自对比结论）

### 3.1 深度 PNG 分辨率不一致（关键）

- `spec/frames2`：256×192
- `ours/frames2`：历史产物曾出现 320×240（取决于设备支持的 depth format）

这通常不是“时长差异”，而是**深度流格式（activeDepthDataFormat）未对齐**导致的。

### 3.2 `data.mov` 音轨策略（关键，当前实现为有意识偏离）

- `spec/data.mov`：仅 H.264 视频（无音轨）
- `ours/data.mov`：主产物；关闭音频时仅视频，开启音频且录制成功时为 H.264 视频 + 音频轨
- `ours/`：不再额外导出 `data_with_audio.mov`

这意味着：**当前录制目录优先服务业务采集与回放，`data.mov` 是否带音轨取决于录制配置**。  
如果后续还要把这批数据喂给严格按 Spectacular 样例验收的 CLI/脚本，需要在进入工具链前额外做一次“去音轨”预处理。

#### 3.2.1 为什么 `data.mov` 带音轨会“影响下游”

这里的“影响”主要不是指算法一定变差，而是指：**工具链兼容性、时间轴稳定性与工程风险**会显著上升。

**影响什么：**

- **合同/验收不一致**：Spectacular 样例的 `data.mov` 只有 1 条 video stream；很多下游脚本会把“`data.mov` 仅视频流”当作合同的一部分（例如直接检查 stream 数量、是否存在 audio stream）。
- **解析/抽帧脚本更脆弱**：少数工具/脚本会对 stream 顺序做假设（例如“第 0 条 stream 就是视频”）。一旦容器里出现音轨，stream 排序/选择策略不再稳定，轻则取错流，重则直接报错或抽帧为 0。
- **时间轴相关统计更容易误判**：一些检查会用容器层 `duration`、`start_time`、`bit_rate` 之类字段做对齐判断；音轨一旦存在，“谁更长/谁先开始”会影响容器层的表现，从而让“视频时长/帧数估算”出现偏差。
- **录制端稳定性风险上升**：在移动端同时采集/编码/写入音频会增加 CPU、I/O 与 AVFoundation 管线压力；极端情况下会间接增加视频丢帧与 PTS 抖动概率（而这恰好是下游 VIO/SLAM 最敏感的指标之一）。

**怎么影响（机制层面）：**

- MOV/MP4 是 **多轨容器**：音频与视频各自有独立的 timebase/timescale，容器层还有一个 movie timescale。加入音轨后，导出/封装步骤为了保持 A/V 同步可能会引入额外的时间量化、对齐与裁剪逻辑（例如以较短轨为准裁剪，或出现非零 `start_time` / edit list）。
- 一旦发生“为了对齐音视频而改写时间轴”的行为，下游若把 `data.mov` 当作“纯视频时钟”来对齐 `data.jsonl`，就更容易出现**帧时间不稳、短长帧混杂、帧-IMU 对齐漂移**等问题。

**因此当前策略：**

- **录制会话目录本身**：只保留一个 `data.mov`；若录制时启用音频，则该文件直接带音轨。
- **给 Spectacular CLI / 严格样例工具链的目录**：在进入下游前，从 `data.mov` 额外导出无音轨副本（例如 `data_cli.mov`），不要再依赖双产物目录结构。

### 3.3 `data.mov` 标称帧率 / 帧间隔抖动（关键）

现象：

- `spec`：`r_frame_rate = 30/1`，帧间隔 ~33.336ms 稳定
- `ours`：容器层 `r_frame_rate = 60/1`，但平均仍接近 30fps，且出现 16.67ms / 50ms 的短长帧

这通常意味着**实际采集或 activeFormat 锁到了 60fps**，但写入端丢帧导致平均帧率接近 30。

### 3.4 `metadata.json` schema 不一致（关键，当前实现已对齐）

样例 `metadata.json` 极简（`device_model` / `platform`）。  
本项目当前实现也保持 `metadata.json` 为最小字段集；若需要记录音频/上传业务字段，建议写入独立文件（例如 `upload_context.json`），避免污染样例合同。

### 3.5 两路内参与 aligned 行为不一致（关键）

现象：

- `spec`：逐帧 `camera1` 内参与 `camera0` 一致
- `ours`：虽写了 `aligned:true`，但 `camera1` 内参仍有稳定偏差（cx/cy 偏移、fx/fy 浮动）

如果深度已经对齐到 RGB，**`aligned:true` 对应的内参应与 RGB 主路一致**，否则下游会认为是“未对齐”或“仍是另一相机模型”。

### 3.6 `calibration.json` 数值差异（较关键）

常见表现：

- 焦距/主点数值偏差（可能来自分辨率/取参来源不同）
- `camera1.imuToCamera` 平移占位缺失（样例是 `x=0.1`，ours 变成 0.0）

### 3.7 传感器采样率差异（较关键）

常见表现：

- gyro / accel：两边都 ~100 Hz（OK）
- magnetometer：`spec` ~100 Hz，`ours` ~50–60 Hz

需要提高磁力计 update interval（设备层仍可能被系统限制）。

### 3.8 JSONL 写出顺序差异（可选对齐）

- `spec`：不是严格按 `time` 全局递增
- `ours`：严格单调递增

这不是 schema 变化，但如果目标是“字节级复刻样例”，需要决定是否模拟样例的“原始顺序”。

---

## 4. 修复清单（按优先级，映射到本项目代码模块）

### P0（必须先修，直接导致格式不对齐）

1. **深度 `frames2/*.png` 分辨率固定/优先到 256×192（并持续回归抽检）**
   - 模块：`ios/Runner/SlamRecordingSession.swift`
   - 重点：优先选择 `activeDepthDataFormat` 中 **256×192** 的 depth format；若设备不支持需明确回退策略

2. **让录制产物只保留一个 `data.mov`；若下游仍要求纯视频，则补一层去音轨预处理**
   - 目标：应用侧不再维护 `data.mov` / `data_with_audio.mov` 双产物，最终会话目录只保留一个主视频文件
   - 当前方案：开启音频时直接把音轨封装进 `data.mov`；关闭音频时 `data.mov` 仍为纯视频
   - CLI 兼容：若下游脚本仍要求仅视频流，可额外导出 `data_cli.mov`（或覆盖生成无音轨 `data.mov`）供 CLI 使用
   - 原因：见 §3.2.1（音轨对工具链/时间轴/稳定性的影响）

3. **确保视频采集锁到 30fps，避免 60fps 丢帧**
   - 模块：`ios/Runner/SlamRecordingSession.swift`
   - 重点：选 `activeFormat` 时优先选支持 30fps 的 format，并锁 `activeVideoMin/MaxFrameDuration`

4. **`aligned:true` 时第二路（深度）内参写法与第一路完全一致**
   - 模块：`ios/Runner/SlamRecordingSession.swift`（写 JSONL 帧行 / 写 calibration.json）

### P1（强烈建议，影响下游一致性）

5. **磁力计采样率提升到 ~100 Hz**
   - 模块：`ios/Runner/SlamRecordingSession.swift`
   - 重点：`magnetometerUpdateInterval = 1/100`

6. **`calibration.json` 的 `camera1.imuToCamera` 平移占位与样例一致（x=0.1）**
   - 模块：`ios/Runner/SlamRecordingSession.swift`

7. **`metadata.json` 收敛到样例 schema（仅保留最小字段集）**
   - 模块：`ios/Runner/SlamRecordingSession.swift`

### P2（可选：追求“样例行为复刻”）

8. **JSONL 行写出顺序不再按 time 全局排序**
   - 模块：`ios/Runner/SlamRecordingSession.swift`
   - 说明：写出顺序按“回调到达顺序”保留，更接近样例的 raw stream 行为

---

## 5. 验收/自检建议（不依赖业务代码）

1. **检查 frames2 PNG 规格**
   - 任取 `frames2/00000000.png`，校验 IHDR：`256x192`、`bitDepth=16`、`colorType=0`

2. **检查 `data.mov` 的音轨状态是否符合当前用途**
   - 用 `ffprobe -hide_banner -show_streams data.mov`（或你们内部脚本）
   - 若本次录制启用了音频：期望至少包含 1 条 `video` stream 和 1 条 `audio` stream
   - 若要送入严格按样例验收的 CLI：先导出无音轨版本，再检查该副本是否只包含 1 条 `video` stream
   - 说明：为什么要这样验收见 §3.2.1

3. **检查帧率与抖动**
   - `r_frame_rate` 期望 30/1
   - `avg_frame_rate` 约 30fps
   - 相邻帧 PTS 间隔应集中在 ~33.3ms，不应出现大量 16.7ms / 50ms

4. **检查 JSONL 两路内参一致**
   - 对所有帧行：`frames[0].calibration` 与 `frames[1].calibration`（当 `aligned:true` 且 `gray`）应完全一致

5. **检查 metadata.json 字段集合**
   - 期望只有样例的最小字段（或至少不包含 `audio_*` / `capture_mode` 等扩展字段）

---

## 6. 备注：关于坐标系/符号

仅凭一次录制中 `accelerometer` 的正负号与样例不同，不能直接判定坐标系错误：手机姿态差异会改变重力在设备坐标系下的分量符号。

更像“实现偏差”的通常是：

- `aligned:true` 但两路内参未贴齐
- `imuToCamera` 的平移占位丢失
- 深度分辨率不匹配
- 采样率配置不一致


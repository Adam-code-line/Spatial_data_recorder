# Spatial Data Recorder 对齐 Spectacular Rec：现状检查与优化指南（2026-04-20）

本文基于对当前仓库代码与内置样例数据的逐项检查，总结：

1) 你的录制链路现在与 **Spectacular Rec** 的样例合同（文件结构 / 编码参数 / 时间行为 / 标定写法）对齐到什么程度；  
2) 还可以从哪些方向继续对齐与优化；  
3) 想获得“和 Spectacular Rec 一样好”的下游处理效果，采集端与处理端分别该怎么做。

> 对齐基线样例：`docs/recording_2026-03-18_19-14-19/`  
> 关键实现：`ios/Runner/SlamRecordingSession.swift`（采集 + 落盘）

---

## 0. 结论速览（先看这个）

- **格式层面（能不能被工具链吃进去）**：当前 iOS 录制链路已基本覆盖 Spectacular 样例所需的最小闭环：  
  `data.mov` + `frames2/*.png` + `data.jsonl` + `calibration.json` + `metadata.json`。
- **业务差异（你选择保留音频）**：Spectacular 样例的 `data.mov` 通常无音轨；但你这边希望 **保留音频**（用于现场记录/回放/同步排查等）。  
  这在“数据质量”上不一定是坏事，但会带来两点工程注意事项：  
  1) 少数工具链/脚本可能假设“容器里只有 video stream”，需要确认兼容性；  
  2) 音频采集与写入会占用一定资源，极端情况下可能间接增加丢帧风险（需要用 diagnose/抽帧统计回归验证）。
- **质量层面（处理效果上限）**：真正决定“处理效果能否接近 Spectacular Rec”的关键，通常不是文件名对齐，而是：
  - **时间同步的精度与稳定性**（帧/IMU 时间轴一致、抖动可控、尽量不丢帧）
  - **相机几何真值**（畸变、`imuToCamera` 外参）与 **深度质量**（滤波/置信度/异常值）
- **仓库内证据**：`docs/scene_20260413_113659_diagnose.html` 曾因加速度缺少重力（模长 ~1）而失败；`docs/scene_20260413_161617_diagnose.html` 显示整体已通过（Passed）。这说明“单位/语义正确”对工具链结果是硬门槛。

---

## 1. 对齐基线与验收口径（建议用同一把尺子）

### 1.1 基线样例（你现在对齐的是谁）

仓库内置的 Spectacular Rec 风格样例目录：

- `docs/recording_2026-03-18_19-14-19/`

该样例的关键特征（建议作为验收标准）：

- `data.mov`：H.264 视频，**无音轨**，约 30fps
- `frames2/*.png`：深度逐帧 PNG，**16-bit grayscale**，分辨率 **256×192**，像素单位 mm
- `data.jsonl`：IMU + 帧元数据（JSON Lines），`frames[1]` 为 `gray + depthScale=0.001 + aligned=true`
- `calibration.json`：`cameras` 通常为 2 项（camera0 RGB / camera1 depth-gray 语义），且 depth 的逐帧内参写法与 RGB 一致
- `metadata.json`：极简（`device_model` / `platform`）

> 说明：你这边的录制会话允许 **保留音频**。这意味着你们的 `data.mov` 与 Spectacular 样例在“容器 stream 数量”上不完全一致；下游若要求严格一致，可以在导出/上传阶段提供“无音轨版本”（见 §7.4）。

### 1.2 诊断报告（建议作为“质量验收”入口）

仓库里已经保存了用 Spectacular AI diagnose 工具生成的 HTML 报告，可直接作为对齐/质量回归用例：

- `docs/scene_20260413_113659_diagnose.html`（FAILED：加速度语义不对、时间戳抖动告警）
- `docs/scene_20260413_161617_diagnose.html`（Passed：相机/IMU 均通过）

你后续每次改动采集链路，都建议至少跑一次 diagnose，并保留一份“可回归”的报告。

---

## 2. 当前采集链路（代码层）到底做了什么

> 下面描述对应当前仓库实现（以 `ios/Runner/SlamRecordingSession.swift` 为准）。

### 2.1 采集模式与输出文件

- **主路视频**：`data.mov`（H.264；可选包含音频轨）
- **深度序列**：`frames2/%08d.png`（逐帧深度 PNG，16-bit gray，mm）
- **时序数据**：`data.jsonl`（传感器行 + 帧行）
- **标定**：`calibration.json`
- **元数据**：`metadata.json`

### 2.2 分辨率 / 帧率 / 画质相关开关

- 目标视频分辨率：**1920×1440**
- 目标帧率：**30fps**（通过 `activeVideoMin/MaxFrameDuration` 锁定）
- 关闭 HDR（避免动态范围与色彩处理引入不稳定）
- 关闭视频防抖（防抖会对图像做时域/几何处理，可能伤害 VIO/重建的一致性）
- 视频输出像素格式：`420YpCbCr8BiPlanarFullRange`

### 2.3 时间轴（非常关键）

- 帧行 `time`：用首帧时刻的 `CACurrentMediaTime()` 作为锚点 + 视频 PTS 相对增量（保证与系统单调时钟同轴）
- IMU/磁力计行 `time`：使用 Core Motion 的 `timestamp`（同样基于系统启动后的单调时钟）

这套策略的目标是：**视频帧与 IMU 的 time 在同一条“秒”时间轴上**，下游可直接融合。

---

## 3. 已对齐项（与你的 Spectacular 样例一致/高度接近）

### 3.1 `metadata.json`：最小 schema

当前写入为最小集合（与样例一致）：

- `device_model`
- `platform`

### 3.2 `calibration.json`：双 camera 与 `imuToCamera` 写法

- `cameras` 会根据模式写 1 或 2 项；在深度模式下会写出 camera1
- depth-gray（camera1）在样例里常见的 `imuToCamera[0][3] = 0.1` 占位平移也已对齐（用于“形态对齐”，不等于真值）

### 3.3 `data.jsonl`：`frames[1]` 的样例形态

深度模式下：

- `frames[1].colorFormat = "gray"`
- `frames[1].depthScale = 0.001`
- `frames[1].aligned = true`
- 当 `aligned=true` 时，`frames[1].calibration` 与 `frames[0].calibration` 使用同一组内参主项（fx/fy/cx/cy）

### 3.4 `frames2/*.png`：16-bit gray + mm 语义

- PNG 色彩类型：grayscale
- 位深：16
- 像素值语义：mm（`depthMeters = pngValue * 0.001`）

---

## 4. 仍可对齐/可显著提升处理效果的项（按优先级）

### P0（会直接影响“能不能跑通 / 结果是否明显变差”）

1) **避免丢帧（比码率更重要）**  
   下游 VIO/重建对“稳定 30fps + 连续帧”非常敏感。建议持续关注：
   - `data.mov` 的实际帧间隔是否稳定（不要出现大量 16.7ms / 50ms 的短长帧混杂）
   - 录制过程中是否因写盘/编码背压导致跳帧

2) **深度分辨率已对齐为 256×192（样例口径），建议持续回归抽检**  
   你反馈“深度分辨率之前已经修改好”，当前代码也在深度格式选择上**优先锁定 256×192**。  
   仓库内仍能看到历史录制的 320×240（如 `docs/scene_20260413_161617/frames2/00000000.png`），这更像是“旧数据/旧版本录制产物”。  
   建议：发版后仍用“读取 PNG IHDR”脚本抽检 1～2 个样本，避免后续改格式选择逻辑时回归。

### P1（影响“处理效果上限”，也是 Spectacular Rec 可能更强的原因）

1) **畸变模型/系数（尤其是画面边缘）**  
   目前以 `pinhole` + fx/fy/cx/cy 为主，缺少畸变真值。若你的下游算法对畸变敏感（或视场较大），建议引入：
   - `AVCameraCalibrationData` 的畸变信息（查表或拟合为系数）
   - 或离线标定（固定分辨率/对焦策略下的张正友标定）

2) **`imuToCamera` 真值（强影响 VIO/重建）**  
   样例里出现的 `imuToCamera` 多数是“形态占位/约定矩阵”，不等于真值。  
   若你发现“同样场景 Spectacular Rec 轨迹更稳”，很大概率是它的 IMU-相机外参/噪声模型更好。  
   可行路线：
   - 离线手眼标定（推荐）
   - 或引入能联合估计外参的工具链（成本更高）

3) **深度质量（滤波/置信度/异常值）**  
   当前导出的是深度的 mm 量化结果；若需要更接近 Spectacular 的深度使用体验，可考虑：
   - 打开/对比深度滤波（噪声 vs 细节的 trade-off）
   - 写入深度置信度（如果设备/API 可提供）或做简单异常值剔除

### P2（工程兼容性/可维护性）

1) **会话目录“合同”隔离**  
   你的 App 现在还有上传/分组用的业务文件（如 `upload_context.json`）可能出现在会话目录或 ZIP 中。  
   若你希望“录制目录直接丢给 Spectacular 工具链不带任何歧义”，建议：
   - 将业务文件移动到隐藏目录或同级 `.meta/` 下
   - 或在导出/ZIP 合同中默认排除（只保留 Spectacular 合同文件）

2) **长录制的内存与可靠性**  
   当前 JSONL 在内存中累积，停止后一次性落盘。录制时间变长时可能带来内存峰值与失败风险。  
   如果你计划录制分钟级/更长，建议改为“边录边写（streaming JSONL）”。

---

## 5. 想达到“和 Spectacular Rec 一样好”的实操建议（采集端 + 处理端）

### 5.1 采集端（你能立刻做、收益最大的）

1) **保持 30fps 稳定**：尽量避免过暗环境（会导致曝光时间变长 → 运动模糊）、避免发热降频。  
2) **按 SLAM 友好的运动方式采集**：匀速移动 + 缓慢转动，减少快速甩动与强抖动。  
3) **每次改采集逻辑都跑一次 diagnose**：把“通过 diagnose”作为发布门槛之一。

### 5.2 处理端（别让“对齐数据”输在读法上）

1) **确认 depthScale 的解释一致**：本项目约定 `depthMeters = pngValue * 0.001`。  
2) **正确处理 aligned depth 的分辨率差**：depth PNG 为 256×192，而 RGB 为 1920×1440；如果你的处理代码假设两者同分辨率，需要显式做缩放映射。  
3) **检查帧号与 PNG 文件名是否一一对应**：`frames2/%08d.png` 与 JSONL 的 `number` 必须可对上。

### 5.3 如果你追求“质量上限接近 Spectacular Rec”

- 做一次“机型级”的离线标定：畸变 + `imuToCamera`。  
  这通常是提升 VIO/重建质量的最大杠杆之一，比微调 JSON 字段顺序更有效。

---

## 6. 相关仓库文档（建议搭配阅读）

- `docs/SpectacularRec对齐参数与修复清单.md`（逐项对齐 checklist）
- `docs/Spectacular_AI_DATA_FORMAT_中文.md`（Spectacular AI 官方 DATA_FORMAT 翻译）
- `docs/标定真值缺口与可行方案.md`（畸变与 `imuToCamera` 真值路线）
- `docs/scene_20260413_161617_diagnose.html`（通过用例）
- `docs/scene_20260413_113659_diagnose.html`（失败用例：帮助你理解哪些错误会直接“毁掉处理效果”）

---

## 7. 你关心的三件事：畸变、`imuToCamera`、深度质量 —— 捕获软件怎么做才靠谱

你说得很关键：你的 App 本质上是**采集器**，不是 SLAM/VIO 算法本体。  
所以更现实的路线是：**把“难的几何真值”拆成可落地的来源**，并明确哪些能直接从 iOS API 得到，哪些必须靠离线标定/工具链获得。

下文按“你能拿到什么 → 怎么写进数据 → 跟 Spectacular 的关系”来解释。

### 7.1 畸变模型/系数：你有哪些可选路线

#### 路线 A（最稳、最不容易出错）：继续 pinhole，不写畸变

Spectacular 的样例本身就是 `model: pinhole` 且没有畸变系数；对很多 iPhone 场景（尤其是主摄）这是可接受的近似。  
如果你下游算法（或 Spectacular diagnose / 你们自研处理）已经能稳定跑通，并且结果质量主要受“丢帧/抖动/外参”影响，那么优先别引入畸变字段，避免**写错比不写更糟**。

#### 路线 B（你有深度/标定数据时可做）：导出“畸变查表（LUT）”作为附加文件

在 iOS 的深度链路上，你有机会从 `AVCameraCalibrationData` 获取畸变相关信息（常见形态是查找表而非简单的 4/5 个系数），例如：

- `lensDistortionLookupTable` / `inverseLensDistortionLookupTable`
- `lensDistortionCenter`
- `intrinsicMatrix` + `intrinsicMatrixReferenceDimensions`

这类数据非常“真值友好”，但**不一定能直接塞进 Spectacular `distortionCoefficients`**。

推荐做法（捕获软件视角）：

1) 保持 `calibration.json` 兼容（仍写 pinhole + fx/fy/cx/cy）。  
2) 新增一个“扩展标定文件”，例如：`calibration_extras.json` + 若干二进制 LUT 文件：  
   - `distortion_lut_cam0.bin` / `distortion_lut_cam0_inverse.bin`  
   - `distortion_lut_cam1.bin` / `...`（如果你也需要 depth 的查表）
3) 在 `calibration_extras.json` 里写清楚：LUT 的布局、分辨率、像素坐标约定、以及如何将其用于 undistort。

这样做的好处是：  
你不必为了对齐样例而“强行把 LUT 拟合成系数”，但下游若需要畸变校正，依然有高保真信息可用。

#### 路线 C（追求通用算法兼容）：离线标定得到系数（OpenCV / Kalibr），写入 `calibration.json`

当你的下游处理希望使用标准畸变模型（Brown-Conrady / Kannala-Brandt4 等）时，最常见的方式是**离线标定**：

- 采集：拍摄标定板（棋盘格/圆点板/AprilGrid），覆盖全视场、多角度、不同距离；必须固定与录制一致的分辨率与镜头配置。
- 估计：在 PC 上用 OpenCV 或 Kalibr 拟合内参 + 畸变系数。
- 固化：把结果按“机型 + 分辨率 + 摄像头类型”固化成一份标定配置，随 App 发布（或首次运行下发）。
- 写入：将 `model` 与 `distortionCoefficients` 写进 `calibration.json`（或 per-frame cameraParameters）。

> 注意：离线标定非常依赖“分辨率完全一致 + 不变焦 + 尽量稳定对焦策略”。一旦你的视频分辨率/裁剪/变焦策略变了，之前的畸变系数就不再可靠。

---

### 7.2 `imuToCamera`：为什么 iOS 很难直接给你“真值”，以及你能怎么拿到

#### 现实约束：iOS 没有公开 API 直接给“IMU→相机”的刚体外参真值

这就是你现在 `calibration.json` 里 `imuToCamera` 只能写“约定矩阵/占位”的根本原因（仓库文档 `docs/标定真值缺口与可行方案.md` 也有详细解释）。

#### 捕获软件可落地的方案：离线 Camera-IMU 标定（推荐）

如果你真的想要“处理效果上限”显著接近 Spectacular，`imuToCamera` 往往是最值钱的一项真值。

捕获软件侧你需要做的是：**提供足够干净的数据给标定工具**，而不是在手机端实现复杂算法。

一条典型路线（概念步骤）：

1) 录制一段“标定序列”：对着 AprilGrid/标定板，做多方向转动与平移（保证激励充分、可观测性好）。  
2) 导出：  
   - 相机帧（最好是逐帧无损或高质量图像；如果只能从 H.264 抽帧，精度会打折）  
   - IMU（gyro/accel，准确时间戳）  
3) 在 PC 上用 Kalibr 等工具跑 camera-imu calibration，得到 `T_cam_imu`（或 `T_imu_cam`）。  
4) 将结果固化为你们的 `imuToCamera` 写入逻辑（按机型/分辨率选择）。

> 关键点：`imuToCamera` 必须与“你 JSONL 中 IMU values 的坐标系定义”和“相机帧坐标系定义”完全一致。否则写了真值也会被用错。

---

### 7.3 深度质量：你能做的不是“更亮的灰度视频”，而是给下游更多可用信息

你当前的 `frames2/*.png` 是 16-bit mm 深度，非常适合做一个统一合同；但“质量”往往取决于你是否还能提供以下信息：

1) **原始 Float 深度（可选但很有价值）**  
   仅 16-bit mm 会量化并丢失一些细节/异常值语义。若下游希望自己做滤波/置信度处理，建议额外输出：  
   - `depth_raw/00000000.f32`（或压缩后的二进制），存放 `DepthFloat32` 深度（米）  
   这样 `frames2` 负责“合同与可视化”，`depth_raw` 负责“算法真值输入”。

2) **置信度（Confidence）/ 有效性 Mask（如果来源能提供）**  
   一些深度来源（例如 ARKit 的 `ARFrame.sceneDepth` / `ARFrame.smoothedSceneDepth`）会提供 per-pixel 的 `confidenceMap`。  
   如果你能把 confidence 存下来，下游可以显著减少飞点与误差传播。

3) **滤波开关与版本信息**  
   深度滤波不是越强越好：  
   - 强滤波：噪声小但细节/边缘变糊  
   - 弱滤波：细节多但噪声大  
   建议你把“是否滤波/用的哪条深度源/深度格式”写入扩展元数据，便于下游做条件分支与回归比较。

---

### 7.4 你要保留音频：如何既保留又不破坏 Spectacular 兼容性

建议采用“两层合同”的思路：

- **录制原始会话**：保留音频（满足你的业务诉求）。  
- **导出/上传给工具链的会话**：提供一个开关：
  - `keep_audio=true`：上传原始 `data.mov`（带音轨）
  - `keep_audio=false`：上传一个“去音轨”的 `data.mov`（仅视频流），以满足严格脚本/工具链

这样你不需要牺牲音频，也不会因为个别工具的假设导致全链路卡住。

**无代码改动的推荐工作流（本地导出一个“给 Spectacular CLI 的目录”）：**

1) 复制一份会话目录作为 CLI 输入目录（避免破坏原始数据）。  
2) 在复制后的目录里，把 `data.mov` 替换为“无音轨版本”（仅视频流）。常见做法是用 ffmpeg 直接 copy 视频流并移除音频：

```bash
ffmpeg -i data.mov -an -c:v copy data_noaudio.mov
```

然后将 `data_noaudio.mov` 重命名为 `data.mov`（或按你的脚本约定替换）。  
这样 Spectacular CLI 永远看到“样例合同一致”的 `data.mov`，而你仍保留原始带音轨文件用于额外处理。

**有代码改动的推荐形态（更干净、长期维护成本更低）：**

- `data.mov` 永远保持**纯视频**（Spectacular-compatible）
- 音频单独落盘为 `audio.m4a` / `audio.wav`（sidecar），并在扩展元数据中写明格式与时间对齐方式

---

## 8. Spectacular Rec 可能是怎么做到“效果更好”的（抓住本质，而不是字段）

Spectacular Rec/SDK 属于完整的 VIO/SLAM 产品栈；它的优势通常来自这些方面（这里是工程推断，供你对齐方向用）：

1) **更强的时间同步与传感器建模**：对 IMU 噪声、时间偏置、帧间抖动有更强的鲁棒性。  
2) **更可信的标定**：他们要么有离线标定工具链，要么在算法里做自标定/联合估计，让 `imuToCamera` 与相机模型更贴近真值。  
3) **更成熟的深度使用策略**：选择深度源、滤波与置信度处理，使得深度在重建里“可用而不是好看”。  
4) **端到端质量控制**：在 Recorder 侧就避免 HDR/防抖/变焦等会破坏几何一致性的设置，并用诊断工具做回归。

对你来说，最现实的对齐策略是：

- 采集端先把“时间轴 + 稳定帧率 + 深度合同”做到可复现、可回归；  
- 然后用离线标定补上“畸变 + `imuToCamera`”；  
- 最后再谈更高阶的“深度置信度/原始深度侧车”，把下游算法的上限释放出来。

# Recording 参数来源说明（当前 P0 + P1 实现）

本文说明：**在一次会话目录里，哪些字段属于「拍摄或系统 API 直接得到」**，哪些属于**轻量封装/时间对齐**，哪些属于**占位或启发式**（需要后续标定或 P2 才能逼近真值）。

- **范围**：与 [`MVP开发优先级.md`](MVP开发优先级.md) 中 **P0**（最小闭环）与 **P1**（质量与可复现）一致：单目 `data.mov`、IMU、停止时排序落盘的 `data.jsonl`、对焦/曝光锁定、`calibration.json` 占位、`metadata.json`（含 P1 说明字段）。
- **应用层**：[`lib/app/spatial_data_recorder_app.dart`](../lib/app/spatial_data_recorder_app.dart) 仅负责 UI 与调用原生录制；**不生成** recording 参数。实际写入由 iOS **`SlamRecordingSession`**（`ios/Runner/SlamRecordingSession.swift`）完成。

下文「直接」指：**无需离线 SLAM、BA、深度估计、张正友标定等算法**；可能仍包含简单的减法归一化、顺序计数或 JSON 序列化。

**对照表**（设备/API 能力与 recording 落盘项一览）：[`Recording采集与落盘对照表.md`](Recording采集与落盘对照表.md)。

---

## 一、可直接视为「采集链路产出」的

| 产物/字段 | 说明 |
|-----------|------|
| **`data.mov` 视频内容** | 来自 `AVCaptureVideoDataOutput` 的实时帧，经 `AVAssetWriter` 编码为 H.264；无麦克风轨（符合 MVP 约定）。 |
| **视频宽高** | 由首帧 `CVPixelBuffer` 的宽度、高度决定，与写入 MOV 的分辨率一致。 |
| **JSONL：`sensor.type: gyroscope` 的 `values`** | `CMDeviceMotion.rotationRate`（**rad/s**），Core Motion 在回调中直接给出。 |
| **JSONL：`sensor.type: accelerometer` 的 `values`** | 由 `gravity` 与 `userAcceleration` 分量相加得到的三轴加速度（**m/s²**，含重力，与设备运动参考系一致）；仍为运行时 API 输出，**非**自建滤波器或优化器结果。 |
| **JSONL：帧行的 `time`** | 由 `CMSampleBuffer` 的 `presentationTimeStamp` 相对**首帧视频 PTS** 换算为秒；来源是采集管线时间戳，仅做相对首帧的归一化。 |
| **JSONL：帧行的 `number`** | 按收到并写入视频的帧顺序递增，与 `data.mov` 中帧顺序一致。 |
| **JSONL：帧行的 `frames[0].cameraInd`** | 固定为单目主相机索引 `0`，属格式约定。 |
| **`metadata.json`：`device_model`** | 通过 `sysctl` 读取 `hw.machine`（机型内部代号），系统接口可得。 |
| **`metadata.json`：`platform`** | 当前实现固定为 `"ios"`，表示数据来源平台。 |
| **`metadata.json`：`imu_temperature_status`** | 固定为 **`unavailable_no_public_api_ios`**：Core Motion **不提供**与 Spectacular 样例一致的 IMU 芯片温度；**不写入**伪造 `imuTemperature` 行。 |
| **`metadata.json`：`p1`** | 对象，记录 P1 行为标记（如 `jsonl_sorted_by_time`、`focus_exposure_locked_after_delay_s`），便于复现与排障。 |

---

## 二、需代码做「对齐/封装」、但不属于复杂算法的

| 字段/行为 | 说明 |
|-----------|------|
| **IMU 行的 `time`** | 使用 `CACurrentMediaTime()` 减去与视频首帧对齐的 `timeOriginMedia`，使 IMU 与录制段落在同一相对时间轴上；属于**显式选定的时钟与减法**，不是视觉重建算法。 |
| **JSONL 落盘顺序（P1）** | 采集过程中将各行缓存在内存；**会话结束、停止采集后**按根级 **`time` 升序**写出；同一时间戳下稳定次序为：**陀螺仪 → 加速度计 → 视频 `frames` 行**（与 [`Spectacular_AI_DATA_FORMAT_中文.md`](Spectacular_AI_DATA_FORMAT_中文.md) 推荐的全局有序一致）。 |
| **缓冲刷盘（P1）** | 录制中**不**对每一行立即 `FileHandle` 写入，结束时一次性写入 `data.jsonl`，减少录制中 I/O 抖动。 |
| **对焦 / 曝光 / 白平衡锁定（P1）** | 会话开始后短延迟（约 **0.2 s**）再调用 `setFocusModeLocked` → `setExposureModeCustom` →（若支持）**白平衡锁定**，减少录制段内对焦与曝光漂移；见 [`Flutter-iOS-SLAM数据采集应用开发指南.md`](Flutter-iOS-SLAM数据采集应用开发指南.md) §4.1。首帧前若尚未完成锁定，**开头若干帧**仍可能处于 AE/AF 收敛过程（工程折中）。 |
| **相机内参矩阵附件** | 若连接支持，已开启 **`isCameraIntrinsicMatrixDeliveryEnabled`**，便于后续迭代将真实内参写入 `calibration.json`（当前仍未解析该附件）。 |

---

## 三、当前**不是**拍摄直接内参、属于占位或启发式的

[`MVP开发优先级.md`](MVP开发优先级.md) 已说明 P0 接受「占位/静态内参」。实现上对应为：

| 字段 | 说明 |
|------|------|
| **`calibration.json`：焦距 `focalLengthX/Y`** | 使用 `0.72 × imageWidth` 等**经验比例**，非从相机内参标定或 `CMSampleBuffer` 内参附件解析。 |
| **`calibration.json`：主点 `principalPointX/Y`** | 取图像中心 `(width/2, height/2)`，为常见近似。 |
| **`calibration.json`：`imuToCamera`** | 使用 **4×4 单位矩阵** 占位，非手眼标定或出厂外参。 |
| **`calibration.json`：`model: pinhole`** | 格式约定；畸变系数等若未写入则依赖下游默认假设。 |

若需「与设备光学参数一致」的内参/外参，见 [`标定真值缺口与可行方案.md`](标定真值缺口与可行方案.md)。

---

## 四、P0/P1 未包含、故本应用当前**不会**直接产出项

与 [`MVP开发优先级.md`](MVP开发优先级.md) **「不包含」/ P2** 一致，以下**不属于**当前 recording 的直接采集结果：

- 磁力计行、第二相机/深度、`frames2` 目录、样例中每帧内嵌的完整双路标定与 `depthScale` 等（多属 **P2 与样例对齐** 范畴）。
- **`imuTemperature` JSONL 行**：无公开 iOS API，当前**不产出**。

---

## 五、小结

| 类别 | 内容 |
|------|------|
| **偏「直接」** | 视频流、分辨率、陀螺仪/加速度采样值、视频时间戳导出的帧时间与序号、机型 metadata。 |
| **偏「工程对齐」** | IMU 相对时间、JSONL 会话末排序与缓冲写入、对焦/曝光/白平衡锁定策略。 |
| **偏「占位」** | `calibration.json` 中焦距、主点、`imuToCamera` 的当前数值。 |

修订录制管线时，建议同步更新本文与 [`MVP开发优先级.md`](MVP开发优先级.md)，避免文档与 `SlamRecordingSession.swift` 行为不一致。

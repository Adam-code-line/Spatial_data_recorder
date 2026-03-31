# Recording 参数来源说明（当前 P0 实现）

本文说明：**在一次会话目录里，哪些字段属于「拍摄或系统 API 直接得到」**，哪些属于**轻量封装/时间对齐**，哪些属于**占位或启发式**（需要后续标定或 P2 才能逼近真值）。

- **范围**：与 [`MVP开发优先级.md`](MVP开发优先级.md) 中 **P0** 一致（单目 `data.mov`、IMU、`calibration.json` 占位、`metadata.json`）。
- **应用层**：[`lib/app/spatial_data_recorder_app.dart`](../lib/app/spatial_data_recorder_app.dart) 仅负责 UI 与调用原生录制；**不生成** recording 参数。实际写入由 iOS **`SlamRecordingSession`**（`ios/Runner/SlamRecordingSession.swift`）完成。

下文「直接」指：**无需离线 SLAM、BA、深度估计、张正友标定等算法**；可能仍包含简单的减法归一化、顺序计数或 JSON 序列化。

**对照表**（设备/API 能力与 recording 落盘项一览）：[`Recording采集与落盘对照表.md`](Recording采集与落盘对照表.md)。

---

## 一、可直接视为「采集链路产出」的

| 产物/字段 | 说明 |
|-----------|------|
| **`data.mov` 视频内容** | 来自 `AVCaptureVideoDataOutput` 的实时帧，经 `AVAssetWriter` 编码为 H.264；无麦克风轨（符合 MVP 约定）。 |
| **视频宽高** | 由首帧 `CVPixelBuffer` 的宽度、高度决定，与写入 MOV 的分辨率一致。 |
| **JSONL：`sensor.type: gyroscope` 的 `values`** | `CMDeviceMotion.rotationRate`（rad/s），Core Motion 在回调中直接给出。 |
| **JSONL：`sensor.type: accelerometer` 的 `values`** | 由 `gravity` 与 `userAcceleration` 分量相加得到的三轴加速度（m/s² 量级，与设备运动参考系一致）；仍为运行时 API 输出，**非**自建滤波器或优化器结果。 |
| **JSONL：帧行的 `time`** | 由 `CMSampleBuffer` 的 `presentationTimeStamp` 相对**首帧视频 PTS** 换算为秒；来源是采集管线时间戳，仅做相对首帧的归一化。 |
| **JSONL：帧行的 `number`** | 按收到并写入视频的帧顺序递增，与 `data.mov` 中帧顺序一致。 |
| **JSONL：帧行的 `frames[0].cameraInd`** | 固定为单目主相机索引 `0`，属格式约定。 |
| **`metadata.json`：`device_model`** | 通过 `sysctl` 读取 `hw.machine`（机型内部代号），系统接口可得。 |
| **`metadata.json`：`platform`** | 当前实现固定为 `"ios"`，表示数据来源平台。 |

---

## 二、需代码做「对齐/封装」、但不属于复杂算法的

| 字段/行为 | 说明 |
|-----------|------|
| **IMU 行的 `time`** | 使用 `CACurrentMediaTime()` 减去与视频首帧对齐的 `timeOriginMedia`，使 IMU 与录制段落在同一相对时间轴上；属于**显式选定的时钟与减法**，不是视觉重建算法。 |
| **JSONL 多行交错** | 陀螺仪、加速度计与 `frames` 行按采集回调顺序追加；**未**保证全局按 `time` 升序（[`MVP开发优先级.md`](MVP开发优先级.md) **P1** 建议再优化排序与刷盘）。 |

---

## 三、当前**不是**拍摄直接内参、属于占位或启发式的

[`MVP开发优先级.md`](MVP开发优先级.md) 已说明 P0 接受「占位/静态内参」。实现上对应为：

| 字段 | 说明 |
|------|------|
| **`calibration.json`：焦距 `focalLengthX/Y`** | 使用 `0.72 × imageWidth` 等**经验比例**，非从相机内参标定或 `AVCaptureDevice` 精确内参读取。 |
| **`calibration.json`：主点 `principalPointX/Y`** | 取图像中心 `(width/2, height/2)`，为常见近似。 |
| **`calibration.json`：`imuToCamera`** | 使用 **4×4 单位矩阵** 占位，非手眼标定或出厂外参。 |
| **`calibration.json`：`model: pinhole`** | 格式约定；畸变系数等若未写入则依赖下游默认假设。 |

若需「与设备光学参数一致」的内参/外参，需另行：**读取系统提供的标定相关 API**（若可用）或 **离线标定流程**，已超出「直接拍摄得到、不经算法」的狭义范围。

---

## 四、P0 未包含、故本应用当前**不会**直接产出项

与 [`MVP开发优先级.md`](MVP开发优先级.md) **「不包含」**一致，以下**不属于**当前 recording 的直接采集结果：

- 磁力计行、第二相机/深度、`frames2` 目录、样例中每帧内嵌的完整双路标定与 `depthScale` 等（多属 **P2 与样例对齐** 范畴）。

---

## 五、小结

| 类别 | 内容 |
|------|------|
| **偏「直接」** | 视频流、分辨率、陀螺仪/加速度采样值、视频时间戳导出的帧时间与序号、机型 metadata。 |
| **偏「工程对齐」** | IMU 相对时间、JSON 行组织与顺序策略。 |
| **偏「占位」** | `calibration.json` 中焦距、主点、`imuToCamera` 的当前数值。 |

修订录制管线时，建议同步更新本文与 [`MVP开发优先级.md`](MVP开发优先级.md)，避免文档与 `SlamRecordingSession.swift` 行为不一致。

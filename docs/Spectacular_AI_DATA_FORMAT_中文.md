# 数据格式（Spectacular AI DATA_FORMAT 中文说明）

> 原文：<https://github.com/SpectacularAI/docs/blob/main/other/DATA_FORMAT.md>  
> 下文为说明性译文；**字段名、文件名、JSON、代码与单位缩写保持英文**，与规范一致。

---

## 数据集文件夹

每个数据集（dataset）即传感器数据的**一次连续录制**，对应**一个文件夹**，其中包含：

- `data.jsonl`，格式见下文 [JSONL 格式](#jsonl-格式)。
- `data.mkv`（或其它视频扩展名），单目相机。
- （可选）`data2.mkv`，第二路相机，用于立体/深度录制。
- `calibration.json`，见下文 [标定格式](#标定格式)。
- （可选）`vio_config.yaml`，Spectacular AI SDK 的算法参数。

---

## JSONL 格式

本节定义基于 [JSON Lines](https://jsonlines.org/) 的数据格式。该格式既可包含作为**输入**的传感器数据，也可包含不同 **VIO 方法产出的位姿估计**。

### 时间戳

凡描述带时序的数据，根级应包含 `time` 字段，单位为**秒**。整份 JSONL **最好**按这些时间戳**升序**排列。时间戳可从任意值起算，包括负数；从接近 0 开始可减少浮点精度带来的潜在问题。

### 惯性传感器（IMU）

IMU 与其它「N 轴」传感器在根级使用 `sensor` 字段，其下包含 `type` 与 `values`。`values` 的单位：`accelerometer` 为 m/s²，`gyroscope` 为 rad/s，`magnetometer` 为 μT，`imuTemperature` 为 K。

### 相机帧

对 `data.mp4` 中的每一帧（若为立体/深度且存在完美同步的 `data2.mp4`，则两路各对应一项），应有一条根级含 `frames` 的行；`frames` 数组列出各相机的输出。`number` 从 0 起，每帧递增 1。`cameraInd` 为 0 表示 `data.mp4`，为 1 表示 `data2.mp4`。可使用 `cameraParameters` 指定**逐帧**参数；若不指定，则使用 `calibration.json` 中的常量。因此，单目最小示例如下：

```
{ "frames": [{ "cameraInd": 0 }], "number": 0, "time": 0.0 }
```

### GNSS

根级定义 `gps`，包含 `longitude`、`latitude`、`altitude`（米），采用 [地理坐标系](https://en.wikipedia.org/wiki/Geographic_coordinate_system)。`accuracy` 无严格统一定义，多数情况下可理解为某置信度对应的距离（米）。`altitude` 还可选配 `verticalAccuracy` 表示精度。

### 真值与 VIO 输出

根级可使用 `groundTruth`，或某 **VIO 方法名**作为键；其子字段包含 `position`（即文档中的 `t`）以及可选的 `orientation`（`q`）。位置单位为米，**负 z 轴沿重力方向**。姿态为单位四元数。二者共同定义 4×4 矩阵 `T = [R(q), t; 0, 1]`，将齐次设备坐标 `p_d` 左乘变换到世界坐标 `p_w`：`p_w = T * p_d`。

### 激光雷达

`lidar` 字段为对象，含 `model`（数据类型）及 `dataFile`（相对路径，指向包含点云测量的二进制文件）。

#### 模型：`"RoboSense M1 XYZIRT"`

以下为该模型二进制布局的 C++ 头文件定义；二进制文件即该结构体数组。除 **时间** 已与其它数据源对齐外，其余可视为来自激光雷达的原始数据：

```cpp
#pragma pack(push)
#pragma pack(1)
struct LidarRoboSenseXYZIRT {
  float x;
  float y;
  float z;
  uint8_t intensity;
  uint16_t ring;
  double timestamp;
};
#pragma pack(pop)
```

在 C++ 中可按如下方式读取（假设 `jsonlLine` 为当前 JSONL 行）：

```cpp
std::ifstream lidarFile(jsonlLine["lidar"]["dataFile"].c_str(), std::ios::binary);
LidarRoboSenseXYZIRT d;
while (lidarFile.read(reinterpret_cast<char*>(&d), sizeof(LidarRoboSenseXYZIRT))) {
  // Do something with single lidar point
}
```

### `data.jsonl` 示例

```
{"groundTruth":{"position":{"x":-0.007567568216472864,"y":0.022782884538173676,"z":0.00817866250872612},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.444770263671875}
{"sensor":{"type":"accelerometer","values":[-0.03824593499302864,9.121655464172363,-2.983182907104492]},"time":1.43846240234375}
{"sensor":{"type":"gyroscope","values":[0.003195890923961997,-0.17364339530467987,0.015979453921318054]},"time":1.44976953125}
{"sensor":{"type":"imuTemperature","values":[292.8961]},"time":1.44976953125}
{"groundTruth":{"position":{"x":-0.007713410072028637,"y":0.022989293560385704,"z":0.008272084407508373},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.449769287109375}
{"frames":[{"cameraInd":0,"cameraParameters":{"focalLengthX":284.929992675781,"focalLengthY":285.165496826172,"principalPointX":416.4547119140625,"principalPointY":395.77349853515625,"distortionModel":"KANNALA_BRANDT4","distortionCoefficients":[-0.004973,0.03975,-0.0374,0.006239]},"imuToCamera":[[0.01486,0.9995,-0.02577,0.06522],[-0.9998,0.01496,0.003756,-0.0207],[0.00414,0.02571,0.9996,-0.008054],[0,0,0,1]],"time":1.436207275390625},{"cameraInd":1,"cameraParameters":{"focalLengthX":284.559509277344,"focalLengthY":284.4418029785162,"principalPointX":410.81329345703125,"principalPointY":394.1506042480469,"distortionModel":"KANNALA_BRANDT4","distortionCoefficients":[-0.006496,0.04365,-0.04025,0.006813]},"imuToCamera":[[0.01255,0.9995,-0.02538,-0.0449],[-0.9997,0.01301,0.0179,-0.02056],[0.01822,0.02515,0.9995,-0.008638],[0,0,0,1]],"time":1.436207275390625}],"number":28,"time":1.436207275390625}
{"sensor":{"type":"gyroscope","values":[-0.025567127391695976,-0.16512103378772736,0.034089501947164536]},"time":1.4547685546875}
{"sensor":{"type":"imuTemperature","values":[292.8961]},"time":1.4547685546875}
{"groundTruth":{"position":{"x":-0.00783445406705141,"y":0.02315470017492771,"z":0.008362464606761932},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.45476806640625}
{"sensor":{"type":"gyroscope","values":[-0.07137490063905716,-0.1523374617099762,0.04793836548924446]},"time":1.45976806640625}
{"sensor":{"type":"imuTemperature","values":[292.8961]},"time":1.45976806640625}
{"groundTruth":{"position":{"x":-0.007959198206663132,"y":0.023323576897382736,"z":0.008457313291728497},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.459767333984375}
{"sensor":{"type":"accelerometer","values":[0.4015823304653168,9.446745872497559,-2.8301992416381836]},"time":1.4539404296875}
{"sensor":{"type":"gyroscope","values":[-0.12037855386734009,-0.12037855386734009,0.07457078248262405]},"time":1.46476708984375}
{"sensor":{"type":"imuTemperature","values":[292.8961]},"time":1.46476708984375}
{"groundTruth":{"position":{"x":-0.008127331733703613,"y":0.023527292534708977,"z":0.008570007979869843},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.464766357421875}
{"frames":[{"cameraInd":0,"cameraParameters":{"focalLengthX":284.929992675781,"focalLengthY":285.165496826172,"principalPointX":416.4547119140625,"principalPointY":395.77349853515625,"distortionModel":"KANNALA_BRANDT4","distortionCoefficients":[-0.004973,0.03975,-0.0374,0.006239]},"imuToCamera":[[0.01486,0.9995,-0.02577,0.06522],[-0.9998,0.01496,0.003756,-0.0207],[0.00414,0.02571,0.9996,-0.008054],[0,0,0,1]],"time":1.46955859375},{"cameraInd":1,"cameraParameters":{"focalLengthX":284.559509277344,"focalLengthY":284.4418029785162,"principalPointX":410.81329345703125,"principalPointY":394.1506042480469,"distortionModel":"KANNALA_BRANDT4","distortionCoefficients":[-0.006496,0.04365,-0.04025,0.006813]},"imuToCamera":[[0.01255,0.9995,-0.02538,-0.0449],[-0.9997,0.01301,0.0179,-0.02056],[0.01822,0.02515,0.9995,-0.008638],[0,0,0,1]],"time":1.46955859375}],"number":29,"time":1.46955859375}
{"sensor":{"type":"gyroscope","values":[-0.15979453921318054,-0.08735434710979462,0.08841964602470398]},"time":1.4697841796875}
{"sensor":{"type":"imuTemperature","values":[292.8961]},"time":1.4697841796875}
{"groundTruth":{"position":{"x":-0.007131610997021198,"y":0.022098174318671227,"z":0.008283869363367558},"orientation":{"w":0.53464,"x":-0.15299,"y":-0.826976,"z":-0.082863}},"time":1.469782958984375}
{"sensor":{"type":"gyroscope","values":[-0.18323107063770294,-0.06178722158074379,0.09481143206357956]},"time":1.474782958984375}
{"gps": {"accuracy": 4.0, "altitude": 14.18831106834269, "latitude": 60.173783793064594, "longitude": 24.906486344581662}, "time":1.474782958984375}
```

---

## 标定格式

相机内参与外参须通过 `calibration.json` 定义，包含如下字段：

- `cameras`：对象数组；单目一项，立体两项。
- `focalLengthX`：水平焦距。
- `focalLengthY`：垂直焦距。
- `principalPointX`（像素）：水平主点。
- `principalPointY`（像素）：垂直主点。
- `model`：例如 `pinhole`、`kannala-brandt4`、`brown-conrady` 等。
- `distortionCoefficients`：数组，长度依 `model` 而定。例如 `kannala-brandt4` 为 4 个数；`pinhole` 为 0 或 3（无畸变，或 OpenCV radtan 且仅部分径向分量）。
- `imuToCameraMatrix`：4×4 矩阵，齐次坐标变换为：`p_camera = T * p_imu`。
- `imageWidth`、`imageHeight`（像素）：焦距与主点所对应的图像尺寸。

说明：英文规范正文中列表项写为 `imuToCameraMatrix`，示例 JSON 使用键名 `imuToCamera`；以官方仓库最新 `DATA_FORMAT.md` 为准。

### `calibration.json` 示例

```
{
    "cameras": [
        {
            "distortionCoefficients": [
                -0.02772200817284449,
                0.0020816404470823564,
                -0.005219319585905603,
                0.00044346633058214575
            ],
            "focalLengthX": 547.5542611995533,
            "focalLengthY": 547.4728273665322,
            "imuToCamera": [
                [
                    -0.004028958399374893,
                    -0.9999835791608805,
                    0.0040754021655989925,
                    0.00026667580381220524
                ],
                [
                    -0.9999788711605716,
                    0.004049663285094152,
                    0.0050850230782564345,
                    0.03338442163595494
                ],
                [
                    -0.005101443584432566,
                    -0.004054828710638873,
                    -0.9999787665933124,
                    0.0011383544698017876
                ],
                [
                    0.0,
                    0.0,
                    0.0,
                    1.0
                ]
            ],
            "model": "kannala-brandt4",
            "principalPointX": 672.6648243249832,
            "principalPointY": 490.44200513757215,
            "imageWidth": 1344,
            "imageHeight": 972
        }
    ]
}
```

# Recording：设备/API 能采到的 vs 当前 recording 里实际有的

范围与 `[Recording参数来源说明.md](Recording参数来源说明.md)` 中 **P0** 一致。内参/外参占位含义见该文档第三节。


| 设备/API 能采到的                 | 当前 recording 里实际有的                                                                                                                    |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| 主相机视频帧（经编码管线）               | `data.mov`（H.264，无麦克风轨）                                                                                                               |
| 陀螺仪角速度 `rotationRate`       | `data.jsonl`：`sensor.type: gyroscope` 的 `values`                                                                                      |
| 重力 + 用户加速度合成的三轴加速度          | `data.jsonl`：`sensor.type: accelerometer` 的 `values`                                                                                  |
| 视频帧 `presentationTimeStamp` | `data.jsonl`：`frames` 行的 `time`（相对首帧秒）                                                                                                |
| 写入顺序上的帧序                    | `data.jsonl`：`frames` 行的 `number`                                                                                                     |
| 单目主相机索引（格式约定）               | `data.jsonl`：`frames[0].cameraInd`（固定 `0`）                                                                                            |
| IMU 回调时刻（可与媒体时钟对齐）          | `data.jsonl`：IMU 行的 `time`（相对 `timeOrigin` 秒）                                                                                         |
| 机型代号 `hw.machine`           | `metadata.json`：`device_model`                                                                                                        |
| —                           | `metadata.json`：`platform`（固定 `"ios"`）                                                                                                |
| 麦克风                         | 不写入                                                                                                                                   |
| 磁力计                         | 不写入                                                                                                                                   |
| 第二相机 / 深度 / `frames2` 等     | 不写入                                                                                                                                   |
| 精确相机内参、畸变（需标定或系统 API）       | `calibration.json`：`focalLengthX/Y`、`principalPointX/Y`、`model: pinhole`（当前为占位/经验值，详见 `[Recording参数来源说明.md](Recording参数来源说明.md)` 第三节） |
| 真实 IMU→相机外参（需标定）            | `calibration.json`：`imuToCamera`（当前为单位阵占位，详见 `[Recording参数来源说明.md](Recording参数来源说明.md)` 第三节）                                          |



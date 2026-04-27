# Spatial Data Recorder

一个用于 iOS 真机的空间数据采集工具。应用可在录制时同步保存视频与传感器数据，并支持录制后自动上传。

## 主要功能

- 实时相机预览
- 一键开始/停止录制
- 采集视频与 IMU 数据（陀螺仪、加速度计、磁力计）
- 生成结构化会话文件，便于后续重建或算法处理
- 录制完成后自动入队上传，失败可重试
- 支持录制会话浏览与手动补传

## 录制输出文件（典型）

- `data.mov`：主视频；开启音频时直接包含音轨
- `data2.mov`：第二路视频（设备/模式支持时生成）
- `data.jsonl`：时间序列数据（帧与传感器）
- `calibration.json`：相机标定参数
- `metadata.json`：设备与采集元信息

## 使用要求

- 需要 iOS 真机（模拟器不支持）
- 需要授予相机权限
- 开发环境需已安装 Flutter

## 快速开始

1. 安装依赖：`flutter pub get`
2. 连接 iPhone 真机并运行：`flutter run`
3. 首次进入应用后允许相机权限
4. 点击录制按钮开始/停止采集

## 上传配置

上传配置从 `.env` 读取，不在代码里硬编码后端地址和鉴权 Token。

1. 复制 `.env-example` 为 `.env`
2. 修改以下配置项：
	- `UPLOAD_BASE_URL`
	- `UPLOAD_PATH`
	- `UPLOAD_AUTH_TOKEN`
3. 确保后端 `AUTH_TOKENS` 与 `UPLOAD_AUTH_TOKEN` 一致

如果 `UPLOAD_BASE_URL` 使用 IPv6，请使用方括号包裹地址，例如：

- `http://[240e:3bb:2e71:310::1101]:8080`

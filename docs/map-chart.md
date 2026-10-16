# 海图、港区与设施符号

## 数据与显示

固定种子决定真实岛屿中心及半径。海域水深取最近岸线距离，每公里 50 m，最大 300 m；海图绘制 20／50／100／200 m。港区沿现有岸壁和防波堤计算距离，每公里 30 m，绘制 2／5／10 m。这是可复现的原型海图模型，不是真实测绘数据。

水深线只绘于可航水域，线条低于目标与告警。PPI 采用圆形裁切，岸线与导航碰撞使用相同的圆岛模型；局部岛屿进入量程时也能显示。海域和港区是不同尺度的现有场景，不把局部港口坐标直接作为海域公里坐标。

设施实例包含 `id`、`label`、`family`、`position_km`、`size_class`、`variant`；`chart_known` 控制海图可见性（旧调用默认已知），`role` 区分已实现回收机场与海图参考设施，港口可带 `component: warehouse`。海域 P1 是海图参考港，港内 P1 是出航场景的局部码头，两者使用不同实例 ID。

海域 AF1 对应现有机场回收位置；座舱保留原回收窗口与屏缘提示，避免重复机场图标。其他海图设施没有新增生产、补给或战斗交互。仓库、起重机和维修细节不改变现有碰撞、航速、任务或装备规则。

## 图标与层级

港口符号分别表达陆侧建筑与海侧栈桥；船坞表达修理池和维修设施。港内显示三仓库、控制楼、码头和船坞，各有编号。泊位编号放在航道侧。海域设施保留 32–48 逻辑像素；拥挤时移动符号并用引线连接实际位置，文字选择空闲方向，无空间时省略文字，保留符号。纸图使用缩略符号和海域坐标，不使用 CRT 后处理。

目标仍使用最后观测位置、航向及原余辉衰减；未知目标不显示隐藏型号、尺寸或形态。静态已知海图不冒充雷达实时探测。

## 验证入口

- `python tools/dev.py check`：全量现有回归与新增海图几何、图标、已知设施、量程边界和避让检查。
- `python tools/dev.py test --graphics --case m1_ui --case radar_visual --case flight_navigation --case unit_icon --case unit_library_flow --case harbor_navigation --case chart_features`：Compatibility 图形与输入回归。
- `python tools/dev.py capture harbor|game|chart-wide|chart-stale|chart-silent|flight-nav|library`：具体模式详见调试说明，可配置三种窗口和弱 CRT。

自动化和开发者截图审查不代替玩家无标签辨识测试。最终执行记录见本批视觉 QA 报告。

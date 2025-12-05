# WaterSalute-SASL

X-Plane 12 SASL3 (Lua) 插件，模拟飞机过水门仪式。两辆消防车驶向飞机并喷射水柱形成水拱门。

## 功能

- 通过菜单控制启动/停止 (Plugins → Water Salute)
- 自动检查飞机在地面且速度 < 40 节
- 消防车根据飞机翼展自动定位
- 8x8 消防车物理转向模型（阿克曼转向）
- 水粒子效果系统
- **飞机经过水门时，玻璃上出现雨滴效果**
- 道路网络路径规划（读取 apt.dat）

## 安装

将 `WaterSalute` 文件夹复制到 `X-Plane 12/Resources/plugins/`

## 使用

1. 飞机在地面低速滑行
2. 菜单：**Plugins → Water Salute → Start Water Salute**
3. 点击 **Stop Water Salute** 结束仪式

## 资源文件

需要在 `WaterSalute/data/modules/WaterSalute/resources/` 目录下放置以下模型文件：

- `firetruck.obj` - 消防车3D模型
- `waterdrop.obj` - 水滴粒子模型

可以从 WaterSalute C++ 版本的 fountains.zip 中获取这些模型。

## 雨滴效果

当飞机经过水门仪式时，如果飞机接近水柱喷射区域，驾驶舱玻璃上会自动出现雨滴效果：

- **自动检测**：插件检测飞机与水柱粒子的距离
- **渐变效果**：雨滴效果平滑淡入淡出
- **强度控制**：雨滴密度取决于飞机与水柱的接近程度
- **自动恢复**：水门仪式结束后，效果自动消失

### 技术参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 检测半径 | 50 m | 水平方向检测水粒子的范围 |
| 检测高度 | 20 m | 垂直方向检测水粒子的范围 |
| 最大强度 | 80% | 雨滴效果的最大强度 |
| 淡入时间 | 0.5 s | 效果出现的过渡时间 |
| 淡出时间 | 2.0 s | 效果消失的过渡时间 |

## Datarefs

所有 dataref 为 float 数组，索引 0 = 左侧消防车，索引 1 = 右侧消防车。

| Dataref | 单位 | 范围 | 读写 | 说明 |
|---------|------|------|------|------|
| `watersalute/truck/front_steering_angle` | 度 | -45 ~ 45 | R/W | 前轮转向角 |
| `watersalute/truck/rear_steering_angle` | 度 | -45 ~ 45 | R/W | 后轮转向角 |
| `watersalute/truck/wheel_rotation_angle` | 度 | 0 ~ 360 | R | 车轮旋转角度 |
| `watersalute/truck/cannon_pitch` | 度 | 0 ~ 90 | R/W | 水炮俯仰角 |
| `watersalute/truck/cannon_yaw` | 度 | -180 ~ 180 | R/W | 水炮偏航角 |
| `watersalute/truck/speed` | m/s | - | R | 车辆速度 |

## 转向系统

### 阿克曼转向模型（Ackermann Steering）

本插件使用阿克曼转向几何模型计算8x8消防车的转向速率。

#### 核心公式

```
转弯半径 R = wheelbase / (tan(δ_f) + tan(|δ_r|))
转向速率 ω = speed / R = speed × (tan(δ_f) + tan(|δ_r|)) / wheelbase
```

其中：
- `δ_f` - 前轮转向角（度）
- `δ_r` - 后轮转向角（度）
- `wheelbase` - 轴距（6米）
- `speed` - 车辆速度（m/s）

#### 转向参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 最大转向角 | ±45° | 前后轮最大转向角度 |
| 轴距 | 6.0 m | 前后轴之间的距离 |
| 车轮半径 | 0.5 m | 用于计算车轮旋转角度 |
| 后轮转向比 | 0.4 | 后轮角度 = -前轮角度 × 0.4 |

## 车辆物理参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 接近速度 | 15 m/s | 消防车接近飞机的速度 |
| 原地转向速度 | 2 m/s | 用于计算原地转向时的转向速率 |
| 离开速度倍数 | 0.667 | 离开时速度 = 接近速度 × 2/3 |
| 加速度 | 3 m/s² | 消防车加速时的加速度 |
| 减速度 | 4 m/s² | 消防车减速时的减速度 |
| 停止距离 | 200 m | 消防车在飞机前方停止的距离 |
| 额外间距 | 40 m | 消防车间距 = 翼展/2 + 20m |

## 道路网络与路径规划

插件会自动读取 X-Plane 的 apt.dat 文件获取机场地面道路信息，使消防车沿着真实的服务车辆道路行驶。

### 功能特点

- **apt.dat 解析**：读取机场的地面交通网络（1201节点、1202/1206边）
- **自动寻路**：使用 A* 算法在道路网络中规划最短路径
- **平滑转弯**：使用贝塞尔曲线在路口创建平滑的转弯路径
- **速度控制**：转弯时自动减速，直线时加速
- **优雅降级**：如果无法读取道路网络，自动回退到直线接近模式

### 支持的 apt.dat 记录

| 代码 | 类型 | 说明 |
|------|------|------|
| 1201 | 节点 | 道路网络节点，包含经纬度和名称 |
| 1202 | 边 | 滑行道连接，允许消防车通行 |
| 1206 | 服务车辆边 | 专用服务车辆道路，fire_truck 类型优先 |

## 技术实现

本插件使用 SASL3 (Scriptable Avionics Simulation Library) 框架开发，以 Lua 语言编写。

### 文件结构

```
WaterSalute/
├── 64/                     # SASL 二进制文件
├── data/
│   ├── init.lua            # 插件入口
│   ├── modules/
│   │   └── WaterSalute/
│   │       ├── component.lua   # 组件定义
│   │       ├── main.lua        # 主逻辑
│   │       ├── constants.lua   # 常量定义
│   │       ├── utils.lua       # 工具函数
│   │       ├── firetruck.lua   # 消防车模块
│   │       ├── roadnetwork.lua # 道路网络解析
│   │       ├── pathplanning.lua # A*寻路和路径平滑
│   │       ├── raindrop.lua    # 雨滴效果模块
│   │       └── resources/      # 3D模型资源
├── liblinux/               # Linux 库
└── version.txt             # 版本信息
```

## License

GPLv3 详见 LICENSE 文件
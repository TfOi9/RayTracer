# Rust - CUDA 光线追踪器

### 概述
本项目为一个简单的光线追踪器，支持场景构建以及图片渲染。本项目的主体部分使用 Rust 语言实现，内置了球体、平行四边形和三角形等几何体，并实现了哑光、金属、透射、发光和烟雾材质，以及纯色、棋盘、图片、Perlin 噪声等多种纹理。

本项目的主体部分使用 CPU 渲染，并支持多线程渲染，同时使用了 BVH 树优化实体列表求交。此外，本项目基于 CUDA 实现了 GPU 渲染，当前正在开发中，可以做到相对于 CPU 渲染的进一步性能优化。

### 仓库结构
本仓库的 Rust 代码存放在 `src` 文件夹下，CUDA 代码存放在 `cuda` 文件夹下，渲染出的成品图片存放在 `images` 文件夹下。本项目的 Rust 既可以渲染，又可以充当场景构建的前端，而 CUDA 可以作为渲染后端。前、后端基于 IR 做到了解耦。具体地，`src/export_ir.rs` 实现了把场景输出为 IR 文件，而 `cuda/include/parser.cuh` 则可以解析 IR 并转化为 CUDA 端的内部表示。有关 IR 的具体内容，请参考 `docs/cuda_ir.md` 和 `docs/ir_usage.md`。

### 构建方法
本仓库的 Rust 端和 CUDA 端构建分离。Rust 端是跨平台的，要求安装了 `rustup` 和 `cargo`。可以直接在仓库根目录下执行 `cargo build --release`来构建。CUDA 端要求为 Windows 或 WSL 环境，且电脑配备有 NVIDIA 系列显卡并安装有最新驱动。此外，还需要 `gcc` `cmake` 和 `nvcc` 环境。

为了避免显存溢出，当前固定分块渲染，块边长最大为 256 像素。这一修复完全避免了显存溢出到内存上所带来的内存虚拟化错误。

如需使用 CUDA 渲染，首先需要场景 IR 文件（`.ir`，可通过 Rust 端构建获得）和相机配置文件（`.cfg`）。你可以运行 `gpu_render.exe` 可执行文件并使用命令行参数传入 IR 文件路径、输出路径和相机配置文件来渲染。

举例而言，加入你的可执行文件在 `cuda/build/` 路径下，你可以在项目根目录下执行：
```
powershell
> .\cuda\build\gpu_render.exe
  .\images\gpu\scenario_1\scenario_1.ir
  .\images\gpu\scenario_1\scenario_1.ppm
  .\images\gpu\scenario_1\camera_scenario_1.cfg
```
来渲染预设好的场景 1 。

### 渲染性能
以下给出一个参考基线：
渲染场景 1 （`bouncing_spheres`，参数为：宽度 1000px，比例 16:9，每像素取样数 500，最大反射深度 50），CPU 渲染约需 30s （包含场景构建），GPU 渲染约需 12s （包含 IR 解析）。

上述测试的硬件环境为 Intel Core i9（24 核），NVIDIA GeForce RTX 5060。

### 参考文献
[_Ray Tracing in One Weekend_](https://raytracing.github.io/books/RayTracingInOneWeekend.html)

[_Ray Tracing: The Next Week_](https://raytracing.github.io/books/RayTracingTheNextWeek.html)

本仓库作者：2025 级 ACM 班 赵睿城

感谢 @cicada3301digger 为本项目提供的命令行渲染入口，以及他为本项目的测试做出的贡献。

文档更新时间：2026 / 3 / 29
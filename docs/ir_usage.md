## IR 生成与解析使用说明

本文档说明如何在当前项目中导出 IR 文件，以及如何用 Rust 侧解析器做结构校验。

### 1. 通过命令行导出 IR

在项目根目录执行：

```bash
# 导出全部场景（1..9）到 ir/scenario_*.ir
cargo run --bin raytracer -- --export-ir all

# 导出单个场景（示例：场景 9）
cargo run --bin raytracer -- --export-ir 9
```

说明：
- 输出目录固定为 `ir/`。
- 单场景导出文件名为 `ir/scenario_<id>.ir`。
- 支持的场景编号为 `1..9`。

### 2. 在 Rust 代码中导出 IR

场景级导出接口位于 `export_scenarios` 模块：

```rust
use raytracer::export_scenarios::{export_scene_ir, export_all_scene_ir};

// 导出单个场景
export_scene_ir(9, "ir/scenario_9.ir")?;

// 导出全部场景，返回生成的路径列表
let paths = export_all_scene_ir("ir")?;
println!("generated: {} files", paths.len());
```

若你已经持有一个场景根节点（实现 `Hittable`），可使用 `export_ir` 模块的底层接口：

```rust
use raytracer::export_ir::{export_to_ir_string, export_to_ir_file};

let text = export_to_ir_string(&world_root)?;
export_to_ir_file(&world_root, "ir/custom_scene.ir")?;
```

### 3. 解析 IR（结构校验）

`parse_ir_text` 会按段读取并返回每个 section 的计数，用于快速校验 IR 文件结构是否完整：

```rust
use raytracer::export_ir::parse_ir_text;

let text = std::fs::read_to_string("ir/scenario_9.ir")?;
let parsed = parse_ir_text(&text)?;

println!(
    "texture={} material={} hittable={} bvh={} resource={}",
    parsed.texture_count,
    parsed.material_count,
    parsed.hittable_count,
    parsed.bvh_count,
    parsed.resource_count,
);
```

说明：
- 当前解析器是“结构级解析”：校验 section 顺序、`SIZE` 与行数是否匹配，并返回计数。
- 它不做完整语义反序列化（例如不还原为具体几何体/材质对象）。

### 4. 与 CUDA 解析链路联调

可直接运行测试验证“导出 -> 解析”链路：

```bash
cargo test -q --test ir_pipeline_test
```

该测试会：
- 导出场景 IR。
- 调用 `parse_ir_text` 做结构校验。
- 在本机存在 `nvcc` 时，编译并运行 CUDA parser smoke 程序。

### 5. IR 格式细节

字段级定义（TEXTURE/MATERIAL/HITTABLE/BVH/RESOURCE）请参考：

- `docs/cuda_ir.md`

补充说明：
- 当前 RESOURCE 段对图片资源采用“内嵌像素”格式（不再仅保存路径）。
- 导出包含 ImageTexture 的场景时，`.ir` 文件会显著增大，这是预期行为。

### 6. CUDA 端直接渲染（gpu_render）

在 `cuda/` 目录构建并运行：

```bash
cd cuda
cmake -S . -B build
cmake --build build -j

# 用 IR + 相机配置渲染到指定输出路径
./build/gpu_render ../ir/scenario_1.ir /tmp/scenario_1_gpu.ppm ./config/camera_scenario_1.cfg
```

相机配置文件采用 `key=value` 文本格式（示例见 `cuda/config/camera_scenario_1.cfg`）：

```text
aspect_ratio=1.7777778
image_width=400
samples_per_pixel=50
max_depth=20
vfov=20.0
lookfrom=13.0 2.0 3.0
lookat=0.0 0.0 0.0
vup=0.0 1.0 0.0
defocus_angle=0.6
focus_dist=10.0
background=0.70 0.80 1.00
```

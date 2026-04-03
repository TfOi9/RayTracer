#include "../include/parser.cuh"

#include <iostream>
#include <string>
#include <vector>

static bool validate_ir_indices(const ParsedIR& ir, std::string& err) {
    const int tex_count = static_cast<int>(ir.textures.size());
    const int mat_count = static_cast<int>(ir.materials.size());
    const int hit_count = static_cast<int>(ir.hittables.size());
    const int bvh_count = static_cast<int>(ir.bvh.size());

    if (tex_count <= 0 || mat_count <= 0 || hit_count <= 0 || bvh_count <= 0) {
        err = "critical sections must be non-empty";
        return false;
    }

    for (int i = 0; i < mat_count; ++i) {
        if (ir.materials[i].textureId < 0 || ir.materials[i].textureId >= tex_count) {
            err = "material textureId out of range at row " + std::to_string(i);
            return false;
        }
    }

    int leaf_count = 0;
    std::vector<int> parent_count(static_cast<size_t>(bvh_count), 0);
    for (int i = 0; i < hit_count; ++i) {
        if (ir.hittables[i].type < 1 || ir.hittables[i].type > 4) {
            err = "hittable type out of range at row " + std::to_string(i);
            return false;
        }
        if (ir.hittables[i].textureId < 0 || ir.hittables[i].textureId >= tex_count) {
            err = "hittable textureId out of range at row " + std::to_string(i);
            return false;
        }
        if (ir.hittables[i].materialId < 0 || ir.hittables[i].materialId >= mat_count) {
            err = "hittable materialId out of range at row " + std::to_string(i);
            return false;
        }
    }

    for (int i = 0; i < bvh_count; ++i) {
        const ParsedBvhRow& row = ir.bvh[i];
        if (row.hittableIndex >= 0) {
            ++leaf_count;
            if (row.hittableIndex >= hit_count || row.left != -1 || row.right != -1) {
                err = "invalid BVH leaf row " + std::to_string(i);
                return false;
            }
            continue;
        }

        if (row.left < 0 || row.left >= bvh_count || row.right < 0 || row.right >= bvh_count || row.left == row.right) {
            err = "invalid BVH internal row " + std::to_string(i);
            return false;
        }
        ++parent_count[static_cast<size_t>(row.left)];
        ++parent_count[static_cast<size_t>(row.right)];
    }

    if (leaf_count != hit_count) {
        err = "BVH leaf count does not match hittable count";
        return false;
    }

    if (parent_count[0] != 0) {
        err = "BVH root node must be row 0";
        return false;
    }

    for (int i = 1; i < bvh_count; ++i) {
        if (parent_count[static_cast<size_t>(i)] != 1) {
            err = "BVH node has invalid parent count at row " + std::to_string(i);
            return false;
        }
    }

    return true;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "usage: cuda_parser_smoke <ir_path>" << std::endl;
        return 2;
    }

    ParsedIR ir;
    std::string err;
    if (!parse_ir_file(argv[1], ir, &err)) {
        std::cerr << "parse_ir_file failed: " << err << std::endl;
        return 1;
    }

    if (ir.hittables.empty() || ir.bvh.empty() || ir.materials.empty()) {
        std::cerr << "parsed IR has empty critical sections" << std::endl;
        return 1;
    }

    std::string validation_err;
    if (!validate_ir_indices(ir, validation_err)) {
        std::cerr << "IR validation failed: " << validation_err << std::endl;
        return 1;
    }

    std::cout << "textures=" << ir.textures.size()
              << " materials=" << ir.materials.size()
              << " hittables=" << ir.hittables.size()
              << " bvh=" << ir.bvh.size()
              << " resources=" << ir.resources.size()
              << std::endl;

    return 0;
}

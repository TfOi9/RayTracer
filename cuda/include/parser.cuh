#ifndef CUDA_PARSER_CUH
#define CUDA_PARSER_CUH

#include "aabb.cuh"

#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

struct ParsedTextureRow {
    int type;
    Vec3 c1;
    Vec3 c2;
    Vec3 c3;
    int resourceId;
};

struct ParsedMaterialRow {
    int type;
    int textureId;
    Vec3 color;
    float p1;
    float p2;
};

struct ParsedHittableRow {
    int type;
    Vec3 p;
    Vec3 u;
    Vec3 v;
    Vec3 moving;
    Vec3 aux1;
    Vec3 aux2;
    float radius;
    int textureId;
    int materialId;
};

struct ParsedBvhRow {
    int left;
    int right;
    AABB bbox;
    int hittableIndex;
};

struct ParsedResourceRow {
    int type;
    int width;
    int height;
    std::vector<Vec3> pixels;
};

struct ParsedIR {
    std::vector<ParsedTextureRow> textures;
    std::vector<ParsedMaterialRow> materials;
    std::vector<ParsedHittableRow> hittables;
    std::vector<ParsedBvhRow> bvh;
    std::vector<ParsedResourceRow> resources;
};

inline std::string trim_copy(const std::string& in) {
    size_t begin = 0;
    while (begin < in.size() && std::isspace(static_cast<unsigned char>(in[begin]))) {
        ++begin;
    }
    size_t end = in.size();
    while (end > begin && std::isspace(static_cast<unsigned char>(in[end - 1]))) {
        --end;
    }
    return in.substr(begin, end - begin);
}

inline bool read_non_empty_line(std::ifstream& file, std::string& line) {
    while (std::getline(file, line)) {
        line = trim_copy(line);
        if (!line.empty()) {
            return true;
        }
    }
    return false;
}

inline bool parse_size_line(const std::string& line, int& out_size) {
    const size_t eq = line.find('=');
    if (eq == std::string::npos) {
        return false;
    }
    std::string rhs = trim_copy(line.substr(eq + 1));
    std::istringstream iss(rhs);
    iss >> out_size;
    return !iss.fail();
}

inline bool expect_section(std::ifstream& file, const std::string& section_name, int& size_out, std::string* err) {
    std::string line;
    if (!read_non_empty_line(file, line)) {
        if (err) {
            *err = "Unexpected EOF while reading section " + section_name;
        }
        return false;
    }
    if (line != section_name) {
        if (err) {
            *err = "Expected section " + section_name + ", got " + line;
        }
        return false;
    }

    if (!read_non_empty_line(file, line)) {
        if (err) {
            *err = "Missing SIZE line for section " + section_name;
        }
        return false;
    }

    if (!parse_size_line(line, size_out) || size_out < 0) {
        if (err) {
            *err = "Invalid SIZE line for section " + section_name + ": " + line;
        }
        return false;
    }

    return true;
}

inline bool parse_ir_file(const std::string& path, ParsedIR& out, std::string* err = nullptr) {
    std::ifstream file(path);
    if (!file.is_open()) {
        if (err) {
            *err = "Failed to open IR file: " + path;
        }
        return false;
    }

    int count = 0;
    std::string line;

    if (!expect_section(file, "TEXTURE", count, err)) {
        return false;
    }
    out.textures.clear();
    out.textures.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        if (!read_non_empty_line(file, line)) {
            if (err) {
                *err = "Unexpected EOF in TEXTURE section";
            }
            return false;
        }
        std::istringstream iss(line);
        ParsedTextureRow row{};
        if (!(iss >> row.type >> row.c1.x >> row.c1.y >> row.c1.z >> row.c2.x >> row.c2.y >> row.c2.z >> row.c3.x >> row.c3.y >> row.c3.z >> row.resourceId)) {
            if (err) {
                *err = "Invalid TEXTURE row: " + line;
            }
            return false;
        }
        out.textures.push_back(row);
    }

    if (!expect_section(file, "MATERIAL", count, err)) {
        return false;
    }
    out.materials.clear();
    out.materials.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        if (!read_non_empty_line(file, line)) {
            if (err) {
                *err = "Unexpected EOF in MATERIAL section";
            }
            return false;
        }
        std::istringstream iss(line);
        ParsedMaterialRow row{};
        if (!(iss >> row.type >> row.textureId >> row.color.x >> row.color.y >> row.color.z >> row.p1 >> row.p2)) {
            if (err) {
                *err = "Invalid MATERIAL row: " + line;
            }
            return false;
        }
        out.materials.push_back(row);
    }

    if (!expect_section(file, "HITTABLE", count, err)) {
        return false;
    }
    out.hittables.clear();
    out.hittables.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        if (!read_non_empty_line(file, line)) {
            if (err) {
                *err = "Unexpected EOF in HITTABLE section";
            }
            return false;
        }
        std::istringstream iss(line);
        ParsedHittableRow row{};
        if (!(iss >> row.type >> row.p.x >> row.p.y >> row.p.z >> row.u.x >> row.u.y >> row.u.z >> row.v.x >> row.v.y >> row.v.z >> row.moving.x >> row.moving.y >> row.moving.z >> row.aux1.x >> row.aux1.y >> row.aux1.z >> row.aux2.x >> row.aux2.y >> row.aux2.z >> row.radius >> row.textureId >> row.materialId)) {
            if (err) {
                *err = "Invalid HITTABLE row: " + line;
            }
            return false;
        }
        out.hittables.push_back(row);
    }

    if (!expect_section(file, "BVH", count, err)) {
        return false;
    }
    out.bvh.clear();
    out.bvh.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        if (!read_non_empty_line(file, line)) {
            if (err) {
                *err = "Unexpected EOF in BVH section";
            }
            return false;
        }
        std::istringstream iss(line);
        ParsedBvhRow row{};
        float xmin = 0.0f;
        float xmax = 0.0f;
        float ymin = 0.0f;
        float ymax = 0.0f;
        float zmin = 0.0f;
        float zmax = 0.0f;
        if (!(iss >> row.left >> row.right >> xmin >> xmax >> ymin >> ymax >> zmin >> zmax >> row.hittableIndex)) {
            if (err) {
                *err = "Invalid BVH row: " + line;
            }
            return false;
        }
        row.bbox = AABB(Interval(xmin, xmax), Interval(ymin, ymax), Interval(zmin, zmax));
        out.bvh.push_back(row);
    }

    if (!expect_section(file, "RESOURCE", count, err)) {
        return false;
    }
    out.resources.clear();
    out.resources.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) {
        if (!read_non_empty_line(file, line)) {
            if (err) {
                *err = "Unexpected EOF in RESOURCE section";
            }
            return false;
        }

        std::istringstream iss(line);
        ParsedResourceRow row{};
        if (!(iss >> row.type)) {
            if (err) {
                *err = "Invalid RESOURCE row: " + line;
            }
            return false;
        }

        if (row.type == 1) {
            if (!(iss >> row.width >> row.height) || row.width < 0 || row.height < 0) {
                if (err) {
                    *err = "Invalid RESOURCE image header row: " + line;
                }
                return false;
            }

            const size_t pixel_count = static_cast<size_t>(row.width) * static_cast<size_t>(row.height);
            row.pixels.clear();
            row.pixels.reserve(pixel_count);

            for (size_t p = 0; p < pixel_count; ++p) {
                if (!read_non_empty_line(file, line)) {
                    if (err) {
                        *err = "Unexpected EOF in RESOURCE image payload";
                    }
                    return false;
                }
                std::istringstream pss(line);
                Vec3 px{};
                if (!(pss >> px.x >> px.y >> px.z)) {
                    if (err) {
                        *err = "Invalid RESOURCE image pixel row: " + line;
                    }
                    return false;
                }
                row.pixels.push_back(px);
            }
        } else {
            if (err) {
                *err = "Unsupported RESOURCE type: " + std::to_string(row.type);
            }
            return false;
        }

        out.resources.push_back(row);
    }

    return true;
}

#endif // CUDA_PARSER_CUH

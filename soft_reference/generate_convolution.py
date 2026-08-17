import numpy as np

np.random.seed(42)

# ==============================================================================
# 1. LARGE 3D TILED GEMM (M=1024, K=32, N=32)
# ==============================================================================
GEMM_M, GEMM_K, GEMM_N = 1024, 32, 32
raw_gemm_A = np.random.randint(1, 6, size=(GEMM_M, GEMM_K), dtype=np.int32)
raw_gemm_B = np.random.randint(1, 6, size=(GEMM_K, GEMM_N), dtype=np.int32)
golden_gemm_C = np.matmul(raw_gemm_A, raw_gemm_B)

# ==============================================================================
# 2. YOLO 1x1 CONVOLUTION (32x32 Image = 1024 Pixels, Cin=16, Cout=16)
# ==============================================================================
H_1x1, W_1x1, CIN_1x1, COUT_1x1 = 32, 32, 16, 16
raw_conv1_in = np.random.randint(1, 5, size=(H_1x1, W_1x1, CIN_1x1), dtype=np.int32)
raw_conv1_w  = np.random.randint(1, 5, size=(CIN_1x1, COUT_1x1), dtype=np.int32)

# 1x1 Conv with NumPy GEMM
golden_conv1 = np.matmul(raw_conv1_in.reshape(-1, CIN_1x1), raw_conv1_w).reshape(H_1x1, W_1x1, COUT_1x1)

# ==============================================================================
# 3. YOLO 3x3 CONVOLUTION WITH SAME PADDING (32x32 Feature Map, Cin=16, Cout=16)
# ==============================================================================
H_3x3, W_3x3, CIN_3x3, COUT_3x3 = 32, 32, 16, 16
raw_image_3x3   = np.random.randint(1, 4, size=(H_3x3, W_3x3, CIN_3x3), dtype=np.int32)
raw_weights_3x3 = np.random.randint(1, 4, size=(3, 3, CIN_3x3, COUT_3x3), dtype=np.int32)

# Apply SAME Zero-Padding (1 pixel border around 32x32 -> 34x34)
padded_image = np.pad(raw_image_3x3, ((1, 1), (1, 1), (0, 0)), mode='constant', constant_values=0)

# Golden Convolution
golden_conv3 = np.zeros((H_3x3, W_3x3, COUT_3x3), dtype=np.int32)
for y in range(H_3x3):
    for x in range(W_3x3):
        for co in range(COUT_3x3):
            acc = 0
            for ky in range(3):
                for kx in range(3):
                    for ci in range(CIN_3x3):
                        acc += padded_image[y + ky, x + kx, ci] * raw_weights_3x3[ky, kx, ci, co]
            golden_conv3[y, x, co] = acc

# ==============================================================================
# EXPORT FLAT MEMORY FILES
# ==============================================================================
def export_flat(filename, array, hex_digits):
    flat_data = array.flatten()
    with open(filename, "w") as f:
        for val in flat_data:
            f.write(f"{int(val):0{hex_digits}X}\n")
    print(f"Exported {filename:<22} | Elements: {len(flat_data):>7}")

export_flat("yolo_gemm_A.mem",     raw_gemm_A,     hex_digits=2)
export_flat("yolo_gemm_B.mem",     raw_gemm_B,     hex_digits=2)
export_flat("golden_gemm.mem",     golden_gemm_C,  hex_digits=8)

export_flat("yolo_conv1_in.mem",   raw_conv1_in,   hex_digits=2)
export_flat("yolo_conv1_w.mem",    raw_conv1_w,    hex_digits=2)
export_flat("golden_conv1.mem",    golden_conv1,   hex_digits=8)

export_flat("yolo_image_3x3.mem",  raw_image_3x3,   hex_digits=2)
export_flat("yolo_weights_3x3.mem",raw_weights_3x3, hex_digits=2)
export_flat("golden_conv3.mem",    golden_conv3,    hex_digits=8)

print("\n>>> All YOLO workloads generated successfully! <<<")
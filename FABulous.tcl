# all Directory with in the script will be relative to the project folder
load_fabric
run_FABulous_fabric
gen_user_design_wrapper user_design/combined_1x1_3x3_dma/combined_dma_npu_sram_top.sv user_design/top_wrapper.v
compile_design ./user_design/combined_1x1_3x3_dma/combined_dma_npu_sram_top.sv
run_simulation fst ./user_design/combined_1x1_3x3_dma/combined_1x1_3x3_dma/combined_dma_npu_sram_top.bin
exit
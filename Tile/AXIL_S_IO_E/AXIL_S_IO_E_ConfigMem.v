module AXIL_S_IO_E_ConfigMem
    #(
`ifdef EMULATION
        parameter [639:0] Emulate_Bitstream=640'b0,
`endif
        parameter MaxFramesPerCol=20,
        parameter FrameBitsPerRow=32,
        parameter NoConfigBits=6
    )
    (
        input  [FrameBitsPerRow - 1:0] FrameData,
        input  [MaxFramesPerCol - 1:0] FrameStrobe,
        output  [NoConfigBits - 1:0] ConfigBits,
        output  [NoConfigBits - 1:0] ConfigBits_N
    );

`ifdef EMULATION
assign ConfigBits[0] = Emulate_Bitstream[231];
assign ConfigBits[1] = Emulate_Bitstream[230];
assign ConfigBits[2] = Emulate_Bitstream[229];
assign ConfigBits[3] = Emulate_Bitstream[228];
assign ConfigBits[4] = Emulate_Bitstream[227];
assign ConfigBits[5] = Emulate_Bitstream[226];
`else

 //instantiate frame latches
config_latch Inst_frame7_bit7 (
    .D(FrameData[7]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[0]),
    .QN(ConfigBits_N[0])
);

config_latch Inst_frame7_bit6 (
    .D(FrameData[6]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[1]),
    .QN(ConfigBits_N[1])
);

config_latch Inst_frame7_bit5 (
    .D(FrameData[5]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[2]),
    .QN(ConfigBits_N[2])
);

config_latch Inst_frame7_bit4 (
    .D(FrameData[4]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[3]),
    .QN(ConfigBits_N[3])
);

config_latch Inst_frame7_bit3 (
    .D(FrameData[3]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[4]),
    .QN(ConfigBits_N[4])
);

config_latch Inst_frame7_bit2 (
    .D(FrameData[2]),
    .E(FrameStrobe[7]),
    .Q(ConfigBits[5]),
    .QN(ConfigBits_N[5])
);

`endif
endmodule
module AXI_M_IO_ConfigMem
    #(
`ifdef EMULATION
        parameter [639:0] Emulate_Bitstream=640'b0,
`endif
        parameter MaxFramesPerCol=20,
        parameter FrameBitsPerRow=32,
        parameter NoConfigBits=8
    )
    (
        input  [FrameBitsPerRow - 1:0] FrameData,
        input  [MaxFramesPerCol - 1:0] FrameStrobe,
        output  [NoConfigBits - 1:0] ConfigBits,
        output  [NoConfigBits - 1:0] ConfigBits_N
    );

`ifdef EMULATION
assign ConfigBits[0] = Emulate_Bitstream[271];
assign ConfigBits[1] = Emulate_Bitstream[270];
assign ConfigBits[2] = Emulate_Bitstream[269];
assign ConfigBits[3] = Emulate_Bitstream[268];
assign ConfigBits[4] = Emulate_Bitstream[267];
assign ConfigBits[5] = Emulate_Bitstream[266];
assign ConfigBits[6] = Emulate_Bitstream[265];
assign ConfigBits[7] = Emulate_Bitstream[264];
`else

 //instantiate frame latches
config_latch Inst_frame8_bit15 (
    .D(FrameData[15]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[0]),
    .QN(ConfigBits_N[0])
);

config_latch Inst_frame8_bit14 (
    .D(FrameData[14]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[1]),
    .QN(ConfigBits_N[1])
);

config_latch Inst_frame8_bit13 (
    .D(FrameData[13]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[2]),
    .QN(ConfigBits_N[2])
);

config_latch Inst_frame8_bit12 (
    .D(FrameData[12]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[3]),
    .QN(ConfigBits_N[3])
);

config_latch Inst_frame8_bit11 (
    .D(FrameData[11]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[4]),
    .QN(ConfigBits_N[4])
);

config_latch Inst_frame8_bit10 (
    .D(FrameData[10]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[5]),
    .QN(ConfigBits_N[5])
);

config_latch Inst_frame8_bit9 (
    .D(FrameData[9]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[6]),
    .QN(ConfigBits_N[6])
);

config_latch Inst_frame8_bit8 (
    .D(FrameData[8]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[7]),
    .QN(ConfigBits_N[7])
);

`endif
endmodule
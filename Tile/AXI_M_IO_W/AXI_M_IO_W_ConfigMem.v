module AXI_M_IO_W_ConfigMem
    #(
`ifdef EMULATION
        parameter [639:0] Emulate_Bitstream=640'b0,
`endif
        parameter MaxFramesPerCol=20,
        parameter FrameBitsPerRow=32,
        parameter NoConfigBits=20
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
assign ConfigBits[8] = Emulate_Bitstream[263];
assign ConfigBits[9] = Emulate_Bitstream[262];
assign ConfigBits[10] = Emulate_Bitstream[261];
assign ConfigBits[11] = Emulate_Bitstream[260];
assign ConfigBits[12] = Emulate_Bitstream[259];
assign ConfigBits[13] = Emulate_Bitstream[258];
assign ConfigBits[14] = Emulate_Bitstream[257];
assign ConfigBits[15] = Emulate_Bitstream[256];
assign ConfigBits[16] = Emulate_Bitstream[319];
assign ConfigBits[17] = Emulate_Bitstream[318];
assign ConfigBits[18] = Emulate_Bitstream[317];
assign ConfigBits[19] = Emulate_Bitstream[316];
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

config_latch Inst_frame8_bit7 (
    .D(FrameData[7]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[8]),
    .QN(ConfigBits_N[8])
);

config_latch Inst_frame8_bit6 (
    .D(FrameData[6]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[9]),
    .QN(ConfigBits_N[9])
);

config_latch Inst_frame8_bit5 (
    .D(FrameData[5]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[10]),
    .QN(ConfigBits_N[10])
);

config_latch Inst_frame8_bit4 (
    .D(FrameData[4]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[11]),
    .QN(ConfigBits_N[11])
);

config_latch Inst_frame8_bit3 (
    .D(FrameData[3]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[12]),
    .QN(ConfigBits_N[12])
);

config_latch Inst_frame8_bit2 (
    .D(FrameData[2]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[13]),
    .QN(ConfigBits_N[13])
);

config_latch Inst_frame8_bit1 (
    .D(FrameData[1]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[14]),
    .QN(ConfigBits_N[14])
);

config_latch Inst_frame8_bit0 (
    .D(FrameData[0]),
    .E(FrameStrobe[8]),
    .Q(ConfigBits[15]),
    .QN(ConfigBits_N[15])
);

config_latch Inst_frame9_bit31 (
    .D(FrameData[31]),
    .E(FrameStrobe[9]),
    .Q(ConfigBits[16]),
    .QN(ConfigBits_N[16])
);

config_latch Inst_frame9_bit30 (
    .D(FrameData[30]),
    .E(FrameStrobe[9]),
    .Q(ConfigBits[17]),
    .QN(ConfigBits_N[17])
);

config_latch Inst_frame9_bit29 (
    .D(FrameData[29]),
    .E(FrameStrobe[9]),
    .Q(ConfigBits[18]),
    .QN(ConfigBits_N[18])
);

config_latch Inst_frame9_bit28 (
    .D(FrameData[28]),
    .E(FrameStrobe[9]),
    .Q(ConfigBits[19]),
    .QN(ConfigBits_N[19])
);

`endif
endmodule
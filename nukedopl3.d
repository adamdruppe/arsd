// Copyright (C) 2013-2016 Alexey Khokholov (Nuke.YKT)
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
//
//  Nuked OPL3 emulator.
//  Thanks:
//      MAME Development Team(Jarek Burczynski, Tatsuyuki Satoh):
//          Feedback and Rhythm part calculation information.
//      forums.submarine.org.uk(carbon14, opl3):
//          Tremolo and phase generator calculation information.
//      OPLx decapsulated(Matthew Gambrell, Olli Niemitalo):
//          OPL2 ROMs.
//
// version: 1.7.4
/++
	OPL3 (1990's midi chip) emulator.

	License:
		GPL2
	Authors:
		Originally written in C by Alexey Khokholov, ported to D by ketmar, very slightly modified by me.
+/
module arsd.nukedopl3;
nothrow @trusted @nogc:

public:
enum OPL_WRITEBUF_SIZE = 1024;
enum OPL_WRITEBUF_DELAY = 2;


// ////////////////////////////////////////////////////////////////////////// //

// ////////////////////////////////////////////////////////////////////////// //
private:
enum OPL_RATE = 49716;

struct OPL3Slot {
  OPL3Channel* channel;
  OPL3Chip* chip;
  short out_;
  short fbmod;
  short* mod;
  short prout;
  short eg_rout;
  short eg_out;
  ubyte eg_inc;
  ubyte eg_gen;
  ubyte eg_rate;
  ubyte eg_ksl;
  ubyte *trem;
  ubyte reg_vib;
  ubyte reg_type;
  ubyte reg_ksr;
  ubyte reg_mult;
  ubyte reg_ksl;
  ubyte reg_tl;
  ubyte reg_ar;
  ubyte reg_dr;
  ubyte reg_sl;
  ubyte reg_rr;
  ubyte reg_wf;
  ubyte key;
  uint pg_phase;
  uint timer;
}

struct OPL3Channel {
  OPL3Slot*[2] slots;
  OPL3Channel* pair;
  OPL3Chip* chip;
  short*[4] out_;
  ubyte chtype;
  ushort f_num;
  ubyte block;
  ubyte fb;
  ubyte con;
  ubyte alg;
  ubyte ksv;
  ushort cha, chb;
}

struct OPL3WriteBuf {
  ulong time;
  ushort reg;
  ubyte data;
}

///
public struct OPL3Chip {
private:
  OPL3Channel[18] channel;
  OPL3Slot[36] slot;
  ushort timer;
  ubyte newm;
  ubyte nts;
  ubyte rhy;
  ubyte vibpos;
  ubyte vibshift;
  ubyte tremolo;
  ubyte tremolopos;
  ubyte tremoloshift;
  uint noise;
  short zeromod;
  int[2] mixbuff;
  //OPL3L
  int rateratio;
  int samplecnt;
  short[2] oldsamples;
  short[2] samples;

  ulong writebuf_samplecnt;
  uint writebuf_cur;
  uint writebuf_last;
  ulong writebuf_lasttime;
  OPL3WriteBuf[OPL_WRITEBUF_SIZE] writebuf;
}


private:
enum RSM_FRAC = 10;

// Channel types

enum {
  ch_2op = 0,
  ch_4op = 1,
  ch_4op2 = 2,
  ch_drum = 3
}

// Envelope key types

enum {
  egk_norm = 0x01,
  egk_drum = 0x02
}


//
// logsin table
//

static immutable ushort[256] logsinrom = [
  0x859, 0x6c3, 0x607, 0x58b, 0x52e, 0x4e4, 0x4a6, 0x471,
  0x443, 0x41a, 0x3f5, 0x3d3, 0x3b5, 0x398, 0x37e, 0x365,
  0x34e, 0x339, 0x324, 0x311, 0x2ff, 0x2ed, 0x2dc, 0x2cd,
  0x2bd, 0x2af, 0x2a0, 0x293, 0x286, 0x279, 0x26d, 0x261,
  0x256, 0x24b, 0x240, 0x236, 0x22c, 0x222, 0x218, 0x20f,
  0x206, 0x1fd, 0x1f5, 0x1ec, 0x1e4, 0x1dc, 0x1d4, 0x1cd,
  0x1c5, 0x1be, 0x1b7, 0x1b0, 0x1a9, 0x1a2, 0x19b, 0x195,
  0x18f, 0x188, 0x182, 0x17c, 0x177, 0x171, 0x16b, 0x166,
  0x160, 0x15b, 0x155, 0x150, 0x14b, 0x146, 0x141, 0x13c,
  0x137, 0x133, 0x12e, 0x129, 0x125, 0x121, 0x11c, 0x118,
  0x114, 0x10f, 0x10b, 0x107, 0x103, 0x0ff, 0x0fb, 0x0f8,
  0x0f4, 0x0f0, 0x0ec, 0x0e9, 0x0e5, 0x0e2, 0x0de, 0x0db,
  0x0d7, 0x0d4, 0x0d1, 0x0cd, 0x0ca, 0x0c7, 0x0c4, 0x0c1,
  0x0be, 0x0bb, 0x0b8, 0x0b5, 0x0b2, 0x0af, 0x0ac, 0x0a9,
  0x0a7, 0x0a4, 0x0a1, 0x09f, 0x09c, 0x099, 0x097, 0x094,
  0x092, 0x08f, 0x08d, 0x08a, 0x088, 0x086, 0x083, 0x081,
  0x07f, 0x07d, 0x07a, 0x078, 0x076, 0x074, 0x072, 0x070,
  0x06e, 0x06c, 0x06a, 0x068, 0x066, 0x064, 0x062, 0x060,
  0x05e, 0x05c, 0x05b, 0x059, 0x057, 0x055, 0x053, 0x052,
  0x050, 0x04e, 0x04d, 0x04b, 0x04a, 0x048, 0x046, 0x045,
  0x043, 0x042, 0x040, 0x03f, 0x03e, 0x03c, 0x03b, 0x039,
  0x038, 0x037, 0x035, 0x034, 0x033, 0x031, 0x030, 0x02f,
  0x02e, 0x02d, 0x02b, 0x02a, 0x029, 0x028, 0x027, 0x026,
  0x025, 0x024, 0x023, 0x022, 0x021, 0x020, 0x01f, 0x01e,
  0x01d, 0x01c, 0x01b, 0x01a, 0x019, 0x018, 0x017, 0x017,
  0x016, 0x015, 0x014, 0x014, 0x013, 0x012, 0x011, 0x011,
  0x010, 0x00f, 0x00f, 0x00e, 0x00d, 0x00d, 0x00c, 0x00c,
  0x00b, 0x00a, 0x00a, 0x009, 0x009, 0x008, 0x008, 0x007,
  0x007, 0x007, 0x006, 0x006, 0x005, 0x005, 0x005, 0x004,
  0x004, 0x004, 0x003, 0x003, 0x003, 0x002, 0x002, 0x002,
  0x002, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001,
  0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000
];

//
// exp table
//

static immutable ushort[256] exprom = [
  0x000, 0x003, 0x006, 0x008, 0x00b, 0x00e, 0x011, 0x014,
  0x016, 0x019, 0x01c, 0x01f, 0x022, 0x025, 0x028, 0x02a,
  0x02d, 0x030, 0x033, 0x036, 0x039, 0x03c, 0x03f, 0x042,
  0x045, 0x048, 0x04b, 0x04e, 0x051, 0x054, 0x057, 0x05a,
  0x05d, 0x060, 0x063, 0x066, 0x069, 0x06c, 0x06f, 0x072,
  0x075, 0x078, 0x07b, 0x07e, 0x082, 0x085, 0x088, 0x08b,
  0x08e, 0x091, 0x094, 0x098, 0x09b, 0x09e, 0x0a1, 0x0a4,
  0x0a8, 0x0ab, 0x0ae, 0x0b1, 0x0b5, 0x0b8, 0x0bb, 0x0be,
  0x0c2, 0x0c5, 0x0c8, 0x0cc, 0x0cf, 0x0d2, 0x0d6, 0x0d9,
  0x0dc, 0x0e0, 0x0e3, 0x0e7, 0x0ea, 0x0ed, 0x0f1, 0x0f4,
  0x0f8, 0x0fb, 0x0ff, 0x102, 0x106, 0x109, 0x10c, 0x110,
  0x114, 0x117, 0x11b, 0x11e, 0x122, 0x125, 0x129, 0x12c,
  0x130, 0x134, 0x137, 0x13b, 0x13e, 0x142, 0x146, 0x149,
  0x14d, 0x151, 0x154, 0x158, 0x15c, 0x160, 0x163, 0x167,
  0x16b, 0x16f, 0x172, 0x176, 0x17a, 0x17e, 0x181, 0x185,
  0x189, 0x18d, 0x191, 0x195, 0x199, 0x19c, 0x1a0, 0x1a4,
  0x1a8, 0x1ac, 0x1b0, 0x1b4, 0x1b8, 0x1bc, 0x1c0, 0x1c4,
  0x1c8, 0x1cc, 0x1d0, 0x1d4, 0x1d8, 0x1dc, 0x1e0, 0x1e4,
  0x1e8, 0x1ec, 0x1f0, 0x1f5, 0x1f9, 0x1fd, 0x201, 0x205,
  0x209, 0x20e, 0x212, 0x216, 0x21a, 0x21e, 0x223, 0x227,
  0x22b, 0x230, 0x234, 0x238, 0x23c, 0x241, 0x245, 0x249,
  0x24e, 0x252, 0x257, 0x25b, 0x25f, 0x264, 0x268, 0x26d,
  0x271, 0x276, 0x27a, 0x27f, 0x283, 0x288, 0x28c, 0x291,
  0x295, 0x29a, 0x29e, 0x2a3, 0x2a8, 0x2ac, 0x2b1, 0x2b5,
  0x2ba, 0x2bf, 0x2c4, 0x2c8, 0x2cd, 0x2d2, 0x2d6, 0x2db,
  0x2e0, 0x2e5, 0x2e9, 0x2ee, 0x2f3, 0x2f8, 0x2fd, 0x302,
  0x306, 0x30b, 0x310, 0x315, 0x31a, 0x31f, 0x324, 0x329,
  0x32e, 0x333, 0x338, 0x33d, 0x342, 0x347, 0x34c, 0x351,
  0x356, 0x35b, 0x360, 0x365, 0x36a, 0x370, 0x375, 0x37a,
  0x37f, 0x384, 0x38a, 0x38f, 0x394, 0x399, 0x39f, 0x3a4,
  0x3a9, 0x3ae, 0x3b4, 0x3b9, 0x3bf, 0x3c4, 0x3c9, 0x3cf,
  0x3d4, 0x3da, 0x3df, 0x3e4, 0x3ea, 0x3ef, 0x3f5, 0x3fa
];

//
// freq mult table multiplied by 2
//
// 1/2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15
//

static immutable ubyte[16] mt = [
  1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30
];

//
// ksl table
//

static immutable ubyte[16] kslrom = [
  0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64
];

static immutable ubyte[4] kslshift = [
  8, 1, 2, 0
];

//
// envelope generator constants
//

static immutable ubyte[8][4][3] eg_incstep = [
  [
      [ 0, 0, 0, 0, 0, 0, 0, 0 ],
      [ 0, 0, 0, 0, 0, 0, 0, 0 ],
      [ 0, 0, 0, 0, 0, 0, 0, 0 ],
      [ 0, 0, 0, 0, 0, 0, 0, 0 ]
  ],
  [
      [ 0, 1, 0, 1, 0, 1, 0, 1 ],
      [ 0, 1, 0, 1, 1, 1, 0, 1 ],
      [ 0, 1, 1, 1, 0, 1, 1, 1 ],
      [ 0, 1, 1, 1, 1, 1, 1, 1 ]
  ],
  [
      [ 1, 1, 1, 1, 1, 1, 1, 1 ],
      [ 2, 2, 1, 1, 1, 1, 1, 1 ],
      [ 2, 2, 1, 1, 2, 2, 1, 1 ],
      [ 2, 2, 2, 2, 2, 2, 1, 1 ]
  ]
];

static immutable ubyte[16] eg_incdesc = [
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2
];

static immutable byte[16] eg_incsh = [
  0, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, -1, -2
];

//
// address decoding
//

static immutable byte[0x20] ad_slot = [
  0, 1, 2, 3, 4, 5, -1, -1, 6, 7, 8, 9, 10, 11, -1, -1,
  12, 13, 14, 15, 16, 17, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
];

static immutable ubyte[18] ch_slot = [
  0, 1, 2, 6, 7, 8, 12, 13, 14, 18, 19, 20, 24, 25, 26, 30, 31, 32
];

//
// Envelope generator
//

alias envelope_sinfunc = short function (ushort phase, ushort envelope) nothrow @trusted @nogc;
alias envelope_genfunc = void function (OPL3Slot *slott) nothrow @trusted @nogc;

private short OPL3_EnvelopeCalcExp (uint level) {
  if (level > 0x1fff) level = 0x1fff;
  return cast(short)(((exprom.ptr[(level&0xff)^0xff]|0x400)<<1)>>(level>>8));
}

private short OPL3_EnvelopeCalcSin0 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  ushort neg = 0;
  phase &= 0x3ff;
  if (phase&0x200) neg = ushort.max;
  if (phase&0x100) out_ = logsinrom.ptr[(phase&0xff)^0xff]; else out_ = logsinrom.ptr[phase&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3))^neg;
}

private short OPL3_EnvelopeCalcSin1 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  phase &= 0x3ff;
       if (phase&0x200) out_ = 0x1000;
  else if (phase&0x100) out_ = logsinrom.ptr[(phase&0xff)^0xff];
  else out_ = logsinrom.ptr[phase&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3));
}

private short OPL3_EnvelopeCalcSin2 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  phase &= 0x3ff;
  if (phase&0x100) out_ = logsinrom.ptr[(phase&0xff)^0xff]; else out_ = logsinrom.ptr[phase&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3));
}

private short OPL3_EnvelopeCalcSin3 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  phase &= 0x3ff;
  if (phase&0x100) out_ = 0x1000; else out_ = logsinrom.ptr[phase&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3));
}

private short OPL3_EnvelopeCalcSin4 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  ushort neg = 0;
  phase &= 0x3ff;
  if ((phase&0x300) == 0x100) neg = ushort.max;
       if (phase&0x200) out_ = 0x1000;
  else if (phase&0x80) out_ = logsinrom.ptr[((phase^0xff)<<1)&0xff];
  else out_ = logsinrom.ptr[(phase<<1)&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3))^neg;
}

private short OPL3_EnvelopeCalcSin5 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  phase &= 0x3ff;
       if (phase&0x200) out_ = 0x1000;
  else if (phase&0x80) out_ = logsinrom.ptr[((phase^0xff)<<1)&0xff];
  else out_ = logsinrom.ptr[(phase<<1)&0xff];
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3));
}

private short OPL3_EnvelopeCalcSin6 (ushort phase, ushort envelope) {
  ushort neg = 0;
  phase &= 0x3ff;
  if (phase&0x200) neg = ushort.max;
  return OPL3_EnvelopeCalcExp(envelope<<3)^neg;
}

private short OPL3_EnvelopeCalcSin7 (ushort phase, ushort envelope) {
  ushort out_ = 0;
  ushort neg = 0;
  phase &= 0x3ff;
  if (phase&0x200) {
    neg = ushort.max;
    phase = (phase&0x1ff)^0x1ff;
  }
  out_ = cast(ushort)(phase<<3);
  return OPL3_EnvelopeCalcExp(out_+(envelope<<3))^neg;
}

static immutable envelope_sinfunc[8] envelope_sin = [
  &OPL3_EnvelopeCalcSin0,
  &OPL3_EnvelopeCalcSin1,
  &OPL3_EnvelopeCalcSin2,
  &OPL3_EnvelopeCalcSin3,
  &OPL3_EnvelopeCalcSin4,
  &OPL3_EnvelopeCalcSin5,
  &OPL3_EnvelopeCalcSin6,
  &OPL3_EnvelopeCalcSin7
];

static immutable envelope_genfunc[5] envelope_gen = [
  &OPL3_EnvelopeGenOff,
  &OPL3_EnvelopeGenAttack,
  &OPL3_EnvelopeGenDecay,
  &OPL3_EnvelopeGenSustain,
  &OPL3_EnvelopeGenRelease
];

alias envelope_gen_num = int;
enum /*envelope_gen_num*/:int {
  envelope_gen_num_off = 0,
  envelope_gen_num_attack = 1,
  envelope_gen_num_decay = 2,
  envelope_gen_num_sustain = 3,
  envelope_gen_num_release = 4
}

private ubyte OPL3_EnvelopeCalcRate (OPL3Slot* slot, ubyte reg_rate) {
  if (reg_rate == 0x00) return 0x00;
  ubyte rate = cast(ubyte)((reg_rate<<2)+(slot.reg_ksr ? slot.channel.ksv : (slot.channel.ksv>>2)));
  if (rate > 0x3c) rate = 0x3c;
  return rate;
}

private void OPL3_EnvelopeUpdateKSL (OPL3Slot* slot) {
  short ksl = (kslrom.ptr[slot.channel.f_num>>6]<<2)-((0x08-slot.channel.block)<<5);
  if (ksl < 0) ksl = 0;
  slot.eg_ksl = cast(ubyte)ksl;
}

private void OPL3_EnvelopeUpdateRate (OPL3Slot* slot) {
  switch (slot.eg_gen) {
    case envelope_gen_num_off:
    case envelope_gen_num_attack:
      slot.eg_rate = OPL3_EnvelopeCalcRate(slot, slot.reg_ar);
      break;
    case envelope_gen_num_decay:
      slot.eg_rate = OPL3_EnvelopeCalcRate(slot, slot.reg_dr);
      break;
    case envelope_gen_num_sustain:
    case envelope_gen_num_release:
      slot.eg_rate = OPL3_EnvelopeCalcRate(slot, slot.reg_rr);
      break;
    default: break;
  }
}

private void OPL3_EnvelopeGenOff (OPL3Slot* slot) {
  slot.eg_rout = 0x1ff;
}

private void OPL3_EnvelopeGenAttack (OPL3Slot* slot) {
  if (slot.eg_rout == 0x00) {
    slot.eg_gen = envelope_gen_num_decay;
    OPL3_EnvelopeUpdateRate(slot);
  } else {
    slot.eg_rout += ((~cast(uint)slot.eg_rout)*slot.eg_inc)>>3;
    if (slot.eg_rout < 0x00) slot.eg_rout = 0x00;
  }
}

private void OPL3_EnvelopeGenDecay (OPL3Slot* slot) {
  if (slot.eg_rout >= slot.reg_sl<<4) {
    slot.eg_gen = envelope_gen_num_sustain;
    OPL3_EnvelopeUpdateRate(slot);
  } else {
    slot.eg_rout += slot.eg_inc;
  }
}

private void OPL3_EnvelopeGenSustain (OPL3Slot* slot) {
  if (!slot.reg_type) OPL3_EnvelopeGenRelease(slot);
}

private void OPL3_EnvelopeGenRelease (OPL3Slot* slot) {
  if (slot.eg_rout >= 0x1ff) {
    slot.eg_gen = envelope_gen_num_off;
    slot.eg_rout = 0x1ff;
    OPL3_EnvelopeUpdateRate(slot);
  } else {
    slot.eg_rout += slot.eg_inc;
  }
}

private void OPL3_EnvelopeCalc (OPL3Slot* slot) {
  ubyte rate_h, rate_l;
  ubyte inc = 0;
  rate_h = slot.eg_rate>>2;
  rate_l = slot.eg_rate&3;
  if (eg_incsh.ptr[rate_h] > 0) {
    if ((slot.chip.timer&((1<<eg_incsh.ptr[rate_h])-1)) == 0) {
      inc = eg_incstep.ptr[eg_incdesc.ptr[rate_h]].ptr[rate_l].ptr[((slot.chip.timer)>> eg_incsh.ptr[rate_h])&0x07];
    }
  } else {
    inc = cast(ubyte)(eg_incstep.ptr[eg_incdesc.ptr[rate_h]].ptr[rate_l].ptr[slot.chip.timer&0x07]<<(-cast(int)(eg_incsh.ptr[rate_h])));
  }
  slot.eg_inc = inc;
  slot.eg_out = cast(short)(slot.eg_rout+(slot.reg_tl<<2)+(slot.eg_ksl>>kslshift.ptr[slot.reg_ksl])+*slot.trem);
  envelope_gen[slot.eg_gen](slot);
}

private void OPL3_EnvelopeKeyOn (OPL3Slot* slot, ubyte type) {
  if (!slot.key) {
    slot.eg_gen = envelope_gen_num_attack;
    OPL3_EnvelopeUpdateRate(slot);
    if ((slot.eg_rate>>2) == 0x0f) {
      slot.eg_gen = envelope_gen_num_decay;
      OPL3_EnvelopeUpdateRate(slot);
      slot.eg_rout = 0x00;
    }
    slot.pg_phase = 0x00;
  }
  slot.key |= type;
}

private void OPL3_EnvelopeKeyOff (OPL3Slot* slot, ubyte type) {
  if (slot.key) {
    slot.key &= (~cast(uint)type);
    if (!slot.key) {
      slot.eg_gen = envelope_gen_num_release;
      OPL3_EnvelopeUpdateRate(slot);
    }
  }
}

//
// Phase Generator
//

private void OPL3_PhaseGenerate (OPL3Slot* slot) {
  ushort f_num;
  uint basefreq;

  f_num = slot.channel.f_num;
  if (slot.reg_vib) {
    byte range;
    ubyte vibpos;

    range = (f_num>>7)&7;
    vibpos = slot.chip.vibpos;

         if (!(vibpos&3)) range = 0;
    else if (vibpos&1) range >>= 1;
    range >>= slot.chip.vibshift;

    if (vibpos&4) range = cast(byte) -cast(int)(range);
    f_num += range;
  }
  basefreq = (f_num<<slot.channel.block)>>1;
  slot.pg_phase += (basefreq*mt.ptr[slot.reg_mult])>>1;
}

//
// Noise Generator
//

private void OPL3_NoiseGenerate (OPL3Chip* chip) {
  if (chip.noise&0x01) chip.noise ^= 0x800302;
  chip.noise >>= 1;
}

//
// Slot
//

private void OPL3_SlotWrite20 (OPL3Slot* slot, ubyte data) {
  slot.trem = ((data>>7)&0x01 ? &slot.chip.tremolo : cast(ubyte*)&slot.chip.zeromod);
  slot.reg_vib = (data>>6)&0x01;
  slot.reg_type = (data>>5)&0x01;
  slot.reg_ksr = (data>>4)&0x01;
  slot.reg_mult = data&0x0f;
  OPL3_EnvelopeUpdateRate(slot);
}

private void OPL3_SlotWrite40 (OPL3Slot* slot, ubyte data) {
  slot.reg_ksl = (data>>6)&0x03;
  slot.reg_tl = data&0x3f;
  OPL3_EnvelopeUpdateKSL(slot);
}

private void OPL3_SlotWrite60 (OPL3Slot* slot, ubyte data) {
  slot.reg_ar = (data>>4)&0x0f;
  slot.reg_dr = data&0x0f;
  OPL3_EnvelopeUpdateRate(slot);
}

private void OPL3_SlotWrite80 (OPL3Slot* slot, ubyte data) {
  slot.reg_sl = (data>>4)&0x0f;
  if (slot.reg_sl == 0x0f) slot.reg_sl = 0x1f;
  slot.reg_rr = data&0x0f;
  OPL3_EnvelopeUpdateRate(slot);
}

private void OPL3_SlotWriteE0 (OPL3Slot* slot, ubyte data) {
  slot.reg_wf = data&0x07;
  if (slot.chip.newm == 0x00) slot.reg_wf &= 0x03;
}

private void OPL3_SlotGeneratePhase (OPL3Slot* slot, ushort phase) {
  slot.out_ = envelope_sin[slot.reg_wf](phase, slot.eg_out);
}

private void OPL3_SlotGenerate (OPL3Slot* slot) {
  OPL3_SlotGeneratePhase(slot, cast(ushort)(cast(ushort)(slot.pg_phase>>9)+*slot.mod));
}

private void OPL3_SlotGenerateZM (OPL3Slot* slot) {
  OPL3_SlotGeneratePhase(slot, cast(ushort)(slot.pg_phase>>9));
}

private void OPL3_SlotCalcFB (OPL3Slot* slot) {
  slot.fbmod = (slot.channel.fb != 0x00 ? cast(short)((slot.prout+slot.out_)>>(0x09-slot.channel.fb)) : 0);
  slot.prout = slot.out_;
}

//
// Channel
//

private void OPL3_ChannelUpdateRhythm (OPL3Chip* chip, ubyte data) {
  OPL3Channel* channel6;
  OPL3Channel* channel7;
  OPL3Channel* channel8;
  ubyte chnum;

  chip.rhy = data&0x3f;
  if (chip.rhy&0x20) {
    channel6 = &chip.channel.ptr[6];
    channel7 = &chip.channel.ptr[7];
    channel8 = &chip.channel.ptr[8];
    channel6.out_.ptr[0] = &channel6.slots.ptr[1].out_;
    channel6.out_.ptr[1] = &channel6.slots.ptr[1].out_;
    channel6.out_.ptr[2] = &chip.zeromod;
    channel6.out_.ptr[3] = &chip.zeromod;
    channel7.out_.ptr[0] = &channel7.slots.ptr[0].out_;
    channel7.out_.ptr[1] = &channel7.slots.ptr[0].out_;
    channel7.out_.ptr[2] = &channel7.slots.ptr[1].out_;
    channel7.out_.ptr[3] = &channel7.slots.ptr[1].out_;
    channel8.out_.ptr[0] = &channel8.slots.ptr[0].out_;
    channel8.out_.ptr[1] = &channel8.slots.ptr[0].out_;
    channel8.out_.ptr[2] = &channel8.slots.ptr[1].out_;
    channel8.out_.ptr[3] = &channel8.slots.ptr[1].out_;
    for (chnum = 6; chnum < 9; ++chnum) chip.channel.ptr[chnum].chtype = ch_drum;
    OPL3_ChannelSetupAlg(channel6);
    //hh
    if (chip.rhy&0x01) {
      OPL3_EnvelopeKeyOn(channel7.slots.ptr[0], egk_drum);
    } else {
      OPL3_EnvelopeKeyOff(channel7.slots.ptr[0], egk_drum);
    }
    //tc
    if (chip.rhy&0x02) {
      OPL3_EnvelopeKeyOn(channel8.slots.ptr[1], egk_drum);
    } else {
      OPL3_EnvelopeKeyOff(channel8.slots.ptr[1], egk_drum);
    }
    //tom
    if (chip.rhy&0x04) {
      OPL3_EnvelopeKeyOn(channel8.slots.ptr[0], egk_drum);
    } else {
      OPL3_EnvelopeKeyOff(channel8.slots.ptr[0], egk_drum);
    }
    //sd
    if (chip.rhy&0x08) {
      OPL3_EnvelopeKeyOn(channel7.slots.ptr[1], egk_drum);
    } else {
      OPL3_EnvelopeKeyOff(channel7.slots.ptr[1], egk_drum);
    }
    //bd
    if (chip.rhy&0x10) {
      OPL3_EnvelopeKeyOn(channel6.slots.ptr[0], egk_drum);
      OPL3_EnvelopeKeyOn(channel6.slots.ptr[1], egk_drum);
    } else {
      OPL3_EnvelopeKeyOff(channel6.slots.ptr[0], egk_drum);
      OPL3_EnvelopeKeyOff(channel6.slots.ptr[1], egk_drum);
    }
  } else {
    for (chnum = 6; chnum < 9; ++chnum) {
      chip.channel.ptr[chnum].chtype = ch_2op;
      OPL3_ChannelSetupAlg(&chip.channel.ptr[chnum]);
      OPL3_EnvelopeKeyOff(chip.channel.ptr[chnum].slots.ptr[0], egk_drum);
      OPL3_EnvelopeKeyOff(chip.channel.ptr[chnum].slots.ptr[1], egk_drum);
    }
  }
}

private void OPL3_ChannelWriteA0 (OPL3Channel* channel, ubyte data) {
  if (channel.chip.newm && channel.chtype == ch_4op2) return;
  channel.f_num = (channel.f_num&0x300)|data;
  channel.ksv = cast(ubyte)((channel.block<<1)|((channel.f_num>>(0x09-channel.chip.nts))&0x01));
  OPL3_EnvelopeUpdateKSL(channel.slots.ptr[0]);
  OPL3_EnvelopeUpdateKSL(channel.slots.ptr[1]);
  OPL3_EnvelopeUpdateRate(channel.slots.ptr[0]);
  OPL3_EnvelopeUpdateRate(channel.slots.ptr[1]);
  if (channel.chip.newm && channel.chtype == ch_4op) {
    channel.pair.f_num = channel.f_num;
    channel.pair.ksv = channel.ksv;
    OPL3_EnvelopeUpdateKSL(channel.pair.slots.ptr[0]);
    OPL3_EnvelopeUpdateKSL(channel.pair.slots.ptr[1]);
    OPL3_EnvelopeUpdateRate(channel.pair.slots.ptr[0]);
    OPL3_EnvelopeUpdateRate(channel.pair.slots.ptr[1]);
  }
}

private void OPL3_ChannelWriteB0 (OPL3Channel* channel, ubyte data) {
  if (channel.chip.newm && channel.chtype == ch_4op2) return;
  channel.f_num = (channel.f_num&0xff)|((data&0x03)<<8);
  channel.block = (data>>2)&0x07;
  channel.ksv = cast(ubyte)((channel.block<<1)|((channel.f_num>>(0x09-channel.chip.nts))&0x01));
  OPL3_EnvelopeUpdateKSL(channel.slots.ptr[0]);
  OPL3_EnvelopeUpdateKSL(channel.slots.ptr[1]);
  OPL3_EnvelopeUpdateRate(channel.slots.ptr[0]);
  OPL3_EnvelopeUpdateRate(channel.slots.ptr[1]);
  if (channel.chip.newm && channel.chtype == ch_4op) {
    channel.pair.f_num = channel.f_num;
    channel.pair.block = channel.block;
    channel.pair.ksv = channel.ksv;
    OPL3_EnvelopeUpdateKSL(channel.pair.slots.ptr[0]);
    OPL3_EnvelopeUpdateKSL(channel.pair.slots.ptr[1]);
    OPL3_EnvelopeUpdateRate(channel.pair.slots.ptr[0]);
    OPL3_EnvelopeUpdateRate(channel.pair.slots.ptr[1]);
  }
}

private void OPL3_ChannelSetupAlg (OPL3Channel* channel) {
  if (channel.chtype == ch_drum) {
    final switch (channel.alg&0x01) {
      case 0x00:
        channel.slots.ptr[0].mod = &channel.slots.ptr[0].fbmod;
        channel.slots.ptr[1].mod = &channel.slots.ptr[0].out_;
        break;
      case 0x01:
        channel.slots.ptr[0].mod = &channel.slots.ptr[0].fbmod;
        channel.slots.ptr[1].mod = &channel.chip.zeromod;
        break;
    }
    return;
  }
  if (channel.alg&0x08) return;
  if (channel.alg&0x04) {
    channel.pair.out_.ptr[0] = &channel.chip.zeromod;
    channel.pair.out_.ptr[1] = &channel.chip.zeromod;
    channel.pair.out_.ptr[2] = &channel.chip.zeromod;
    channel.pair.out_.ptr[3] = &channel.chip.zeromod;
    final switch (channel.alg&0x03) {
      case 0x00:
        channel.pair.slots.ptr[0].mod = &channel.pair.slots.ptr[0].fbmod;
        channel.pair.slots.ptr[1].mod = &channel.pair.slots.ptr[0].out_;
        channel.slots.ptr[0].mod = &channel.pair.slots.ptr[1].out_;
        channel.slots.ptr[1].mod = &channel.slots.ptr[0].out_;
        channel.out_.ptr[0] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[1] = &channel.chip.zeromod;
        channel.out_.ptr[2] = &channel.chip.zeromod;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
      case 0x01:
        channel.pair.slots.ptr[0].mod = &channel.pair.slots.ptr[0].fbmod;
        channel.pair.slots.ptr[1].mod = &channel.pair.slots.ptr[0].out_;
        channel.slots.ptr[0].mod = &channel.chip.zeromod;
        channel.slots.ptr[1].mod = &channel.slots.ptr[0].out_;
        channel.out_.ptr[0] = &channel.pair.slots.ptr[1].out_;
        channel.out_.ptr[1] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[2] = &channel.chip.zeromod;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
      case 0x02:
        channel.pair.slots.ptr[0].mod = &channel.pair.slots.ptr[0].fbmod;
        channel.pair.slots.ptr[1].mod = &channel.chip.zeromod;
        channel.slots.ptr[0].mod = &channel.pair.slots.ptr[1].out_;
        channel.slots.ptr[1].mod = &channel.slots.ptr[0].out_;
        channel.out_.ptr[0] = &channel.pair.slots.ptr[0].out_;
        channel.out_.ptr[1] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[2] = &channel.chip.zeromod;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
      case 0x03:
        channel.pair.slots.ptr[0].mod = &channel.pair.slots.ptr[0].fbmod;
        channel.pair.slots.ptr[1].mod = &channel.chip.zeromod;
        channel.slots.ptr[0].mod = &channel.pair.slots.ptr[1].out_;
        channel.slots.ptr[1].mod = &channel.chip.zeromod;
        channel.out_.ptr[0] = &channel.pair.slots.ptr[0].out_;
        channel.out_.ptr[1] = &channel.slots.ptr[0].out_;
        channel.out_.ptr[2] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
    }
  } else {
    final switch (channel.alg&0x01) {
      case 0x00:
        channel.slots.ptr[0].mod = &channel.slots.ptr[0].fbmod;
        channel.slots.ptr[1].mod = &channel.slots.ptr[0].out_;
        channel.out_.ptr[0] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[1] = &channel.chip.zeromod;
        channel.out_.ptr[2] = &channel.chip.zeromod;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
      case 0x01:
        channel.slots.ptr[0].mod = &channel.slots.ptr[0].fbmod;
        channel.slots.ptr[1].mod = &channel.chip.zeromod;
        channel.out_.ptr[0] = &channel.slots.ptr[0].out_;
        channel.out_.ptr[1] = &channel.slots.ptr[1].out_;
        channel.out_.ptr[2] = &channel.chip.zeromod;
        channel.out_.ptr[3] = &channel.chip.zeromod;
        break;
    }
  }
}

private void OPL3_ChannelWriteC0 (OPL3Channel* channel, ubyte data) {
  channel.fb = (data&0x0e)>>1;
  channel.con = data&0x01;
  channel.alg = channel.con;
  if (channel.chip.newm) {
    if (channel.chtype == ch_4op) {
      channel.pair.alg = cast(ubyte)(0x04|(channel.con<<1)|(channel.pair.con));
      channel.alg = 0x08;
      OPL3_ChannelSetupAlg(channel.pair);
    } else if (channel.chtype == ch_4op2) {
      channel.alg = cast(ubyte)(0x04|(channel.pair.con<<1)|(channel.con));
      channel.pair.alg = 0x08;
      OPL3_ChannelSetupAlg(channel);
    } else {
      OPL3_ChannelSetupAlg(channel);
    }
  } else {
    OPL3_ChannelSetupAlg(channel);
  }
  if (channel.chip.newm) {
    channel.cha = ((data>>4)&0x01 ? ushort.max : 0);
    channel.chb = ((data>>5)&0x01 ? ushort.max : 0);
  } else {
    channel.cha = channel.chb = ushort.max;
  }
}

private void OPL3_ChannelKeyOn (OPL3Channel* channel) {
  if (channel.chip.newm) {
    if (channel.chtype == ch_4op) {
      OPL3_EnvelopeKeyOn(channel.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOn(channel.slots.ptr[1], egk_norm);
      OPL3_EnvelopeKeyOn(channel.pair.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOn(channel.pair.slots.ptr[1], egk_norm);
    } else if (channel.chtype == ch_2op || channel.chtype == ch_drum) {
      OPL3_EnvelopeKeyOn(channel.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOn(channel.slots.ptr[1], egk_norm);
    }
  } else {
    OPL3_EnvelopeKeyOn(channel.slots.ptr[0], egk_norm);
    OPL3_EnvelopeKeyOn(channel.slots.ptr[1], egk_norm);
  }
}

private void OPL3_ChannelKeyOff (OPL3Channel* channel) {
  if (channel.chip.newm) {
    if (channel.chtype == ch_4op) {
      OPL3_EnvelopeKeyOff(channel.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOff(channel.slots.ptr[1], egk_norm);
      OPL3_EnvelopeKeyOff(channel.pair.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOff(channel.pair.slots.ptr[1], egk_norm);
    } else if (channel.chtype == ch_2op || channel.chtype == ch_drum) {
      OPL3_EnvelopeKeyOff(channel.slots.ptr[0], egk_norm);
      OPL3_EnvelopeKeyOff(channel.slots.ptr[1], egk_norm);
    }
  } else {
    OPL3_EnvelopeKeyOff(channel.slots.ptr[0], egk_norm);
    OPL3_EnvelopeKeyOff(channel.slots.ptr[1], egk_norm);
  }
}

private void OPL3_ChannelSet4Op (OPL3Chip* chip, ubyte data) {
  ubyte bit;
  ubyte chnum;
  for (bit = 0; bit < 6; ++bit) {
    chnum = bit;
    if (bit >= 3) chnum += 9-3;
    if ((data>>bit)&0x01) {
      chip.channel.ptr[chnum].chtype = ch_4op;
      chip.channel.ptr[chnum+3].chtype = ch_4op2;
    } else {
      chip.channel.ptr[chnum].chtype = ch_2op;
      chip.channel.ptr[chnum+3].chtype = ch_2op;
    }
  }
}

private short OPL3_ClipSample (int sample) pure {
  pragma(inline, true);
       if (sample > 32767) sample = 32767;
  else if (sample < -32768) sample = -32768;
  return cast(short)sample;
}

private void OPL3_GenerateRhythm1 (OPL3Chip* chip) {
  OPL3Channel* channel6;
  OPL3Channel* channel7;
  OPL3Channel* channel8;
  ushort phase14;
  ushort phase17;
  ushort phase;
  ushort phasebit;

  channel6 = &chip.channel.ptr[6];
  channel7 = &chip.channel.ptr[7];
  channel8 = &chip.channel.ptr[8];
  OPL3_SlotGenerate(channel6.slots.ptr[0]);
  phase14 = (channel7.slots.ptr[0].pg_phase>>9)&0x3ff;
  phase17 = (channel8.slots.ptr[1].pg_phase>>9)&0x3ff;
  phase = 0x00;
  //hh tc phase bit
  phasebit = ((phase14&0x08)|(((phase14>>5)^phase14)&0x04)|(((phase17>>2)^phase17)&0x08)) ? 0x01 : 0x00;
  //hh
  phase = cast(ushort)((phasebit<<9)|(0x34<<((phasebit^(chip.noise&0x01))<<1)));
  OPL3_SlotGeneratePhase(channel7.slots.ptr[0], phase);
  //tt
  OPL3_SlotGenerateZM(channel8.slots.ptr[0]);
}

private void OPL3_GenerateRhythm2 (OPL3Chip* chip) {
  OPL3Channel* channel6;
  OPL3Channel* channel7;
  OPL3Channel* channel8;
  ushort phase14;
  ushort phase17;
  ushort phase;
  ushort phasebit;

  channel6 = &chip.channel.ptr[6];
  channel7 = &chip.channel.ptr[7];
  channel8 = &chip.channel.ptr[8];
  OPL3_SlotGenerate(channel6.slots.ptr[1]);
  phase14 = (channel7.slots.ptr[0].pg_phase>>9)&0x3ff;
  phase17 = (channel8.slots.ptr[1].pg_phase>>9)&0x3ff;
  phase = 0x00;
  //hh tc phase bit
  phasebit = ((phase14&0x08)|(((phase14>>5)^phase14)&0x04)|(((phase17>>2)^phase17)&0x08)) ? 0x01 : 0x00;
  //sd
  phase = (0x100<<((phase14>>8)&0x01))^((chip.noise&0x01)<<8);
  OPL3_SlotGeneratePhase(channel7.slots.ptr[1], phase);
  //tc
  phase = cast(ushort)(0x100|(phasebit<<9));
  OPL3_SlotGeneratePhase(channel8.slots.ptr[1], phase);
}


// ////////////////////////////////////////////////////////////////////////// //
/// OPL3_Generate
public void generate (ref OPL3Chip chip, short* buf) {
  ubyte ii;
  ubyte jj;
  short accm;

  buf[1] = OPL3_ClipSample(chip.mixbuff.ptr[1]);

  for (ii = 0; ii < 12; ++ii) {
    OPL3_SlotCalcFB(&chip.slot.ptr[ii]);
    OPL3_PhaseGenerate(&chip.slot.ptr[ii]);
    OPL3_EnvelopeCalc(&chip.slot.ptr[ii]);
    OPL3_SlotGenerate(&chip.slot.ptr[ii]);
  }

  for (ii = 12; ii < 15; ++ii) {
    OPL3_SlotCalcFB(&chip.slot.ptr[ii]);
    OPL3_PhaseGenerate(&chip.slot.ptr[ii]);
    OPL3_EnvelopeCalc(&chip.slot.ptr[ii]);
  }

  if (chip.rhy&0x20) {
    OPL3_GenerateRhythm1(&chip);
  } else {
    OPL3_SlotGenerate(&chip.slot.ptr[12]);
    OPL3_SlotGenerate(&chip.slot.ptr[13]);
    OPL3_SlotGenerate(&chip.slot.ptr[14]);
  }

  chip.mixbuff.ptr[0] = 0;
  for (ii = 0; ii < 18; ++ii) {
    accm = 0;
    for (jj = 0; jj < 4; ++jj) accm += *chip.channel.ptr[ii].out_.ptr[jj];
    chip.mixbuff.ptr[0] += cast(short)(accm&chip.channel.ptr[ii].cha);
  }

  for (ii = 15; ii < 18; ++ii) {
    OPL3_SlotCalcFB(&chip.slot.ptr[ii]);
    OPL3_PhaseGenerate(&chip.slot.ptr[ii]);
    OPL3_EnvelopeCalc(&chip.slot.ptr[ii]);
  }

  if (chip.rhy&0x20) {
    OPL3_GenerateRhythm2(&chip);
  } else {
    OPL3_SlotGenerate(&chip.slot.ptr[15]);
    OPL3_SlotGenerate(&chip.slot.ptr[16]);
    OPL3_SlotGenerate(&chip.slot.ptr[17]);
  }

  buf[0] = OPL3_ClipSample(chip.mixbuff.ptr[0]);

  for (ii = 18; ii < 33; ++ii) {
    OPL3_SlotCalcFB(&chip.slot.ptr[ii]);
    OPL3_PhaseGenerate(&chip.slot.ptr[ii]);
    OPL3_EnvelopeCalc(&chip.slot.ptr[ii]);
    OPL3_SlotGenerate(&chip.slot.ptr[ii]);
  }

  chip.mixbuff.ptr[1] = 0;
  for (ii = 0; ii < 18; ++ii) {
    accm = 0;
    for (jj = 0; jj < 4; jj++) accm += *chip.channel.ptr[ii].out_.ptr[jj];
    chip.mixbuff.ptr[1] += cast(short)(accm&chip.channel.ptr[ii].chb);
  }

  for (ii = 33; ii < 36; ++ii) {
    OPL3_SlotCalcFB(&chip.slot.ptr[ii]);
    OPL3_PhaseGenerate(&chip.slot.ptr[ii]);
    OPL3_EnvelopeCalc(&chip.slot.ptr[ii]);
    OPL3_SlotGenerate(&chip.slot.ptr[ii]);
  }

  OPL3_NoiseGenerate(&chip);

  if ((chip.timer&0x3f) == 0x3f) chip.tremolopos = (chip.tremolopos+1)%210;
  chip.tremolo = (chip.tremolopos < 105 ? chip.tremolopos>>chip.tremoloshift : cast(ubyte)((210-chip.tremolopos)>>chip.tremoloshift));
  if ((chip.timer&0x3ff) == 0x3ff) chip.vibpos = (chip.vibpos+1)&7;

  ++chip.timer;

  while (chip.writebuf.ptr[chip.writebuf_cur].time <= chip.writebuf_samplecnt) {
    if (!(chip.writebuf.ptr[chip.writebuf_cur].reg&0x200)) break;
    chip.writebuf.ptr[chip.writebuf_cur].reg &= 0x1ff;
    chip.writeReg(chip.writebuf.ptr[chip.writebuf_cur].reg, chip.writebuf.ptr[chip.writebuf_cur].data);
    chip.writebuf_cur = (chip.writebuf_cur+1)%OPL_WRITEBUF_SIZE;
  }
  ++chip.writebuf_samplecnt;
}


/// OPL3_GenerateResampled
public void generateResampled (ref OPL3Chip chip, short* buf) {
  while (chip.samplecnt >= chip.rateratio) {
    chip.oldsamples.ptr[0] = chip.samples.ptr[0];
    chip.oldsamples.ptr[1] = chip.samples.ptr[1];
    chip.generate(chip.samples.ptr);
    chip.samplecnt -= chip.rateratio;
  }
  buf[0] = cast(short)((chip.oldsamples.ptr[0]*(chip.rateratio-chip.samplecnt)+chip.samples.ptr[0]*chip.samplecnt)/chip.rateratio);
  buf[1] = cast(short)((chip.oldsamples.ptr[1]*(chip.rateratio-chip.samplecnt)+chip.samples.ptr[1]*chip.samplecnt)/chip.rateratio);
  chip.samplecnt += 1<<RSM_FRAC;
}


/// OPL3_Reset
public void reset (ref OPL3Chip chip, uint samplerate) {
  ubyte slotnum;
  ubyte channum;

  //ubyte* cc = cast(ubyte*)chip;
  //cc[0..OPL3Chip.sizeof] = 0;
  chip = chip.init;

  for (slotnum = 0; slotnum < 36; ++slotnum) {
    chip.slot.ptr[slotnum].chip = &chip;
    chip.slot.ptr[slotnum].mod = &chip.zeromod;
    chip.slot.ptr[slotnum].eg_rout = 0x1ff;
    chip.slot.ptr[slotnum].eg_out = 0x1ff;
    chip.slot.ptr[slotnum].eg_gen = envelope_gen_num_off;
    chip.slot.ptr[slotnum].trem = cast(ubyte*)&chip.zeromod;
  }
  for (channum = 0; channum < 18; ++channum) {
    chip.channel.ptr[channum].slots.ptr[0] = &chip.slot.ptr[ch_slot.ptr[channum]];
    chip.channel.ptr[channum].slots.ptr[1] = &chip.slot.ptr[ch_slot.ptr[channum]+3];
    chip.slot.ptr[ch_slot.ptr[channum]].channel = &chip.channel.ptr[channum];
    chip.slot.ptr[ch_slot.ptr[channum]+3].channel = &chip.channel.ptr[channum];
         if ((channum%9) < 3) chip.channel.ptr[channum].pair = &chip.channel.ptr[channum+3];
    else if ((channum%9) < 6) chip.channel.ptr[channum].pair = &chip.channel.ptr[channum-3];
    chip.channel.ptr[channum].chip = &chip;
    chip.channel.ptr[channum].out_.ptr[0] = &chip.zeromod;
    chip.channel.ptr[channum].out_.ptr[1] = &chip.zeromod;
    chip.channel.ptr[channum].out_.ptr[2] = &chip.zeromod;
    chip.channel.ptr[channum].out_.ptr[3] = &chip.zeromod;
    chip.channel.ptr[channum].chtype = ch_2op;
    chip.channel.ptr[channum].cha = ushort.max;
    chip.channel.ptr[channum].chb = ushort.max;
    OPL3_ChannelSetupAlg(&chip.channel.ptr[channum]);
  }
  chip.noise = 0x306600;
  chip.rateratio = (samplerate<<RSM_FRAC)/OPL_RATE;
  chip.tremoloshift = 4;
  chip.vibshift = 1;
}


/// OPL3_WriteReg
public void writeReg (ref OPL3Chip chip, ushort reg, ubyte v) {
  ubyte high = (reg>>8)&0x01;
  ubyte regm = reg&0xff;
  switch (regm&0xf0) {
    case 0x00:
      if (high) {
        switch (regm&0x0f) {
          case 0x04:
            OPL3_ChannelSet4Op(&chip, v);
            break;
          case 0x05:
            chip.newm = v&0x01;
            break;
          default: break;
        }
      } else {
        switch (regm&0x0f) {
          case 0x08:
            chip.nts = (v>>6)&0x01;
            break;
          default: break;
        }
      }
      break;
    case 0x20:
    case 0x30:
      if (ad_slot.ptr[regm&0x1f] >= 0) OPL3_SlotWrite20(&chip.slot.ptr[18*high+ad_slot.ptr[regm&0x1f]], v);
      break;
    case 0x40:
    case 0x50:
      if (ad_slot.ptr[regm&0x1f] >= 0) OPL3_SlotWrite40(&chip.slot.ptr[18*high+ad_slot.ptr[regm&0x1f]], v);
      break;
    case 0x60:
    case 0x70:
      if (ad_slot.ptr[regm&0x1f] >= 0) OPL3_SlotWrite60(&chip.slot.ptr[18*high+ad_slot.ptr[regm&0x1f]], v);
      break;
    case 0x80:
    case 0x90:
      if (ad_slot.ptr[regm&0x1f] >= 0) OPL3_SlotWrite80(&chip.slot.ptr[18*high+ad_slot.ptr[regm&0x1f]], v);
      break;
    case 0xe0:
    case 0xf0:
      if (ad_slot.ptr[regm&0x1f] >= 0) OPL3_SlotWriteE0(&chip.slot.ptr[18*high+ad_slot.ptr[regm&0x1f]], v);
      break;
    case 0xa0:
      if ((regm&0x0f) < 9) OPL3_ChannelWriteA0(&chip.channel.ptr[9*high+(regm&0x0f)], v);
      break;
    case 0xb0:
      if (regm == 0xbd && !high) {
        chip.tremoloshift = (((v>>7)^1)<<1)+2;
        chip.vibshift = ((v>>6)&0x01)^1;
        OPL3_ChannelUpdateRhythm(&chip, v);
      } else if ((regm&0x0f) < 9) {
        OPL3_ChannelWriteB0(&chip.channel.ptr[9*high+(regm&0x0f)], v);
        if (v&0x20) OPL3_ChannelKeyOn(&chip.channel.ptr[9*high+(regm&0x0f)]); else OPL3_ChannelKeyOff(&chip.channel.ptr[9*high+(regm&0x0f)]);
      }
      break;
    case 0xc0:
      if ((regm&0x0f) < 9) OPL3_ChannelWriteC0(&chip.channel.ptr[9*high+(regm&0x0f)], v);
      break;
    default: break;
  }
}


/// OPL3_WriteRegBuffered
public void writeRegBuffered (ref OPL3Chip chip, ushort reg, ubyte v) {
  ulong time1, time2;

  if (chip.writebuf.ptr[chip.writebuf_last].reg&0x200) {
    chip.writeReg(chip.writebuf.ptr[chip.writebuf_last].reg&0x1ff, chip.writebuf.ptr[chip.writebuf_last].data);
    chip.writebuf_cur = (chip.writebuf_last+1)%OPL_WRITEBUF_SIZE;
    chip.writebuf_samplecnt = chip.writebuf.ptr[chip.writebuf_last].time;
  }

  chip.writebuf.ptr[chip.writebuf_last].reg = reg|0x200;
  chip.writebuf.ptr[chip.writebuf_last].data = v;
  time1 = chip.writebuf_lasttime+OPL_WRITEBUF_DELAY;
  time2 = chip.writebuf_samplecnt;

  if (time1 < time2) time1 = time2;

  chip.writebuf.ptr[chip.writebuf_last].time = time1;
  chip.writebuf_lasttime = time1;
  chip.writebuf_last = (chip.writebuf_last+1)%OPL_WRITEBUF_SIZE;
}


/// OPL3_GenerateStream; outputs STEREO stream
public void generateStream (ref OPL3Chip chip, short[] smpbuf) {
  auto sndptr = smpbuf.ptr;
  foreach (immutable _; 0..smpbuf.length/2) {
    chip.generateResampled(sndptr);
    sndptr += 2;
  }
}


// ////////////////////////////////////////////////////////////////////////// //
// simple DooM MUS / Midi player
public final class OPLPlayer {
private:
  static immutable ubyte[128] opl_voltable = [
    0x00, 0x01, 0x03, 0x05, 0x06, 0x08, 0x0a, 0x0b,
    0x0d, 0x0e, 0x10, 0x11, 0x13, 0x14, 0x16, 0x17,
    0x19, 0x1a, 0x1b, 0x1d, 0x1e, 0x20, 0x21, 0x22,
    0x24, 0x25, 0x27, 0x29, 0x2b, 0x2d, 0x2f, 0x31,
    0x32, 0x34, 0x36, 0x37, 0x39, 0x3b, 0x3c, 0x3d,
    0x3f, 0x40, 0x42, 0x43, 0x44, 0x45, 0x47, 0x48,
    0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4f, 0x50, 0x51,
    0x52, 0x53, 0x54, 0x54, 0x55, 0x56, 0x57, 0x58,
    0x59, 0x5a, 0x5b, 0x5c, 0x5c, 0x5d, 0x5e, 0x5f,
    0x60, 0x60, 0x61, 0x62, 0x63, 0x63, 0x64, 0x65,
    0x65, 0x66, 0x67, 0x67, 0x68, 0x69, 0x69, 0x6a,
    0x6b, 0x6b, 0x6c, 0x6d, 0x6d, 0x6e, 0x6e, 0x6f,
    0x70, 0x70, 0x71, 0x71, 0x72, 0x72, 0x73, 0x73,
    0x74, 0x75, 0x75, 0x76, 0x76, 0x77, 0x77, 0x78,
    0x78, 0x79, 0x79, 0x7a, 0x7a, 0x7b, 0x7b, 0x7b,
    0x7c, 0x7c, 0x7d, 0x7d, 0x7e, 0x7e, 0x7f, 0x7f
  ];

  static immutable ushort[284+384] opl_freqtable = [
    0x0133, 0x0133, 0x0134, 0x0134, 0x0135, 0x0136, 0x0136, 0x0137,
    0x0137, 0x0138, 0x0138, 0x0139, 0x0139, 0x013a, 0x013b, 0x013b,
    0x013c, 0x013c, 0x013d, 0x013d, 0x013e, 0x013f, 0x013f, 0x0140,
    0x0140, 0x0141, 0x0142, 0x0142, 0x0143, 0x0143, 0x0144, 0x0144,
    0x0145, 0x0146, 0x0146, 0x0147, 0x0147, 0x0148, 0x0149, 0x0149,
    0x014a, 0x014a, 0x014b, 0x014c, 0x014c, 0x014d, 0x014d, 0x014e,
    0x014f, 0x014f, 0x0150, 0x0150, 0x0151, 0x0152, 0x0152, 0x0153,
    0x0153, 0x0154, 0x0155, 0x0155, 0x0156, 0x0157, 0x0157, 0x0158,
    0x0158, 0x0159, 0x015a, 0x015a, 0x015b, 0x015b, 0x015c, 0x015d,
    0x015d, 0x015e, 0x015f, 0x015f, 0x0160, 0x0161, 0x0161, 0x0162,
    0x0162, 0x0163, 0x0164, 0x0164, 0x0165, 0x0166, 0x0166, 0x0167,
    0x0168, 0x0168, 0x0169, 0x016a, 0x016a, 0x016b, 0x016c, 0x016c,
    0x016d, 0x016e, 0x016e, 0x016f, 0x0170, 0x0170, 0x0171, 0x0172,
    0x0172, 0x0173, 0x0174, 0x0174, 0x0175, 0x0176, 0x0176, 0x0177,
    0x0178, 0x0178, 0x0179, 0x017a, 0x017a, 0x017b, 0x017c, 0x017c,
    0x017d, 0x017e, 0x017e, 0x017f, 0x0180, 0x0181, 0x0181, 0x0182,
    0x0183, 0x0183, 0x0184, 0x0185, 0x0185, 0x0186, 0x0187, 0x0188,
    0x0188, 0x0189, 0x018a, 0x018a, 0x018b, 0x018c, 0x018d, 0x018d,
    0x018e, 0x018f, 0x018f, 0x0190, 0x0191, 0x0192, 0x0192, 0x0193,
    0x0194, 0x0194, 0x0195, 0x0196, 0x0197, 0x0197, 0x0198, 0x0199,
    0x019a, 0x019a, 0x019b, 0x019c, 0x019d, 0x019d, 0x019e, 0x019f,
    0x01a0, 0x01a0, 0x01a1, 0x01a2, 0x01a3, 0x01a3, 0x01a4, 0x01a5,
    0x01a6, 0x01a6, 0x01a7, 0x01a8, 0x01a9, 0x01a9, 0x01aa, 0x01ab,
    0x01ac, 0x01ad, 0x01ad, 0x01ae, 0x01af, 0x01b0, 0x01b0, 0x01b1,
    0x01b2, 0x01b3, 0x01b4, 0x01b4, 0x01b5, 0x01b6, 0x01b7, 0x01b8,
    0x01b8, 0x01b9, 0x01ba, 0x01bb, 0x01bc, 0x01bc, 0x01bd, 0x01be,
    0x01bf, 0x01c0, 0x01c0, 0x01c1, 0x01c2, 0x01c3, 0x01c4, 0x01c4,
    0x01c5, 0x01c6, 0x01c7, 0x01c8, 0x01c9, 0x01c9, 0x01ca, 0x01cb,
    0x01cc, 0x01cd, 0x01ce, 0x01ce, 0x01cf, 0x01d0, 0x01d1, 0x01d2,
    0x01d3, 0x01d3, 0x01d4, 0x01d5, 0x01d6, 0x01d7, 0x01d8, 0x01d8,
    0x01d9, 0x01da, 0x01db, 0x01dc, 0x01dd, 0x01de, 0x01de, 0x01df,
    0x01e0, 0x01e1, 0x01e2, 0x01e3, 0x01e4, 0x01e5, 0x01e5, 0x01e6,
    0x01e7, 0x01e8, 0x01e9, 0x01ea, 0x01eb, 0x01ec, 0x01ed, 0x01ed,
    0x01ee, 0x01ef, 0x01f0, 0x01f1, 0x01f2, 0x01f3, 0x01f4, 0x01f5,
    0x01f6, 0x01f6, 0x01f7, 0x01f8, 0x01f9, 0x01fa, 0x01fb, 0x01fc,
    0x01fd, 0x01fe, 0x01ff, 0x0200, 0x0201, 0x0201, 0x0202, 0x0203,
    0x0204, 0x0205, 0x0206, 0x0207, 0x0208, 0x0209, 0x020a, 0x020b,
    0x020c, 0x020d, 0x020e, 0x020f, 0x0210, 0x0210, 0x0211, 0x0212,
    0x0213, 0x0214, 0x0215, 0x0216, 0x0217, 0x0218, 0x0219, 0x021a,
    0x021b, 0x021c, 0x021d, 0x021e, 0x021f, 0x0220, 0x0221, 0x0222,
    0x0223, 0x0224, 0x0225, 0x0226, 0x0227, 0x0228, 0x0229, 0x022a,
    0x022b, 0x022c, 0x022d, 0x022e, 0x022f, 0x0230, 0x0231, 0x0232,
    0x0233, 0x0234, 0x0235, 0x0236, 0x0237, 0x0238, 0x0239, 0x023a,
    0x023b, 0x023c, 0x023d, 0x023e, 0x023f, 0x0240, 0x0241, 0x0242,
    0x0244, 0x0245, 0x0246, 0x0247, 0x0248, 0x0249, 0x024a, 0x024b,
    0x024c, 0x024d, 0x024e, 0x024f, 0x0250, 0x0251, 0x0252, 0x0253,
    0x0254, 0x0256, 0x0257, 0x0258, 0x0259, 0x025a, 0x025b, 0x025c,
    0x025d, 0x025e, 0x025f, 0x0260, 0x0262, 0x0263, 0x0264, 0x0265,
    0x0266, 0x0267, 0x0268, 0x0269, 0x026a, 0x026c, 0x026d, 0x026e,
    0x026f, 0x0270, 0x0271, 0x0272, 0x0273, 0x0275, 0x0276, 0x0277,
    0x0278, 0x0279, 0x027a, 0x027b, 0x027d, 0x027e, 0x027f, 0x0280,
    0x0281, 0x0282, 0x0284, 0x0285, 0x0286, 0x0287, 0x0288, 0x0289,
    0x028b, 0x028c, 0x028d, 0x028e, 0x028f, 0x0290, 0x0292, 0x0293,
    0x0294, 0x0295, 0x0296, 0x0298, 0x0299, 0x029a, 0x029b, 0x029c,
    0x029e, 0x029f, 0x02a0, 0x02a1, 0x02a2, 0x02a4, 0x02a5, 0x02a6,
    0x02a7, 0x02a9, 0x02aa, 0x02ab, 0x02ac, 0x02ae, 0x02af, 0x02b0,
    0x02b1, 0x02b2, 0x02b4, 0x02b5, 0x02b6, 0x02b7, 0x02b9, 0x02ba,
    0x02bb, 0x02bd, 0x02be, 0x02bf, 0x02c0, 0x02c2, 0x02c3, 0x02c4,
    0x02c5, 0x02c7, 0x02c8, 0x02c9, 0x02cb, 0x02cc, 0x02cd, 0x02ce,
    0x02d0, 0x02d1, 0x02d2, 0x02d4, 0x02d5, 0x02d6, 0x02d8, 0x02d9,
    0x02da, 0x02dc, 0x02dd, 0x02de, 0x02e0, 0x02e1, 0x02e2, 0x02e4,
    0x02e5, 0x02e6, 0x02e8, 0x02e9, 0x02ea, 0x02ec, 0x02ed, 0x02ee,
    0x02f0, 0x02f1, 0x02f2, 0x02f4, 0x02f5, 0x02f6, 0x02f8, 0x02f9,
    0x02fb, 0x02fc, 0x02fd, 0x02ff, 0x0300, 0x0302, 0x0303, 0x0304,
    0x0306, 0x0307, 0x0309, 0x030a, 0x030b, 0x030d, 0x030e, 0x0310,
    0x0311, 0x0312, 0x0314, 0x0315, 0x0317, 0x0318, 0x031a, 0x031b,
    0x031c, 0x031e, 0x031f, 0x0321, 0x0322, 0x0324, 0x0325, 0x0327,
    0x0328, 0x0329, 0x032b, 0x032c, 0x032e, 0x032f, 0x0331, 0x0332,
    0x0334, 0x0335, 0x0337, 0x0338, 0x033a, 0x033b, 0x033d, 0x033e,
    0x0340, 0x0341, 0x0343, 0x0344, 0x0346, 0x0347, 0x0349, 0x034a,
    0x034c, 0x034d, 0x034f, 0x0350, 0x0352, 0x0353, 0x0355, 0x0357,
    0x0358, 0x035a, 0x035b, 0x035d, 0x035e, 0x0360, 0x0361, 0x0363,
    0x0365, 0x0366, 0x0368, 0x0369, 0x036b, 0x036c, 0x036e, 0x0370,
    0x0371, 0x0373, 0x0374, 0x0376, 0x0378, 0x0379, 0x037b, 0x037c,
    0x037e, 0x0380, 0x0381, 0x0383, 0x0384, 0x0386, 0x0388, 0x0389,
    0x038b, 0x038d, 0x038e, 0x0390, 0x0392, 0x0393, 0x0395, 0x0397,
    0x0398, 0x039a, 0x039c, 0x039d, 0x039f, 0x03a1, 0x03a2, 0x03a4,
    0x03a6, 0x03a7, 0x03a9, 0x03ab, 0x03ac, 0x03ae, 0x03b0, 0x03b1,
    0x03b3, 0x03b5, 0x03b7, 0x03b8, 0x03ba, 0x03bc, 0x03bd, 0x03bf,
    0x03c1, 0x03c3, 0x03c4, 0x03c6, 0x03c8, 0x03ca, 0x03cb, 0x03cd,
    0x03cf, 0x03d1, 0x03d2, 0x03d4, 0x03d6, 0x03d8, 0x03da, 0x03db,
    0x03dd, 0x03df, 0x03e1, 0x03e3, 0x03e4, 0x03e6, 0x03e8, 0x03ea,
    0x03ec, 0x03ed, 0x03ef, 0x03f1, 0x03f3, 0x03f5, 0x03f6, 0x03f8,
    0x03fa, 0x03fc, 0x03fe, 0x036c
  ];

private:
  // GenMidi lump structure
  static align(1) struct GenMidi {
  align(1):
  public:
    static align(1) struct Operator {
    align(1):
      ubyte mult; /* Tremolo / vibrato / sustain / KSR / multi */
      ubyte attack; /* Attack rate / decay rate */
      ubyte sustain; /* Sustain level / release rate */
      ubyte wave; /* Waveform select */
      ubyte ksl; /* Key scale level */
      ubyte level; /* Output level */
      ubyte feedback; /* Feedback for modulator, unused for carrier */
    }

    static align(1) struct Voice {
    align(1):
      Operator mod; /* modulator */
      Operator car; /* carrier */
      /* Base note offset. This is used to offset the MIDI note values.
         Several of the GENMIDI instruments have a base note offset of -12,
         causing all notes to be offset down by one octave. */
      short offset;
    }

    static align(1) struct Patch {
    align(1):
    public:
      enum Flag : ushort {
        Fixed = 0x01,
        DualVoice = 0x04,
      }
    public:
      /* bit 0: Fixed pitch - Instrument always plays the same note.
                Most MIDI instruments play a note that is specified in the MIDI "key on" event,
                but some (most notably percussion instruments) always play the same fixed note.
         bit 1: Unknown - used in instrument #65 of the Doom GENMIDI lump.
         bit 2: Double voice - Play two voices simultaneously. This is used even on an OPL2 chip.
                If this is not set, only the first voice is played. If it is set, the fine tuning
                field (see below) can be used to adjust the pitch of the second voice relative to
                the first.
      */
      version(genmidi_dumper) {
        ushort flags;
      } else {
        ubyte flags;
      }
      /* Fine tuning - This normally has a value of 128, but can be adjusted to adjust the tuning of
         the instrument. This field only applies to the second voice of double-voice instruments;
         for single voice instruments it has no effect. The offset values are similar to MIDI pitch
         bends; for example, a value of 82 (hex) in this field is equivalent to a MIDI pitch bend of +256.
       */
      ubyte finetune;
      /* Note number used for fixed pitch instruments */
      ubyte note;
      Voice[2] voice;
      version(genmidi_dumper) {
        // no name in this mode
      } else {
        string name; // patch name
      }
    }

  public:
    //char[8] header;
    Patch[175] patch;
    version(genmidi_dumper) {
      char[32][175] namestrs; // patch names
      @property const(char)[] name (usize patchidx) const pure nothrow @safe @nogc {
        const(char)[] res = namestrs[patchidx][];
        foreach (immutable idx, immutable char ch; res) if (ch == 0) return res[0..idx];
        return res;
      }
    }

  public:
    version(genmidi_dumper) {
      void dump (VFile fo) {
        fo.writeln("static immutable GenMidi mGenMidi = GenMidi([");
        foreach (immutable idx, const ref Patch pt; patch[]) {
          fo.write("  GenMidi.Patch(");
          fo.writef("0x%02x,", pt.flags);
          fo.writef("%3u,", pt.finetune);
          fo.writef("%3u,[", pt.note);
          // voices
          foreach (immutable vidx, const ref v; pt.voice[]) {
            fo.write("GenMidi.Voice(");
            fo.write("GenMidi.Operator(");
            fo.writef("%3u,", v.mod.mult);
            fo.writef("%3u,", v.mod.attack);
            fo.writef("%3u,", v.mod.sustain);
            fo.writef("%3u,", v.mod.wave);
            fo.writef("%3u,", v.mod.ksl);
            fo.writef("%3u,", v.mod.level);
            fo.writef("%3u),", v.mod.feedback);
            fo.write("GenMidi.Operator(");
            fo.writef("%3u,", v.car.mult);
            fo.writef("%3u,", v.car.attack);
            fo.writef("%3u,", v.car.sustain);
            fo.writef("%3u,", v.car.wave);
            fo.writef("%3u,", v.car.ksl);
            fo.writef("%3u,", v.car.level);
            fo.writef("%3u),", v.car.feedback);
            fo.writef("%4d),", v.offset);
          }
          fo.write("],", name(idx).quote);
          fo.writeln("),");
        }
        fo.writeln("]);");
      }
    }
  }

  version(genmidi_dumper) {
  } else {
    //mixin(import("zgenmidi.d"));
    static immutable GenMidi mGenMidi = GenMidi([
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,240,243,  1, 64, 20, 10),GenMidi.Operator( 48,241,244,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Grand Piano"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,240,243,  0, 64, 18, 10),GenMidi.Operator( 48,241,244,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Bright Acoustic Piano"),
      GenMidi.Patch(0x04,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,225,243,  1, 64, 14,  8),GenMidi.Operator( 48,241,244,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 17,232, 21,  0,  0,  0,  1),GenMidi.Operator( 18,247, 20,  0,  0,  0,  0),   0),],"Electric Grand Piano"),
      GenMidi.Patch(0x04,130,  0,[GenMidi.Voice(GenMidi.Operator( 16,241, 83,  1, 64, 15,  6),GenMidi.Operator( 16,209,244,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 17,241, 83,  0, 64, 15,  6),GenMidi.Operator( 17,209,244,  0,  0,  0,  0),   0),],"Honky-tonk Piano"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 33,241, 81,  0, 64, 38,  6),GenMidi.Operator( 49,210,229,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Rhodes Paino"),
      GenMidi.Patch(0x04,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,241,230,  0, 64, 17,  6),GenMidi.Operator(176,241,229,  0, 64,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 18,242,121,  0, 64,  3,  9),GenMidi.Operator( 16,241,153,  0, 64,  0,  0),   0),],"Chorused Piano"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,242,  1,  2,128,  7,  6),GenMidi.Operator( 48,193,244,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Harpsichord"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(144,161, 98,  1,128, 14, 12),GenMidi.Operator( 16,145,167,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Clavinet"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 40,242,100,  1, 64, 15,  8),GenMidi.Operator( 49,242,228,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Celesta"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 19,145, 17,  0,  0, 14,  9),GenMidi.Operator( 20,125, 52,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Glockenspiel"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(178,246, 65,  0,  0, 15,  0),GenMidi.Operator(144,210,146,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Music Box"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240,241,243,  0,  0,  2,  1),GenMidi.Operator(242,241,244,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Vibraphone"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(128,121, 21,  0,  0,  0,  1),GenMidi.Operator(131,248,117,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Marimba"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 20,246,147,  0,  0, 31,  8),GenMidi.Operator( 16,246, 83,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Xylophone"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(129,182, 19,  1,128, 25, 10),GenMidi.Operator(  2,255, 19,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Tubular-bell"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,145, 17,  0, 64,  7,  8),GenMidi.Operator( 17, 82, 83,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Dulcimer"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160,177, 22,  0,128,  8,  7),GenMidi.Operator( 97,209, 23,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Hammond Organ"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,241,  5,  1,  0,  0,  7),GenMidi.Operator(148,244, 54,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Percussive Organ"),
      GenMidi.Patch(0x04,138,  0,[GenMidi.Voice(GenMidi.Operator(226,242, 23,  0,128, 30,  0),GenMidi.Operator( 96,255,  7,  1,128,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(224,242, 23,  1,128, 30,  0),GenMidi.Operator(160,255,  7,  0,128,  0,  0),   0),],"Rock Organ"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48, 48,  4,  0,128, 18,  9),GenMidi.Operator( 49, 84, 20,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 49, 84, 20,  2,128, 18,  9),GenMidi.Operator( 48,253, 68,  0,128,  0,  0),   0),],"Church Organ"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,128, 23,  0, 64,  9,  6),GenMidi.Operator(129, 96, 23,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Reed Organ"),
      GenMidi.Patch(0x04,125,  0,[GenMidi.Voice(GenMidi.Operator( 32,162, 21,  0, 64,  8, 10),GenMidi.Operator( 49, 65, 38,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,130, 21,  0, 64, 10, 10),GenMidi.Operator( 49, 70, 38,  1,  0,  0,  0),   0),],"Accordion"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176, 96, 52,  0,  0, 12,  8),GenMidi.Operator(178, 66, 22,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(176, 96, 52,  0,  0, 12,  8),GenMidi.Operator(178, 66, 22,  0,128,  0,  0),  12),],"Harmonica"),
      GenMidi.Patch(0x04,129,  0,[GenMidi.Voice(GenMidi.Operator( 32,240,  5,  1,128, 18,  8),GenMidi.Operator( 49, 82,  5,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,240,  5,  1,128, 18,  0),GenMidi.Operator( 49, 82,  5,  2,  0,  0,  0),   0),],"Tango Accordion"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,241,245,  0,128, 13,  0),GenMidi.Operator( 32,241,246,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Guitar (nylon)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,225,228,  1,  0, 13, 10),GenMidi.Operator( 48,242,227,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Guitar (steel)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,241, 31,  2,  0, 33, 10),GenMidi.Operator(  0,244,136,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Electric Guitar (jazz)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 16,234, 50,  1,128,  7,  2),GenMidi.Operator( 16,210,231,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Electric Guitar (clean)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,224,244,  0,128, 18,  0),GenMidi.Operator( 48,242,245,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Electric Guitar (muted)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,241,255,  0,  0, 16, 10),GenMidi.Operator( 81,240,255,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),   0),],"Overdriven Guitar"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 16,241,255,  0,  0, 13, 12),GenMidi.Operator( 81,240,255,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),   0),],"Distortion Guitar"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 16,161,151,  2, 64,  3,  0),GenMidi.Operator( 17,225,231,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Guitar Harmonics"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,196, 32,  0,  0, 14,  0),GenMidi.Operator(176,195,246,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),GenMidi.Operator(  0,  0,  0,  0,  0,  0,  0),   0),],"Acoustic Bass"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,240,255,  0,128, 22, 10),GenMidi.Operator( 49,241,248,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Electric Bass (finger)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,224, 20,  0,128, 15,  8),GenMidi.Operator( 48,225,214,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Electric Bass (pick)"),
      GenMidi.Patch(0x04,126,  0,[GenMidi.Voice(GenMidi.Operator(225, 81, 69,  1, 64, 13,  0),GenMidi.Operator(160,145, 70,  1,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(161, 81, 69,  1, 64, 13,  0),GenMidi.Operator(160,129, 70,  1,  0,  0,  0),   0),],"Fretless Bass"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,240,231,  2,  0,  0,  0),GenMidi.Operator( 49,241, 71,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator( 16,245,231,  1,  0, 13, 13),GenMidi.Operator( 16,246,231,  2,  0,  0,  0),   0),],"* Slap Bass 1"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,240,229,  0,128, 16,  8),GenMidi.Operator( 49,241,245,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Slap Bass 2"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,244,245,  1,  0, 10, 10),GenMidi.Operator( 48,243,246,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Synth Bass 1"),
      GenMidi.Patch(0x04,118,  0,[GenMidi.Voice(GenMidi.Operator( 48,131, 70,  1,  0, 21, 10),GenMidi.Operator( 49,210, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 48,131, 70,  1,  0, 21, 10),GenMidi.Operator( 49,210, 23,  0,  0,  0,  0),   0),],"Synth Bass 2"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 96, 80, 69,  1,  0, 23,  6),GenMidi.Operator(161, 97, 70,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Violin"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240, 96, 68,  0,128, 15,  2),GenMidi.Operator(113, 65, 21,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Viola"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176,208, 20,  2,  0, 15,  6),GenMidi.Operator( 97, 98, 23,  1,128,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Cello"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240,177, 17,  2,128, 10,  6),GenMidi.Operator( 32,160, 21,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Contrabass"),
      GenMidi.Patch(0x04,139,  0,[GenMidi.Voice(GenMidi.Operator(240,195,  1,  2,128,  9,  6),GenMidi.Operator( 97,131,  5,  0, 64,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(112,179,  1,  2,128,  9,  6),GenMidi.Operator( 96,147,  5,  1, 64,  0,  0),   0),],"Tremolo Strings"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,248,249,  2,128, 23, 14),GenMidi.Operator( 32,118,230,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Pizzicato Strings"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 49,241, 53,  0,  0, 36,  0),GenMidi.Operator( 32,243,179,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Orchestral Harp"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,170,200,  0,  0,  4, 10),GenMidi.Operator( 16,210,179,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Timpani"),
      GenMidi.Patch(0x04,120,  0,[GenMidi.Voice(GenMidi.Operator( 96,192,  4,  1, 64, 17,  4),GenMidi.Operator(177, 85,  4,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(160,144,  4,  1, 64, 18,  6),GenMidi.Operator( 49, 85,  4,  1,128,  0,  0),   0),],"String Ensemble 1"),
      GenMidi.Patch(0x04,133,  0,[GenMidi.Voice(GenMidi.Operator( 32,144,  5,  1, 64, 17,  4),GenMidi.Operator(161, 53,  5,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(160,144,  5,  1, 64, 18,  6),GenMidi.Operator( 33, 53,  5,  1,128,  0,  0),   0),],"String Ensemble 2"),
      GenMidi.Patch(0x04,123,  0,[GenMidi.Voice(GenMidi.Operator(161,105,  5,  2,128, 19, 10),GenMidi.Operator(241,102,  2,  2,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(161,105,  5,  2,128, 19, 10),GenMidi.Operator(241,102,  2,  2,  0,  0,  0), -12),],"Synth Strings 1"),
      GenMidi.Patch(0x04,132,  0,[GenMidi.Voice(GenMidi.Operator( 33, 17,  3,  0, 64, 13,  0),GenMidi.Operator( 32, 49,  4,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0, 17, 51,  2,128,  2,  8),GenMidi.Operator(  0, 49, 54,  1,128,  0,  0),   0),],"Synth Strings 2"),
      GenMidi.Patch(0x04,138,  0,[GenMidi.Voice(GenMidi.Operator( 96,144, 84,  0, 64, 22,  0),GenMidi.Operator( 96,112,  4,  0, 64,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,144, 84,  0,128, 18,  0),GenMidi.Operator( 96,112,  4,  0,192,  0,  0),   0),],"Choir Aahs"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160,177,183,  0,128, 25,  0),GenMidi.Operator(160,114,133,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 18,102,240,  0,192,  6, 12),GenMidi.Operator( 81,174,182,  0,192,  0,  0), -12),],"Voice Oohs"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176, 96, 84,  0, 64, 26,  0),GenMidi.Operator(176, 48,116,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Synth Voice"),
      GenMidi.Patch(0x04,128,  0,[GenMidi.Voice(GenMidi.Operator( 16, 48, 67,  0,128, 16,  2),GenMidi.Operator( 16,100, 20,  0,  0,  0,  0), -24),GenMidi.Voice(GenMidi.Operator(144, 80, 66,  0,128, 15,  2),GenMidi.Operator( 17, 84, 69,  0,  0,  0,  0), -12),],"Orchestra Hit"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,128, 21,  1,128, 14, 10),GenMidi.Operator( 48, 81, 54,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Trumpet"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176,113, 31,  0,  0, 26, 14),GenMidi.Operator( 32,114, 59,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Trombone"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,128, 70,  0,  0, 22, 12),GenMidi.Operator( 32,146, 86,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,128,  0,  0),GenMidi.Operator(  0,  0,240,  0,128,  0,  0),   0),],"Tuba"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(128,128,230,  1,128, 13, 12),GenMidi.Operator(144, 81,246,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Muted Trumpet"),
      GenMidi.Patch(0x04,129,  0,[GenMidi.Voice(GenMidi.Operator( 32,112,184,  0,  0, 34, 14),GenMidi.Operator( 32, 97,150,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,112,184,  0,  0, 35, 14),GenMidi.Operator( 32, 97,150,  0,128,  0,  0),   0),],"French Horn"),
      GenMidi.Patch(0x04,131,  0,[GenMidi.Voice(GenMidi.Operator( 32, 96, 21,  1,128, 14, 10),GenMidi.Operator( 48, 81, 54,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 48,112, 23,  1,128, 18, 14),GenMidi.Operator( 48, 97, 54,  1,  0,  0,  0),   0),],"Brass Section"),
      GenMidi.Patch(0x04,134,  0,[GenMidi.Voice(GenMidi.Operator( 32,145,166,  2, 64, 13, 12),GenMidi.Operator( 32,129,151,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,145,166,  2,128, 12, 12),GenMidi.Operator( 32,145,151,  1,  0,  0,  0),   0),],"Synth Brass 1"),
      GenMidi.Patch(0x04,134,  0,[GenMidi.Voice(GenMidi.Operator( 48,129,166,  2, 64, 16, 12),GenMidi.Operator( 48, 97,151,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 48,129,166,  2, 64, 10, 10),GenMidi.Operator( 48, 97,151,  1,  0,  0,  0),   0),],"Synth Bass 2"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160, 96,  5,  0,128, 22,  6),GenMidi.Operator(177, 82, 22,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Soprano Sax"),
      GenMidi.Patch(0x02,128,  0,[GenMidi.Voice(GenMidi.Operator(160,112,  6,  1,128,  9,  6),GenMidi.Operator(176, 98, 22,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Alto Sax"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160,152, 11,  0, 64, 10, 10),GenMidi.Operator(176,115, 11,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Tenor Sax"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160,144, 11,  1,128,  5, 10),GenMidi.Operator(176, 99, 27,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Baritone Sax"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(112,112, 22,  0,128, 16,  6),GenMidi.Operator(162, 92,  8,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Oboe"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,200,  7,  0, 64, 15, 10),GenMidi.Operator( 49,115,  7,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"English Horn"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,144, 25,  0,128, 17, 10),GenMidi.Operator( 49, 97, 27,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Bassoon"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,165, 23,  0,128, 13,  8),GenMidi.Operator(176, 99, 23,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Clarinet"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240,110,143,  0,128,  0, 14),GenMidi.Operator(112, 53, 42,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Piccolo"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(160, 80,136,  0,128, 19,  8),GenMidi.Operator( 96, 85, 42,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Flute"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,101, 23,  0,  0, 10, 11),GenMidi.Operator(160,116, 39,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Recorder"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176, 36, 39,  1,128,  4,  9),GenMidi.Operator(176, 69, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0, 23,240,  2,  0,  0, 14),GenMidi.Operator(  0, 37,240,  0,  0,  0,  0),   0),],"Pan Flute"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(225, 87,  4,  0,128, 45, 14),GenMidi.Operator( 96, 87, 55,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Bottle Blow"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(241, 87, 52,  3,  0, 40, 14),GenMidi.Operator(225,103, 93,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Shakuhachi"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(208, 49, 15,  0,192,  7, 11),GenMidi.Operator(112, 50,  5,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Whistle"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(176, 81,  5,  0,192,  7, 11),GenMidi.Operator( 48, 66, 41,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Ocarina"),
      GenMidi.Patch(0x04,130,  0,[GenMidi.Voice(GenMidi.Operator( 34, 81, 91,  1, 64, 18,  0),GenMidi.Operator( 48, 96, 37,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 34,145, 91,  1, 64, 13,  0),GenMidi.Operator( 48,240, 37,  1,  0,  0,  0),   0),],"Lead 1 (square)"),
      GenMidi.Patch(0x04,127,  0,[GenMidi.Voice(GenMidi.Operator( 32,193,155,  1, 64,  3,  8),GenMidi.Operator( 49,192,101,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 96,177,171,  1, 64,  1,  8),GenMidi.Operator( 49,241,  5,  0,  0,  0,  0),   0),],"Lead 2 (sawtooth)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240, 87, 51,  3,  0, 40, 14),GenMidi.Operator(224,103,  7,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Lead 3 (calliope)"),
      GenMidi.Patch(0x04,130,  0,[GenMidi.Voice(GenMidi.Operator(224, 87,  4,  3,  0, 35, 14),GenMidi.Operator(224,103, 77,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(224,247,  4,  3,  0, 35, 14),GenMidi.Operator(224,135, 77,  0,  0,  0,  0),   0),],"Lead 4 (chiffer)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(161,120, 11,  1, 64,  2,  8),GenMidi.Operator( 48,241, 43,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Lead 5 (charang)"),
      GenMidi.Patch(0x04,122,  0,[GenMidi.Voice(GenMidi.Operator( 96,128, 85,  0,  0, 33,  8),GenMidi.Operator(224,242, 20,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 32,144, 85,  0,  0, 33,  8),GenMidi.Operator(160,162, 20,  0,  0,  0,  0),   0),],"Lead 6 (voice)"),
      GenMidi.Patch(0x04,125,  0,[GenMidi.Voice(GenMidi.Operator( 32,193,149,  1, 64,  3, 10),GenMidi.Operator(176,112, 99,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(160,145,149,  1, 64,  9, 10),GenMidi.Operator( 49, 97, 99,  1,  0,  0,  0),  -5),],"Lead 7 (5th sawtooth)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 36, 81,  7,  1, 64,  0,  9),GenMidi.Operator(160,253, 41,  2,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Lead 8 (bass & lead)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 36, 81,  7,  1, 64,  0,  9),GenMidi.Operator(160,253, 41,  2,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* Lead 8 (bass & lead)"),
      GenMidi.Patch(0x04,130,  0,[GenMidi.Voice(GenMidi.Operator(128, 50,  5,  0,192,  0,  9),GenMidi.Operator( 96, 51,  5,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator( 64, 50,  5,  0, 64,  0,  9),GenMidi.Operator(224, 51,  5,  0,  0,  0,  0),   0),],"Pad 2 (warm)"),
      GenMidi.Patch(0x04,130,  0,[GenMidi.Voice(GenMidi.Operator(160,161,165,  2,128, 15, 12),GenMidi.Operator(160,161,150,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(160,161,165,  2,128, 15, 12),GenMidi.Operator(160,161,150,  1,  0,  0,  0),   0),],"Pad 3 (polysynth)"),
      GenMidi.Patch(0x04,139,  0,[GenMidi.Voice(GenMidi.Operator(224,240,  5,  0, 64,  4,  1),GenMidi.Operator( 96,129, 84,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(224,240,  5,  1, 64,  4,  1),GenMidi.Operator( 96,113, 84,  0,128,  0,  0),   0),],"Pad 4 (choir)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(128,161, 51,  0,128, 10,  7),GenMidi.Operator(224, 82, 84,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Pad 5 (bowed glass)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(129,128, 82,  1,128, 29, 14),GenMidi.Operator( 64, 35, 83,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Pad 6 (metal)"),
      GenMidi.Patch(0x04,126,  0,[GenMidi.Voice(GenMidi.Operator(225, 81, 69,  1, 64, 13,  0),GenMidi.Operator(160,145, 70,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(161, 81, 69,  1, 64, 13,  0),GenMidi.Operator(160,129, 70,  1,  0,  0,  0),   0),],"Pad 7 (halo)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(225, 17, 82,  1,128, 12,  8),GenMidi.Operator(224,128,115,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Pad 8 (sweep)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,114, 71,  0, 64,  0, 11),GenMidi.Operator(131,248, 25,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"FX 1 (rain)"),
      GenMidi.Patch(0x04,136,  0,[GenMidi.Voice(GenMidi.Operator(  0,133,  2,  1,192, 18, 10),GenMidi.Operator(193, 69, 18,  1,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator( 34, 69,  3,  0,192, 18, 10),GenMidi.Operator(227, 53, 53,  2,  0,  0,  0),  -5),],"FX 2 (soundtrack)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  4,246,116,  0,192,  0,  0),GenMidi.Operator(  2,163, 36,  0,  0,  0,  0), -24),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* FX 3 (crystal)"),
      GenMidi.Patch(0x04,126,  0,[GenMidi.Voice(GenMidi.Operator(144,192,210,  0,128, 14,  0),GenMidi.Operator( 48,209,210,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(144,208,210,  0,128, 14,  0),GenMidi.Operator( 48,241,210,  0,  0,  0,  0),   0),],"FX 4 (atmosphere)"),
      GenMidi.Patch(0x04,116,  0,[GenMidi.Voice(GenMidi.Operator(208,144,243,  0,  0, 18,  0),GenMidi.Operator(192,194,243,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(208,144,243,  0,  0, 18,  0),GenMidi.Operator(192,194,242,  0,128,  0,  0),   0),],"FX 5 (brightness)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(224, 19, 82,  1,  0, 26,  0),GenMidi.Operator(241, 51, 19,  2,128,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"FX 6 (goblin)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(224, 69,186,  0,  0, 26,  0),GenMidi.Operator(240, 50,145,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"FX 7 (echo drops)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 16, 88,  2,  1,  0, 24, 10),GenMidi.Operator(  2, 66,114,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"* FX 8 (star-theme)"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32, 99,179,  0,  0,  8,  2),GenMidi.Operator( 36, 99,179,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Sitar"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,119, 18,  0,  0, 13,  4),GenMidi.Operator( 16,243,244,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,249,250,  2,  0, 10, 15),GenMidi.Operator(  0,249,250,  3, 64,  0,  0),   0),],"Banjo"),
      GenMidi.Patch(0x04,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,249, 51,  0,128,  0,  0),GenMidi.Operator(  0,244,115,  2,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  7,249,172,  2,  0, 26,  0),GenMidi.Operator( 15,249, 41,  2,  0,  0,  0),   0),],"Shamisen"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,242, 83,  1,  0, 33,  8),GenMidi.Operator( 34,145,228,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Koto"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  3,241, 57,  3, 64, 15,  6),GenMidi.Operator( 21,214,116,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Kalimba"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,137, 21,  1, 64,  2, 10),GenMidi.Operator( 33,107,  7,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Bag Pipe"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48,161,  3,  0,  0, 31, 14),GenMidi.Operator( 33, 82, 38,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Fiddle"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 48, 64, 19,  0,  0, 19,  8),GenMidi.Operator( 48, 97, 22,  1,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Shanai"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 19,161, 50,  0,  0,  0,  1),GenMidi.Operator( 18,178,114,  1,128,  0,  0),  -7),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Tinkle Bell"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(149,231,  1,  0,128,  1,  4),GenMidi.Operator( 22,150,103,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Agogo"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  3,240,  4,  1, 64,  9,  6),GenMidi.Operator( 32,130,  5,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Steel Drums"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 19,248,209,  0, 64,  4,  6),GenMidi.Operator( 18,245,120,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Woodblock"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 16,167,236,  0,  0, 11,  0),GenMidi.Operator( 16,213,245,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Taiko Drum"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 32,168,200,  0,  0, 11,  0),GenMidi.Operator(  1,214,183,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Melodic Tom"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0,248,196,  0,  0, 11,  0),GenMidi.Operator(  0,211,183,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Synth Drum"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 12, 65, 49,  0,128, 15, 14),GenMidi.Operator( 16, 33, 29,  3,128,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Reverse Cymbal"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 50, 52,179,  1,  0, 33, 14),GenMidi.Operator( 49, 84,247,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Guitar Fret Noise"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(209, 55,  4,  0,128, 45, 14),GenMidi.Operator( 80, 55, 52,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Breath Noise"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  2, 62,  1,  2,  0,  0, 14),GenMidi.Operator(  8, 20,243,  2,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Seashore"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(245,235,  3,  0,192, 20,  7),GenMidi.Operator(246, 69,104,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Bird Tweet"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(240,218,113,  1,  0,  0,  8),GenMidi.Operator(202,176, 23,  1,192,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Telephone Ring"),
      GenMidi.Patch(0x01,128, 17,[GenMidi.Voice(GenMidi.Operator(240, 30, 17,  1,  0,  0,  8),GenMidi.Operator(226, 33, 17,  1,192,  0,  0), -24),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Helicopter"),
      GenMidi.Patch(0x01,128, 65,[GenMidi.Voice(GenMidi.Operator(239, 83,  0,  2,128,  6, 14),GenMidi.Operator(239, 16,  2,  3,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Applause"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator( 12,240,240,  2,  0,  0, 14),GenMidi.Operator(  4,246,230,  0,  0,  0,  0), -12),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Gun Shot"),
      GenMidi.Patch(0x01,128, 38,[GenMidi.Voice(GenMidi.Operator(  0,249, 87,  2,  0,  0,  0),GenMidi.Operator(  0,251, 70,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Bass Drum"),
      GenMidi.Patch(0x01,128, 25,[GenMidi.Voice(GenMidi.Operator(  0,250, 71,  0,  0,  0,  6),GenMidi.Operator(  0,249,  6,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Bass Drum"),
      GenMidi.Patch(0x01,128, 83,[GenMidi.Voice(GenMidi.Operator(  2,253,103,  0,128,  0,  6),GenMidi.Operator(  3,247,120,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Slide Stick"),
      GenMidi.Patch(0x01,128, 32,[GenMidi.Voice(GenMidi.Operator( 15,247, 20,  2,  0,  5, 14),GenMidi.Operator(  0,249, 71,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Acoustic Snare"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(225,136,251,  3,  0,  0, 15),GenMidi.Operator(255,166,168,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Hand Clap"),
      GenMidi.Patch(0x05,128, 36,[GenMidi.Voice(GenMidi.Operator(  6,170,255,  0,  0,  0, 14),GenMidi.Operator(  0,247,250,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0, 63,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),  42),],"Electric Snare"),
      GenMidi.Patch(0x01,128, 15,[GenMidi.Voice(GenMidi.Operator(  2,245,108,  0,  0,  0,  7),GenMidi.Operator(  3,247, 56,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Floor Tom"),
      GenMidi.Patch(0x01,128, 88,[GenMidi.Voice(GenMidi.Operator( 12,152, 94,  2,  0,  0, 15),GenMidi.Operator( 15,251,  6,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Closed High-Hat"),
      GenMidi.Patch(0x01,128, 19,[GenMidi.Voice(GenMidi.Operator(  2,245,120,  0,  0,  0,  7),GenMidi.Operator(  0,247, 55,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Floor Tom"),
      GenMidi.Patch(0x01,128, 88,[GenMidi.Voice(GenMidi.Operator( 12,120, 94,  2,  0,  0, 15),GenMidi.Operator( 10,138, 43,  3,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Pedal High Hat"),
      GenMidi.Patch(0x01,128, 21,[GenMidi.Voice(GenMidi.Operator(  2,245, 55,  0,  0,  0,  3),GenMidi.Operator(  2,247, 55,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Tom"),
      GenMidi.Patch(0x01,128, 79,[GenMidi.Voice(GenMidi.Operator(  0,199,  1,  2, 64,  5, 14),GenMidi.Operator( 11,249, 51,  2,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Open High Hat"),
      GenMidi.Patch(0x01,128, 26,[GenMidi.Voice(GenMidi.Operator(  2,245, 55,  0,  0,  0,  3),GenMidi.Operator(  2,247, 55,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low-Mid Tom"),
      GenMidi.Patch(0x01,128, 28,[GenMidi.Voice(GenMidi.Operator(  2,245, 55,  0,  0,  0,  3),GenMidi.Operator(  2,247, 55,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High-Mid Tom"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  4,194,230,  0,  0, 16, 14),GenMidi.Operator(  0,232, 67,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Crash Cymbal 1"),
      GenMidi.Patch(0x01,128, 32,[GenMidi.Voice(GenMidi.Operator(  2,245, 55,  0,  0,  0,  3),GenMidi.Operator(  2,247, 55,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Tom"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  3,253, 18,  2,128,  0, 10),GenMidi.Operator(  2,253,  5,  2,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Ride Cymbal 1"),
      GenMidi.Patch(0x01,128, 96,[GenMidi.Voice(GenMidi.Operator(  0,228,133,  0,128,  0, 14),GenMidi.Operator(192,215, 52,  2,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Chinses Cymbal"),
      GenMidi.Patch(0x01,128, 72,[GenMidi.Voice(GenMidi.Operator(  4,226,230,  0,128, 16, 14),GenMidi.Operator(  1,184, 68,  1,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Ride Bell"),
      GenMidi.Patch(0x01,128, 79,[GenMidi.Voice(GenMidi.Operator(  2,118,119,  2,128,  7, 15),GenMidi.Operator(  1,152,103,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Tambourine"),
      GenMidi.Patch(0x01,128, 69,[GenMidi.Voice(GenMidi.Operator(  4,246,112,  2,128,  1, 14),GenMidi.Operator(  7,198,163,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Splash Cymbal"),
      GenMidi.Patch(0x01,128, 71,[GenMidi.Voice(GenMidi.Operator(  0,253,103,  0,  0,  0,  6),GenMidi.Operator(  1,246,152,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Cowbell"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  4,194,230,  0,  0, 16, 14),GenMidi.Operator(  0,232, 67,  3,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Crash Cymbal 2"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  1,249,181,  0,  0,  7, 11),GenMidi.Operator(191,212, 80,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Vibraslap"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  3,253, 18,  2,128,  0, 10),GenMidi.Operator(  2,253,  5,  2,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Ride Cymbal 2"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  0,251, 86,  2,  0,  0,  4),GenMidi.Operator(  0,250, 38,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Bongo"),
      GenMidi.Patch(0x01,128, 54,[GenMidi.Voice(GenMidi.Operator(  0,251, 86,  2,  0,  0,  4),GenMidi.Operator(  0,250, 38,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Bango"),
      GenMidi.Patch(0x01,128, 72,[GenMidi.Voice(GenMidi.Operator(  0,251, 86,  2,128,  0,  0),GenMidi.Operator(  0,247, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Mute High Conga"),
      GenMidi.Patch(0x01,128, 67,[GenMidi.Voice(GenMidi.Operator(  0,251, 86,  2,128,  0,  0),GenMidi.Operator(  0,247, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Open High Conga"),
      GenMidi.Patch(0x01,128, 60,[GenMidi.Voice(GenMidi.Operator(  0,251, 86,  2,128,  0,  0),GenMidi.Operator(  0,247, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Conga"),
      GenMidi.Patch(0x01,128, 55,[GenMidi.Voice(GenMidi.Operator(  3,251, 86,  0,128,  1,  0),GenMidi.Operator(  0,247, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Timbale"),
      GenMidi.Patch(0x01,128, 48,[GenMidi.Voice(GenMidi.Operator(  3,251, 86,  0,128,  1,  0),GenMidi.Operator(  0,247, 23,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Timbale"),
      GenMidi.Patch(0x01,128, 77,[GenMidi.Voice(GenMidi.Operator(  1,253,103,  3,  0,  0,  8),GenMidi.Operator(  1,246,152,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Agogo"),
      GenMidi.Patch(0x01,128, 72,[GenMidi.Voice(GenMidi.Operator(  1,253,103,  3,  0,  0,  8),GenMidi.Operator(  1,246,152,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Agogo"),
      GenMidi.Patch(0x01,128, 88,[GenMidi.Voice(GenMidi.Operator( 12,120, 94,  2,  0,  0, 15),GenMidi.Operator( 10,138, 43,  3,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Cabasa"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  0, 90,214,  2,  0, 14, 10),GenMidi.Operator(191,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Maracas"),
      GenMidi.Patch(0x01,128, 49,[GenMidi.Voice(GenMidi.Operator(  0,249,199,  1,  0,  7, 10),GenMidi.Operator(128,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Short Whistle"),
      GenMidi.Patch(0x01,128, 49,[GenMidi.Voice(GenMidi.Operator(  0,249,199,  1,  0,  7, 10),GenMidi.Operator(128,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Long Whistle"),
      GenMidi.Patch(0x01,128, 49,[GenMidi.Voice(GenMidi.Operator(  0,249,199,  1,  0,  7, 10),GenMidi.Operator(128,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Short Guiro"),
      GenMidi.Patch(0x01,128, 49,[GenMidi.Voice(GenMidi.Operator(  0,249,199,  1,  0,  7, 10),GenMidi.Operator(128,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Long Guiro"),
      GenMidi.Patch(0x01,128, 73,[GenMidi.Voice(GenMidi.Operator( 19,248,209,  1, 64,  4,  6),GenMidi.Operator( 18,245,120,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Claves"),
      GenMidi.Patch(0x01,128, 68,[GenMidi.Voice(GenMidi.Operator( 19,248,209,  1, 64,  4,  6),GenMidi.Operator( 18,245,120,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"High Wood Block"),
      GenMidi.Patch(0x01,128, 61,[GenMidi.Voice(GenMidi.Operator( 19,248,209,  1, 64,  4,  6),GenMidi.Operator( 18,245,120,  0,  0,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Low Wood Block"),
      GenMidi.Patch(0x00,128,  0,[GenMidi.Voice(GenMidi.Operator(  1, 94,220,  1,  0, 11, 10),GenMidi.Operator(191,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Mute Cuica"),
      GenMidi.Patch(0x01,128, 49,[GenMidi.Voice(GenMidi.Operator(  0,249,199,  1,  0,  7, 10),GenMidi.Operator(128,255,255,  0,192,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Open Cuica"),
      GenMidi.Patch(0x01,128, 90,[GenMidi.Voice(GenMidi.Operator(197,242, 96,  0, 64, 15,  8),GenMidi.Operator(212,244,122,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Mute Triangle"),
      GenMidi.Patch(0x01,128, 90,[GenMidi.Voice(GenMidi.Operator(133,242, 96,  1, 64, 15,  8),GenMidi.Operator(148,242,183,  0,128,  0,  0),   0),GenMidi.Voice(GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),GenMidi.Operator(  0,  0,240,  0,  0,  0,  0),   0),],"Open Triangle"),
    ]);
  }

private:
  static struct SynthMidiChannel {
    ubyte volume;
    ushort volume_t;
    ubyte pan;
    ubyte reg_pan;
    ubyte pitch;
    const(GenMidi.Patch)* patch;
    bool drum;
  }

  static struct SynthVoice {
    ubyte bank;

    ubyte op_base;
    ubyte ch_base;

    uint freq;

    ubyte[2] tl;
    ubyte additive;

    bool voice_dual;
    const(GenMidi.Voice)* voice_data;
    const(GenMidi.Patch)* patch;

    SynthMidiChannel* chan;

    ubyte velocity;
    ubyte key;
    ubyte note;

    int finetune;

    ubyte pan;
  }

  static align(1) struct MidiHeader {
  align(1):
    char[4] header;
    uint length;
    ushort format;
    ushort count;
    ushort time;
    ubyte[0] data;
  }

  static align(1) struct MidiTrack {
  align(1):
    char[4] header;
    uint length;
    ubyte[0] data;
  }

  static struct Track {
    const(ubyte)* data;
    const(ubyte)* pointer;
    uint length;
    uint time;
    ubyte lastevent;
    bool finish;
    uint num;
  }

  static align(1) struct MusHeader {
  align(1):
    char[4] header;
    ushort length;
    ushort offset;
  }

private:
  // config
  uint mSampleRate;
  bool mOPL2Mode;
  bool mStereo;

  // genmidi lump
  version(genmidi_dumper) {
    GenMidi mGenMidi;
    bool mGenMidiLoaded;
  }

  // OPL3 emulator
  OPL3Chip chip;

  SynthMidiChannel[16] mSynthMidiChannels;
  SynthVoice[18] mSynthVoices;
  uint mSynthVoiceNum;
  SynthVoice*[18] mSynthVoicesAllocated;
  uint mSynthVoicesAllocatedNum;
  SynthVoice*[18] mSynthVoicesFree;
  uint mSynthVoicesFreeNum;

  Track[] mMidiTracks;
  uint mMidiCount;
  uint mMidiTimebase;
  uint mMidiCallrate;
  uint mMidiTimer;
  uint mMidiTimechange;
  uint mMidiRate;
  uint mMidiFinished;
  ubyte[16] mMidiChannels;
  ubyte mMidiChannelcnt;

  const(ubyte)* mMusData;
  const(ubyte)* mMusPointer;
  ushort mMusLength;
  uint mMusTimer;
  uint mMusTimeend;
  ubyte[16] mMusChanVelo;

  uint mSongTempo;
  bool mPlayerActive;
  bool mPlayLooped;

  enum DataFormat {
    Unknown,
    Midi,
    Mus,
  }
  DataFormat mDataFormat = DataFormat.Unknown;

  uint mOPLCounter;

  ubyte[] songdata;

private:
  static ushort MISC_Read16LE (ushort n) pure nothrow @trusted @nogc {
    const(ubyte)* m = cast(const(ubyte)*)&n;
    return cast(ushort)(m[0]|(m[1]<<8));
  }

  static ushort MISC_Read16BE (ushort n) pure nothrow @trusted @nogc {
    const(ubyte)* m = cast(const(ubyte)*)&n;
    return cast(ushort)(m[1]|(m[0]<<8));
  }

  static uint MISC_Read32LE (uint n) pure nothrow @trusted @nogc {
    const(ubyte)* m = cast(const(ubyte)*)&n;
    return m[0]|(m[1]<<8)|(m[2]<<16)|(m[3]<<24);
  }

  static uint MISC_Read32BE (uint n) pure nothrow @trusted @nogc {
    const(ubyte)* m = cast(const(ubyte)*)&n;
    return m[3]|(m[2]<<8)|(m[1]<<16)|(m[0]<<24);
  }

  // ////////////////////////////////////////////////////////////////////// //
  // synth
  enum SynthCmd : ubyte {
    NoteOff,
    NoteOn,
    PitchBend,
    Patch,
    Control,
  }

  enum SynthCtl : ubyte {
    Bank,
    Modulation,
    Volume,
    Pan,
    Expression,
    Reverb,
    Chorus,
    Sustain,
    Soft,
    AllNoteOff,
    MonoMode,
    PolyMode,
    Reset,
  }

  void SynthResetVoice (ref SynthVoice voice) nothrow @trusted @nogc {
    voice.freq = 0;
    voice.voice_dual = false;
    voice.voice_data = null;
    voice.patch = null;
    voice.chan = null;
    voice.velocity = 0;
    voice.key = 0;
    voice.note = 0;
    voice.pan = 0x30;
    voice.finetune = 0;
    voice.tl.ptr[0] = 0x3f;
    voice.tl.ptr[1] = 0x3f;
  }

  void SynthResetChip (ref OPL3Chip chip) nothrow @safe @nogc {
    for (ushort i = 0x40; i < 0x56; ++i) chip.writeReg(i, 0x3f);
    for (ushort i = 0x60; i < 0xf6; ++i) chip.writeReg(i, 0x00);
    for (ushort i = 0x01; i < 0x40; ++i) chip.writeReg(i, 0x00);

    chip.writeReg(0x01, 0x20);

    if (!mOPL2Mode) {
      chip.writeReg(0x105, 0x01);
      for (ushort i = 0x140; i < 0x156; ++i) chip.writeReg(i, 0x3f);
      for (ushort i = 0x160; i < 0x1f6; ++i) chip.writeReg(i, 0x00);
      for (ushort i = 0x101; i < 0x140; ++i) chip.writeReg(i, 0x00);
      chip.writeReg(0x105, 0x01);
    } else {
      chip.writeReg(0x105, 0x00);
    }
  }

  void SynthResetMidi (ref SynthMidiChannel channel) nothrow @trusted @nogc {
    channel.volume = 100;
    channel.volume_t = opl_voltable.ptr[channel.volume]+1;
    channel.pan = 64;
    channel.reg_pan = 0x30;
    channel.pitch = 64;
    channel.patch = &mGenMidi.patch.ptr[0];
    channel.drum = false;
    if (&channel is &mSynthMidiChannels.ptr[15]) channel.drum = true;
  }

  void SynthInit () nothrow @trusted @nogc {
    static immutable ubyte[9] opl_slotoffset = [0x00, 0x01, 0x02, 0x08, 0x09, 0x0a, 0x10, 0x11, 0x12];

    for (uint i = 0; i < 18; ++i) {
      mSynthVoices.ptr[i].bank = cast(ubyte)(i/9);
      mSynthVoices.ptr[i].op_base = opl_slotoffset.ptr[i%9];
      mSynthVoices.ptr[i].ch_base = i%9;
      SynthResetVoice(mSynthVoices.ptr[i]);
    }

    for (uint i = 0; i < 16; ++i) SynthResetMidi(mSynthMidiChannels.ptr[i]);

    SynthResetChip(chip);

    mSynthVoiceNum = (mOPL2Mode ? 9 : 18);

    for (ubyte i = 0; i < mSynthVoiceNum; i++) mSynthVoicesFree.ptr[i] = &mSynthVoices.ptr[i];

    mSynthVoicesAllocatedNum = 0;
    mSynthVoicesFreeNum = mSynthVoiceNum;
  }

  void SynthWriteReg (uint bank, ushort reg, ubyte data) nothrow @trusted @nogc {
    reg |= bank<<8;
    chip.writeReg(reg, data);
  }

  void SynthVoiceOff (SynthVoice* voice) nothrow @trusted @nogc {
    SynthWriteReg(voice.bank, cast(ushort)(0xb0+voice.ch_base), cast(ubyte)(voice.freq>>8));
    voice.freq = 0;
    for (uint i = 0; i < mSynthVoicesAllocatedNum; ++i) {
      if (mSynthVoicesAllocated.ptr[i] is voice) {
        for (uint j = i; j < mSynthVoicesAllocatedNum-1; ++j) {
          mSynthVoicesAllocated.ptr[j] = mSynthVoicesAllocated.ptr[j+1];
        }
        break;
      }
    }
    --mSynthVoicesAllocatedNum;
    mSynthVoicesFree.ptr[mSynthVoicesFreeNum++] = voice;
  }

  void SynthVoiceFreq (SynthVoice* voice) nothrow @trusted @nogc {
    int freq = voice.chan.pitch+voice.finetune+32*voice.note;
    uint block = 0;

    if (freq < 0) {
      freq = 0;
    } else if (freq >= 284) {
      freq -= 284;
      block = freq/384;
      if (block > 7) block = 7;
      freq %= 384;
      freq += 284;
    }

    freq = (block<<10)|opl_freqtable.ptr[freq];

    SynthWriteReg(voice.bank, 0xa0+voice.ch_base, freq&0xff);
    SynthWriteReg(voice.bank, cast(ushort)(0xb0+voice.ch_base), cast(ubyte)((freq>>8)|0x20));

    voice.freq = freq;
  }

  void SynthVoiceVolume (SynthVoice* voice) nothrow @trusted @nogc {
    ubyte volume = cast(ubyte)(0x3f-(voice.chan.volume_t*opl_voltable.ptr[voice.velocity])/256);
    if ((voice.tl.ptr[0]&0x3f) != volume) {
      voice.tl.ptr[0] = (voice.tl.ptr[0]&0xc0)|volume;
      SynthWriteReg(voice.bank, 0x43+voice.op_base, voice.tl.ptr[0]);
      if (voice.additive) {
        ubyte volume2 = cast(ubyte)(0x3f-voice.additive);
        if (volume2 < volume) volume2 = volume;
        volume2 |= voice.tl.ptr[1]&0xc0;
        if (volume2 != voice.tl.ptr[1]) {
          voice.tl.ptr[1] = volume2;
          SynthWriteReg(voice.bank, 0x40+voice.op_base, voice.tl.ptr[1]);
        }
      }
    }
  }

  ubyte SynthOperatorSetup (uint bank, uint base, const(GenMidi.Operator)* op, bool volume) nothrow @trusted @nogc {
    ubyte tl = op.ksl;
    if (volume) tl |= 0x3f; else tl |= op.level;
    SynthWriteReg(bank, cast(ushort)(0x40+base), tl);
    SynthWriteReg(bank, cast(ushort)(0x20+base), op.mult);
    SynthWriteReg(bank, cast(ushort)(0x60+base), op.attack);
    SynthWriteReg(bank, cast(ushort)(0x80+base), op.sustain);
    SynthWriteReg(bank, cast(ushort)(0xE0+base), op.wave);
    return tl;
  }

  void SynthVoiceOn (SynthMidiChannel* channel, const(GenMidi.Patch)* patch, bool dual, ubyte key, ubyte velocity) nothrow @trusted @nogc {
    SynthVoice* voice;
    const(GenMidi.Voice)* voice_data;
    uint bank;
    uint base;
    int note;

    if (mSynthVoicesFreeNum == 0) return;

    voice = mSynthVoicesFree.ptr[0];

    --mSynthVoicesFreeNum;

    for (uint i = 0; i < mSynthVoicesFreeNum; ++i) mSynthVoicesFree.ptr[i] = mSynthVoicesFree.ptr[i+1];

    mSynthVoicesAllocated.ptr[mSynthVoicesAllocatedNum++] = voice;

    voice.chan = channel;
    voice.key = key;
    voice.velocity = velocity;
    voice.patch = patch;
    voice.voice_dual = dual;

    if (dual) {
      voice_data = &patch.voice.ptr[1];
      voice.finetune = cast(int)(patch.finetune>>1)-64;
    } else {
      voice_data = &patch.voice.ptr[0];
      voice.finetune = 0;
    }

    voice.pan = channel.reg_pan;

    if (voice.voice_data != voice_data) {
      voice.voice_data = voice_data;
      bank = voice.bank;
      base = voice.op_base;

      voice.tl.ptr[0] = SynthOperatorSetup(bank, base+3, &voice_data.car, true);

      if (voice_data.mod.feedback&1) {
        voice.additive = cast(ubyte)(0x3f-voice_data.mod.level);
        voice.tl.ptr[1] = SynthOperatorSetup(bank, base, &voice_data.mod, true);
      } else {
        voice.additive = 0;
        voice.tl.ptr[1] = SynthOperatorSetup(bank, base, &voice_data.mod, false);
      }
    }

    SynthWriteReg(voice.bank, 0xc0+voice.ch_base, voice_data.mod.feedback|voice.pan);

    if (MISC_Read16LE(patch.flags)&GenMidi.Patch.Flag.Fixed) {
      note = patch.note;
    } else {
      if (channel.drum) {
        note = 60;
      } else {
        note = key;
        note += cast(short)MISC_Read16LE(cast(ushort)voice_data.offset);
        while (note < 0) note += 12;
        while (note > 95) note -= 12;
      }
    }
    voice.note = cast(ubyte)note;

    SynthVoiceVolume(voice);
    SynthVoiceFreq(voice);
  }

  void SynthKillVoice () nothrow @trusted @nogc {
    SynthVoice* voice;
    if (mSynthVoicesFreeNum > 0) return;
    voice = mSynthVoicesAllocated.ptr[0];
    for (uint i = 0; i < mSynthVoicesAllocatedNum; i++) {
      if (mSynthVoicesAllocated.ptr[i].voice_dual || mSynthVoicesAllocated.ptr[i].chan >= voice.chan) {
        voice = mSynthVoicesAllocated.ptr[i];
      }
    }
    SynthVoiceOff(voice);
  }

  void SynthNoteOff (SynthMidiChannel* channel, ubyte note) nothrow @trusted @nogc {
    for (uint i = 0; i < mSynthVoicesAllocatedNum; ) {
      if (mSynthVoicesAllocated.ptr[i].chan is channel && mSynthVoicesAllocated.ptr[i].key == note) {
        SynthVoiceOff(mSynthVoicesAllocated.ptr[i]);
      } else {
        ++i;
      }
    }
  }

  void SynthNoteOn (SynthMidiChannel* channel, ubyte note, ubyte velo) nothrow @trusted @nogc {
    const(GenMidi.Patch)* patch;

    if (velo == 0) {
      SynthNoteOff(channel, note);
      return;
    }

    if (channel.drum) {
      if (note < 35 || note > 81) return;
      patch = &mGenMidi.patch.ptr[note-35+128];
    } else {
      patch = channel.patch;
    }

    SynthKillVoice();

    SynthVoiceOn(channel, patch, false, note, velo);

    if (mSynthVoicesFreeNum > 0 && MISC_Read16LE(patch.flags)&GenMidi.Patch.Flag.DualVoice) {
      SynthVoiceOn(channel, patch, true, note, velo);
    }
  }

  void SynthPitchBend (SynthMidiChannel* channel, ubyte pitch) nothrow @trusted @nogc {
    SynthVoice*[18] mSynthChannelVoices;
    SynthVoice*[18] mSynthOtherVoices;

    uint cnt1 = 0;
    uint cnt2 = 0;

    channel.pitch = pitch;

    for (uint i = 0; i < mSynthVoicesAllocatedNum; ++i) {
      if (mSynthVoicesAllocated.ptr[i].chan is channel) {
        SynthVoiceFreq(mSynthVoicesAllocated.ptr[i]);
        mSynthChannelVoices.ptr[cnt1++] = mSynthVoicesAllocated.ptr[i];
      } else {
        mSynthOtherVoices.ptr[cnt2++] = mSynthVoicesAllocated.ptr[i];
      }
    }

    for (uint i = 0; i < cnt2; ++i) mSynthVoicesAllocated.ptr[i] = mSynthOtherVoices.ptr[i];
    for (uint i = 0; i < cnt1; ++i) mSynthVoicesAllocated.ptr[i+cnt2] = mSynthChannelVoices.ptr[i];
  }

  void SynthUpdatePatch (SynthMidiChannel* channel, ubyte patch) nothrow @trusted @nogc {
    if (patch >= mGenMidi.patch.length) patch = 0;
    channel.patch = &mGenMidi.patch.ptr[patch];
  }

  void SynthUpdatePan (SynthMidiChannel* channel, ubyte pan) nothrow @trusted @nogc {
    ubyte new_pan = 0x30;
    if (pan <= 48) new_pan = 0x20; else if (pan >= 96) new_pan = 0x10;
    channel.pan = pan;
    if (channel.reg_pan != new_pan) {
      channel.reg_pan = new_pan;
      for (uint i = 0; i < mSynthVoicesAllocatedNum; ++i) {
        if (mSynthVoicesAllocated.ptr[i].chan is channel) {
          mSynthVoicesAllocated.ptr[i].pan = new_pan;
          SynthWriteReg(mSynthVoicesAllocated.ptr[i].bank,
              0xc0+mSynthVoicesAllocated.ptr[i].ch_base,
              mSynthVoicesAllocated.ptr[i].voice_data.mod.feedback|new_pan);
        }
      }
    }
  }

  void SynthUpdateVolume (SynthMidiChannel* channel, ubyte volume) nothrow @trusted @nogc {
    if (volume&0x80) volume = 0x7f;
    if (channel.volume != volume) {
      channel.volume = volume;
      channel.volume_t = opl_voltable.ptr[channel.volume]+1;
      for (uint i = 0; i < mSynthVoicesAllocatedNum; ++i) {
        if (mSynthVoicesAllocated.ptr[i].chan is channel) {
          SynthVoiceVolume(mSynthVoicesAllocated.ptr[i]);
        }
      }
    }
  }

  void SynthNoteOffAll (SynthMidiChannel* channel) nothrow @trusted @nogc {
    for (uint i = 0; i < mSynthVoicesAllocatedNum; ) {
      if (mSynthVoicesAllocated.ptr[i].chan is channel) {
        SynthVoiceOff(mSynthVoicesAllocated.ptr[i]);
      } else {
        ++i;
      }
    }
  }

  void SynthEventReset (SynthMidiChannel* channel) nothrow @trusted @nogc {
    SynthNoteOffAll(channel);
    channel.reg_pan = 0x30;
    channel.pan = 64;
    channel.pitch = 64;
  }

  void SynthReset () nothrow @trusted @nogc {
    for (ubyte i = 0; i < 16; ++i) {
      SynthNoteOffAll(&mSynthMidiChannels.ptr[i]);
      SynthResetMidi(mSynthMidiChannels.ptr[i]);
    }
  }

  void SynthWrite (ubyte command, ubyte data1, ubyte data2) nothrow @trusted @nogc {
    SynthMidiChannel* channel = &mSynthMidiChannels.ptr[command&0x0f];
    command >>= 4;
    switch (command) {
      case SynthCmd.NoteOff: SynthNoteOff(channel, data1); break;
      case SynthCmd.NoteOn: SynthNoteOn(channel, data1, data2); break;
      case SynthCmd.PitchBend: SynthPitchBend(channel, data2); break;
      case SynthCmd.Patch: SynthUpdatePatch(channel, data1); break;
      case SynthCmd.Control:
        switch (data1) {
          case SynthCtl.Volume: SynthUpdateVolume(channel, data2); break;
          case SynthCtl.Pan: SynthUpdatePan(channel, data2); break;
          case SynthCtl.AllNoteOff: SynthNoteOffAll(channel); break;
          case SynthCtl.Reset: SynthEventReset(channel); break;
          default: break;
        }
        break;
      default: break;
    }
  }

  // ////////////////////////////////////////////////////////////////////// //
  // MIDI
  uint MIDI_ReadDelay (const(ubyte)** data) nothrow @trusted @nogc {
    const(ubyte)* dn = *data;
    uint delay = 0;
    do {
      delay = (delay<<7)|((*dn)&0x7f);
    } while (*dn++&0x80);
    *data = dn;
    return delay;
  }

  bool MIDI_LoadSong () nothrow @trusted {
    enum midh = "MThd";
    enum mtrkh = "MTrk";

    import core.stdc.string : memcmp;

    if (songdata.length <= MidiHeader.sizeof) return false;

    if (memcmp(songdata.ptr, "RIFF".ptr, 4) == 0)
    	songdata = songdata[0x14 .. $];

    const(MidiHeader)* mid = cast(const(MidiHeader)*)songdata.ptr;

    if (memcmp(mid.header.ptr, midh.ptr, 4) != 0 || MISC_Read32BE(mid.length) != 6) return false;

    mMidiCount = MISC_Read16BE(mid.count);
    const(ubyte)[] midi_data = mid.data.ptr[0..songdata.length-MidiHeader.sizeof];
    mMidiTimebase = MISC_Read16BE(mid.time);

    // if (mMidiTracks !is null) delete mMidiTracks;

    mMidiTracks = new Track[](mMidiCount);

    uint trknum = 0;
    while (trknum < mMidiCount) {
      if (midi_data.length < 8) { /*delete mMidiTracks;*/ return false; } // out of data
      const(MidiTrack)* track = cast(const(MidiTrack)*)midi_data.ptr;
      uint datasize = MISC_Read32BE(track.length);
      if (midi_data.length-8 < datasize) { /*delete mMidiTracks;*/ return false; } // out of data
      if (memcmp(track.header.ptr, mtrkh.ptr, 4) != 0) {
        // not a track, skip this chunk
        midi_data = midi_data[datasize+8..$];
      } else {
        // track
        mMidiTracks[trknum].length = datasize;
        mMidiTracks[trknum].data = track.data.ptr;
        mMidiTracks[trknum].num = trknum++;
        // move to next chunk
        midi_data = midi_data[datasize+8..$];
      }
    }
    // check if we have all tracks
    if (trknum != mMidiCount) { /*delete mMidiTracks;*/ return false; } // out of tracks

    mDataFormat = DataFormat.Midi;

    return true;
  }

  bool MIDI_StartSong () nothrow @trusted @nogc {
    if (mDataFormat != DataFormat.Midi || mPlayerActive) return false;

    for (uint i = 0; i < mMidiCount; ++i) {
      mMidiTracks[i].pointer = mMidiTracks[i].data;
      mMidiTracks[i].time = MIDI_ReadDelay(&mMidiTracks[i].pointer);
      mMidiTracks[i].lastevent = 0x80;
      mMidiTracks[i].finish = 0;
    }

    for (uint i = 0; i < 16; ++i) mMidiChannels.ptr[i] = 0xff;

    mMidiChannelcnt = 0;

    mMidiRate = 1000000/(500000/mMidiTimebase);
    mMidiCallrate = mSongTempo;
    mMidiTimer = 0;
    mMidiTimechange = 0;
    mMidiFinished = 0;

    mPlayerActive = true;

    return true;
  }

  void MIDI_StopSong () nothrow @trusted @nogc {
    if (mDataFormat != DataFormat.Midi || !mPlayerActive) return;
    mPlayerActive = false;
    for (uint i = 0; i < 16; ++i) {
      SynthWrite(cast(ubyte)((SynthCmd.Control<<4)|i), SynthCtl.AllNoteOff, 0);
    }
    SynthReset();
  }

  Track* MIDI_NextTrack () nothrow @trusted @nogc {
    Track* mintrack = &mMidiTracks[0];
    for (uint i = 1; i < mMidiCount; i++) {
      if ((mMidiTracks[i].time < mintrack.time && !mMidiTracks[i].finish) || mintrack.finish) {
        mintrack = &mMidiTracks[i];
      }
    }
    return mintrack;
  }

  ubyte MIDI_GetChannel (ubyte chan) nothrow @trusted @nogc {
    if (chan == 9) return 15;
    if (mMidiChannels.ptr[chan] == 0xff) mMidiChannels.ptr[chan] = mMidiChannelcnt++;
    return mMidiChannels.ptr[chan];
  }

  void MIDI_Command (const(ubyte)** datap, ubyte evnt) nothrow @trusted @nogc {
    ubyte chan;
    const(ubyte)* data;
    ubyte v1, v2;

    data = *datap;
    chan = MIDI_GetChannel(evnt&0x0f);
    switch (evnt&0xf0) {
      case 0x80:
        v1 = *data++;
        v2 = *data++;
        SynthWrite((SynthCmd.NoteOff<<4)|chan, v1, 0);
        break;
      case 0x90:
        v1 = *data++;
        v2 = *data++;
        SynthWrite((SynthCmd.NoteOn<<4)|chan, v1, v2);
        break;
      case 0xa0:
        data += 2;
        break;
      case 0xb0:
        v1 = *data++;
        v2 = *data++;
        switch (v1) {
          case 0x00: case 0x20: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Bank, v2); break;
          case 0x01: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Modulation, v2); break;
          case 0x07: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Volume, v2); break;
          case 0x0a: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Pan, v2); break;
          case 0x0b: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Expression, v2); break;
          case 0x40: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Sustain, v2); break;
          case 0x43: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Soft, v2); break;
          case 0x5b: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Reverb, v2); break;
          case 0x5d: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Chorus, v2); break;
          case 0x78: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.AllNoteOff, v2); break;
          case 0x79: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Reset, v2); break;
          case 0x7b: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.AllNoteOff, v2); break;
          case 0x7e: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.MonoMode, v2); break;
          case 0x7f: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.PolyMode, v2); break;
          default: break;
        }
        break;
      case 0xc0:
        v1 = *data++;
        SynthWrite((SynthCmd.Patch<<4)|chan, v1, 0);
        break;
      case 0xd0:
        data += 1;
        break;
      case 0xe0:
        v1 = *data++;
        v2 = *data++;
        SynthWrite((SynthCmd.PitchBend<<4)|chan, v1, v2);
        break;
      default: break;
    }
    *datap = data;
  }

  void MIDI_FinishTrack (Track* trck) nothrow @trusted @nogc {
    if (trck.finish) return;
    trck.finish = true;
    ++mMidiFinished;
  }

  void MIDI_AdvanceTrack (Track* trck) nothrow @trusted @nogc {
    ubyte evnt;
    ubyte meta;
    ubyte length;
    uint tempo;
    const(ubyte)* data;

    evnt = *trck.pointer++;

    if (!(evnt&0x80)) {
      evnt = trck.lastevent;
      --trck.pointer;
    }

    switch (evnt) {
      case 0xf0:
      case 0xf7:
        length = cast(ubyte)MIDI_ReadDelay(&trck.pointer);
        trck.pointer += length;
        break;
      case 0xff:
        meta = *trck.pointer++;
        length = cast(ubyte)MIDI_ReadDelay(&trck.pointer);
        data = trck.pointer;
        trck.pointer += length;
        switch (meta) {
          case 0x2f:
            MIDI_FinishTrack(trck);
            break;
          case 0x51:
            if (length == 0x03) {
              tempo = (data[0]<<16)|(data[1]<<8)|data[2];
              mMidiTimechange += (mMidiTimer*mMidiRate)/mMidiCallrate;
              mMidiTimer = 0;
              mMidiRate = 1000000/(tempo/mMidiTimebase);
            }
            break;
          default: break;
        }
        break;
      default:
        MIDI_Command(&trck.pointer,evnt);
        break;
    }

    trck.lastevent = evnt;
    if (trck.pointer >= trck.data+trck.length) MIDI_FinishTrack(trck);
  }

  void MIDI_Callback () nothrow @trusted @nogc {
    Track* trck;

    if (mDataFormat != DataFormat.Midi || !mPlayerActive) return;

    for (;;) {
      trck = MIDI_NextTrack();
      if (trck.finish || trck.time > mMidiTimechange+(mMidiTimer*mMidiRate)/mMidiCallrate) break;
      MIDI_AdvanceTrack(trck);
      if (!trck.finish) trck.time += MIDI_ReadDelay(&trck.pointer);
    }

    ++mMidiTimer;

    if (mMidiFinished == mMidiCount) {
      if (!mPlayLooped) MIDI_StopSong();
      for (uint i = 0; i < mMidiCount; i++) {
        mMidiTracks[i].pointer = mMidiTracks[i].data;
        mMidiTracks[i].time = MIDI_ReadDelay(&mMidiTracks[i].pointer);
        mMidiTracks[i].lastevent = 0x80;
        mMidiTracks[i].finish = 0;
      }

      for (uint i = 0; i < 16; i++) mMidiChannels.ptr[i] = 0xff;

      mMidiChannelcnt = 0;

      mMidiRate = 1000000/(500000/mMidiTimebase);
      mMidiTimer = 0;
      mMidiTimechange = 0;
      mMidiFinished = 0;

      SynthReset();
    }
  }

  // ////////////////////////////////////////////////////////////////////// //
  // MUS
  void MUS_Callback () nothrow @trusted @nogc {
    if (mDataFormat != DataFormat.Mus || !mPlayerActive) return;
    while (mMusTimer == mMusTimeend) {
      ubyte cmd;
      ubyte evnt;
      ubyte chan;
      ubyte data1;
      ubyte data2;

      cmd = *mMusPointer++;
      chan = cmd&0x0f;
      evnt = (cmd>>4)&7;

      switch (evnt) {
        case 0x00:
          data1 = *mMusPointer++;
          SynthWrite((SynthCmd.NoteOff<<4)|chan, data1, 0);
          break;
        case 0x01:
          data1 = *mMusPointer++;
          if (data1&0x80) {
            data1 &= 0x7f;
            mMusChanVelo.ptr[chan] = *mMusPointer++;
          }
          SynthWrite((SynthCmd.NoteOn<<4)|chan, data1, mMusChanVelo.ptr[chan]);
          break;
        case 0x02:
          data1 = *mMusPointer++;
          SynthWrite((SynthCmd.PitchBend<<4)|chan, (data1&1)<<6, data1>>1);
          break;
        case 0x03:
        case 0x04:
          data1 = *mMusPointer++;
          data2 = 0;
          if (evnt == 0x04) data2 = *mMusPointer++;
          switch (data1) {
            case 0x00: SynthWrite((SynthCmd.Patch<<4)|chan, data2, 0); break;
            case 0x01: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Bank, data2); break;
            case 0x02: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Modulation, data2); break;
            case 0x03: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Volume, data2); break;
            case 0x04: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Pan, data2); break;
            case 0x05: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Expression, data2); break;
            case 0x06: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Reverb, data2); break;
            case 0x07: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Chorus, data2); break;
            case 0x08: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Sustain, data2); break;
            case 0x09: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Soft, data2); break;
            case 0x0a: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.AllNoteOff, data2); break;
            case 0x0b: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.AllNoteOff, data2); break;
            case 0x0c: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.MonoMode, data2); break;
            case 0x0d: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.PolyMode, data2); break;
            case 0x0e: SynthWrite((SynthCmd.Control<<4)|chan, SynthCtl.Reset, data2); break;
            case 0x0f: break;
            default: break;
          }
          break;
        case 0x05:
          break;
        case 0x06:
          if (!mPlayLooped) {
            MUS_StopSong();
            return;
          }
          mMusPointer = mMusData;
          cmd = 0;
          SynthReset();
          break;
        case 0x07:
          ++mMusPointer;
          break;
        default: break;
      }

      if (cmd&0x80) {
        mMusTimeend += MIDI_ReadDelay(&mMusPointer);
        break;
      }
    }
    ++mMusTimer;
  }

  bool MUS_LoadSong () nothrow @trusted @nogc {
    enum mush = "MUS\x1a";
    import core.stdc.string : memcmp;
    if (songdata.length <= MusHeader.sizeof) return false;
    const(MusHeader)* mus = cast(const(MusHeader)*)songdata.ptr;
    if (memcmp(mus.header.ptr, mush.ptr, 4) != 0) return false;
    mMusLength = MISC_Read16LE(mus.length);
    uint musofs = MISC_Read16LE(mus.offset);
    if (musofs >= songdata.length) return false;
    if (songdata.length-musofs < mMusLength) return false;
    mMusData = &(cast(const(ubyte)*)songdata.ptr)[musofs];
    mDataFormat = DataFormat.Mus;
    return true;
  }

  bool MUS_StartSong () nothrow @trusted @nogc {
    if (mDataFormat != DataFormat.Mus || mPlayerActive) return true;
    mMusPointer = mMusData;
    mMusTimer = 0;
    mMusTimeend = 0;
    mPlayerActive = true;
    return false;
  }

  void MUS_StopSong () nothrow @trusted @nogc {
    if (mDataFormat != DataFormat.Mus || !mPlayerActive) return;
    mPlayerActive = false;
    for (uint i = 0; i < 16; i++) {
      SynthWrite(cast(ubyte)((SynthCmd.Control<<4)|i), SynthCtl.AllNoteOff, 0);
    }
    SynthReset();
  }

  void PlayerInit () nothrow @trusted @nogc {
    mSongTempo = DefaultTempo;
    mPlayerActive = false;
    mDataFormat = DataFormat.Unknown;
    mPlayLooped = false;
    mMidiTracks = null;
  }

  version(genmidi_dumper) static immutable string genmidiData = import("GENMIDI.lmp");

  version(genmidi_dumper) bool loadGenMIDI (const(void)* data) nothrow @trusted @nogc {
    import core.stdc.string : memcmp, memcpy;
    static immutable string genmidi_head = "#OPL_II#";
    if (memcmp(data, data, 8) != 0) return false;
    memcpy(&mGenMidi, (cast(const(ubyte)*)data)+8, GenMidi.sizeof);
    mGenMidiLoaded = true;
    return true;
  }

  version(genmidi_dumper) public void dumpGenMidi (VFile fo) { mGenMidi.dump(fo); }

public:
  enum DefaultTempo = 140;

public:
  this (int asamplerate=48000, bool aopl3mode=true, bool astereo=true) nothrow @trusted @nogc {
    version(genmidi_dumper) mGenMidiLoaded = false;
    songdata = null;
    sendConfig(asamplerate, aopl3mode, astereo);
    SynthInit();
    PlayerInit();
    mOPLCounter = 0;
    version(genmidi_dumper) loadGenMIDI(genmidiData.ptr);
  }

  private void sendConfig (int asamplerate, bool aopl3mode, bool astereo) nothrow @safe @nogc {
    if (asamplerate < 4096) asamplerate = 4096;
    if (asamplerate > 96000) asamplerate = 96000;
    mSampleRate = asamplerate;
    chip.reset(mSampleRate);
    mOPL2Mode = !aopl3mode;
    mStereo = astereo;
    SynthInit();
  }

  bool load (const(void)[] data) {
    import core.stdc.string : memcpy;
    stop(); // just in case
    mDataFormat = DataFormat.Unknown;
    //delete songdata;
    version(genmidi_dumper) if (!mGenMidiLoaded) return false;
    // just in case
    scope(failure) {
      mDataFormat = DataFormat.Unknown;
      //delete songdata;
    }
    if (data.length == 0) return false;
    songdata.length = data.length;
    memcpy(songdata.ptr, data.ptr, data.length);
    if (MUS_LoadSong() || MIDI_LoadSong()) return true;
    mDataFormat = DataFormat.Unknown;
    //delete songdata;
    return false;
  }

  @property void tempo (uint atempo) pure nothrow @safe @nogc {
    if (atempo < 1) atempo = 1; else if (atempo > 255) atempo = 255;
    mSongTempo = atempo;
  }

  @property uint tempo () const pure nothrow @safe @nogc { return mSongTempo; }

  @property void looped (bool loop) pure nothrow @safe @nogc { mPlayLooped = loop; }
  @property bool looped () const pure nothrow @safe @nogc { return mPlayLooped; }

  @property bool loaded () const pure nothrow @safe @nogc { return (mDataFormat != DataFormat.Unknown); }

  @property bool playing () const pure nothrow @safe @nogc { return mPlayerActive; }

  @property void stereo (bool v) pure nothrow @safe @nogc { mStereo = v; }
  @property bool stereo () const pure nothrow @safe @nogc { return mStereo; }

  // returns `false` if song cannot be started (or if it is already playing)
  bool play () nothrow @safe @nogc {
    bool res = false;
    final switch (mDataFormat) {
      case DataFormat.Unknown: break;
      case DataFormat.Midi: res = MIDI_StartSong(); break;
      case DataFormat.Mus: res = MUS_StartSong(); break;
    }
    return res;
  }

  void stop () nothrow @safe @nogc {
    final switch (mDataFormat) {
      case DataFormat.Unknown: break;
      case DataFormat.Midi: MIDI_StopSong(); break;
      case DataFormat.Mus: MUS_StopSong(); break;
    }
  }

  // return number of generated *frames*
  // returns 0 if song is complete (and player is not looped)
  uint generate (short[] buffer) nothrow @trusted @nogc {
    if (mDataFormat == DataFormat.Unknown) return 0;
    if (buffer.length > uint.max/64) buffer = buffer[0..uint.max/64];
    uint length = cast(uint)buffer.length;
    if (mStereo) length /= 2;
    if (length < 1) return 0; // oops
    short[2] accm = void;
    uint i = 0;
    while (i < length) {
      if (!mPlayerActive) break;
      while (mOPLCounter >= mSampleRate) {
        if (mPlayerActive) {
          final switch (mDataFormat) {
            case DataFormat.Unknown: assert(0, "the thing that should not be");
            case DataFormat.Midi: MIDI_Callback(); break;
            case DataFormat.Mus: MUS_Callback(); break;
          }
        }
        mOPLCounter -= mSampleRate;
      }
      mOPLCounter += mSongTempo;
      chip.generateResampled(accm.ptr);
      if (mStereo) {
        buffer.ptr[i*2] = accm.ptr[0];
        buffer.ptr[i*2+1] = accm.ptr[1];
      } else {
        buffer.ptr[i] = (accm.ptr[0]+accm.ptr[1])/2;
      }
      ++i;
    }
    return i;
  }
}

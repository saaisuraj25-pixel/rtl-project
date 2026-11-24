# Generates a random RV32I test program for the pipeline testbench.
#
#   python3 gen_random.py <seed> <out_prog.hex> <out_data.hex>
#
# Rules so that every program finishes:
#   - branches and jumps only jump forward (1 to 4 instructions)
#   - x30 holds the data base address 0xC00, loads/stores use offsets -1024..1023
#     so all data accesses are in 0x800..0xFFF (upper half of the 4 KB data memory)
#   - x29 is only used to build jalr targets
#   - mostly registers x1..x8 are used, so there are many dependencies
#     (this exercises forwarding and load-use stalls)
import random
import sys

def r_type(f7, rs2, rs1, f3, rd, op=0b0110011):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op

def i_type(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op

def s_type(imm, rs2, rs1, f3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0b0100011

def b_type(off, rs2, rs1, f3):
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0b1100011

def u_type(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op

def j_type(off, rd):
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0b1101111

def li(rd, value):
    # lui + addi, the addi immediate is sign extended so adjust the upper part
    value &= 0xFFFFFFFF
    lo = value & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xFFFFF
    return [u_type(hi, rd, 0b0110111), i_type(lo, rd, 0, rd, 0b0010011)]

R_OPS  = [(0, 0), (0x20, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0x20, 5), (0, 6), (0, 7)]
I_F3   = [0, 2, 3, 4, 6, 7]            # addi slti sltiu xori ori andi
SH_OPS = [(0, 1), (0, 5), (0x20, 5)]   # slli srli srai
LOAD_F3  = [0, 1, 2, 4, 5]             # lb lh lw lbu lhu
STORE_F3 = [0, 1, 2]                   # sb sh sw
BR_F3    = [0, 1, 4, 5, 6, 7]
SPECIAL  = [0, 1, 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000, 0xFFFF, 0x80]

def make(seed, length=200):
    rnd = random.Random(seed)

    def reg():
        if rnd.random() < 0.8:
            return rnd.randint(1, 8)
        return rnd.randint(0, 28)

    prog = li(30, 0xC00)
    for r in range(1, 29):
        if rnd.random() < 0.3:
            prog += li(r, rnd.choice(SPECIAL))
        else:
            prog += li(r, rnd.getrandbits(32))

    # first make a list of instructions, branch targets are filled in later
    body = []
    for _ in range(length):
        kind = rnd.choices(["r", "i", "sh", "lui", "auipc", "load", "store", "branch", "jal", "jalr"],
                           [25, 18, 6, 3, 3, 13, 11, 13, 4, 4])[0]
        if kind == "r":
            f7, f3 = rnd.choice(R_OPS)
            body.append(("word", r_type(f7, reg(), reg(), f3, reg())))
        elif kind == "i":
            body.append(("word", i_type(rnd.randint(-2048, 2047), reg(), rnd.choice(I_F3), reg(), 0b0010011)))
        elif kind == "sh":
            f7, f3 = rnd.choice(SH_OPS)
            body.append(("word", r_type(f7, rnd.randint(0, 31), reg(), f3, reg(), 0b0010011)))
        elif kind == "lui":
            body.append(("word", u_type(rnd.getrandbits(20), reg(), 0b0110111)))
        elif kind == "auipc":
            body.append(("word", u_type(rnd.getrandbits(20), reg(), 0b0010111)))
        elif kind == "load":
            f3 = rnd.choice(LOAD_F3)
            size = 1 << (f3 & 3)
            off = rnd.randint(-1024 // size, 1023 // size) * size     # keep it aligned
            body.append(("word", i_type(off, 30, f3, reg(), 0b0000011)))
        elif kind == "store":
            f3 = rnd.choice(STORE_F3)
            size = 1 << f3
            off = rnd.randint(-1024 // size, 1023 // size) * size
            body.append(("word", s_type(off, reg(), 30, f3)))
        elif kind == "branch":
            body.append(("branch", rnd.choice(BR_F3), reg(), reg(), rnd.randint(1, 4)))
        elif kind == "jal":
            body.append(("jal", reg(), rnd.randint(1, 4)))
        else:
            body.append(("jalr", reg(), rnd.randint(1, 4)))

    # address (word index) of every body instruction. jalr takes 3 words.
    start = []
    pos = len(prog)
    for item in body:
        start.append(pos)
        pos += 3 if item[0] == "jalr" else 1
    end = pos

    def target(i, skip):
        return start[i + skip] if i + skip < len(body) else end

    for i, item in enumerate(body):
        if item[0] == "word":
            prog.append(item[1])
        elif item[0] == "branch":
            _, f3, rs1, rs2, skip = item
            prog.append(b_type(4 * (target(i, skip) - start[i]), rs2, rs1, f3))
        elif item[0] == "jal":
            _, rd, skip = item
            prog.append(j_type(4 * (target(i, skip) - start[i]), rd))
        else:
            # auipc x29, 0 ; addi x29, x29, offset ; jalr rd, 0(x29)
            _, rd, skip = item
            off = 4 * (target(i, skip) - start[i])
            prog += [u_type(0, 29, 0b0010111), i_type(off, 29, 0, 29, 0b0010011),
                     i_type(0, 29, 0, rd, 0b1100111)]

    prog += [0x00000013] * 4 + [0x00100073]     # some nops, then ebreak
    data = [rnd.getrandbits(32) for _ in range(1024)]
    return prog, data

if __name__ == "__main__":
    seed = int(sys.argv[1])
    prog, data = make(seed)
    with open(sys.argv[2], "w") as f:
        f.write("".join("%08x\n" % w for w in prog))
    with open(sys.argv[3], "w") as f:
        f.write("".join("%08x\n" % w for w in data))

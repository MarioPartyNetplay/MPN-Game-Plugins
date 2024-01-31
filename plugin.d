module me.timz.n64.plugin;

import core.sys.windows.windows;
import core.sys.windows.dll;
import std.algorithm;
import std.random;
import std.range;
import std.string;
import std.json;
import std.file;
import std.conv;
import std.traits;
import std.stdio;
import std.typecons;
import std.math;
import std.bitmanip;

alias Address     = uint;
alias Instruction = uint;

enum Instruction NOP = 0;

ulong flip(ulong value) pure nothrow @nogc @safe {
    import core.bitop;
    return ror(value, 32);
}

size_t swapAddrEndian(T)(size_t address) pure nothrow @nogc @safe {
    static if (T.sizeof == 1) {
        return address ^ 0b11;
    } else static if (T.sizeof == 2) {
        return address ^ 0b10;
    } else {
        return address;
    }
}

T* swapAddrEndian(T)(T* ptr) pure nothrow @nogc {
    return cast(T*)swapAddrEndian!T(cast(size_t)ptr);
}

Address addr(T)(ref T v) {
    return cast(Address)swapAddrEndian!T(cast(ubyte*)&v - memory.ptr) + 0x80000000;
}

ref T val(T)(Address address) {
    return *Ptr!T(address);
}

struct Ptr(T) {
    Address address;

    this(Address a) { address = a; }
    ref Ptr!T opAssign(Address a) { address = a; return this; }
    ref T opIndex(size_t i) { return *Ptr!T(address + cast(int)(i * T.sizeof)); }
    ref T opUnary(string op)() if (op == "*") { return *swapAddrEndian(cast(T*)&memory[address - 0x80000000]); }
    ref Ptr!T opUnary(string op)() if (op == "++") { address += T.sizeof; return this; }
    ref Ptr!T opUnary(string op)() if (op == "--") { address -= T.sizeof; return this; }
    T opCast(T)() const if (is(T == bool)) { return 0x80000000 <= address && address < 0x80800000; }

    alias address this;
}

align (1) struct Arr(T, size_t S = 0) {
    T front;
    
    @property size_t length() const { return S; }
    @property bool empty() const { return S == 0; }
    ref T opIndex(size_t i) { return *swapAddrEndian(swapAddrEndian(&front) + i); }

    int opApply(scope int delegate(ref T) dg) {
        foreach (i; 0..S) {
            if (int result = dg(this[i])) {
                return result;
            }
        }
        return 0;
    }
}

mixin template Field(Address A, T, string N) {
    align (1) struct {
        ubyte[swapAddrEndian!T(A) & 0x7FFFFF] _pad;
        mixin("T " ~ N ~ ";");
    }
}

JSONValue toJSON(T)(const T scl) if (isScalarType!T) { return JSONValue(scl); }
JSONValue toJSON(T)(const T str) if (isSomeString!T) { return JSONValue(str); }
JSONValue toJSON(T)(const T arr) if (isArray!T && !isSomeString!T) {
    return JSONValue(arr.map!(e => e.toJSON()).array);
}
JSONValue toJSON(T)(const T asc) if (isAssociativeArray!T) {
    auto result = parseJSON("{}");
    foreach (ref k, ref v; asc) {
        result[k.to!string()] = v.toJSON();
    }
    return result;
}
JSONValue toJSON(T)(const ref T agg) if (is(T == struct)) {
    JSONValue result = JSONValue("{}");
    foreach (i, ref v; agg.tupleof) {
        auto k = __traits(identifier, agg.tupleof[i]);
        result[k] = v.toJSON();
    }
    return result;
}
JSONValue toJSON(T)(const T agg, JSONValue result = parseJSON("{}")) if (is(T == class)) {
    if (agg is null) return JSONValue(null);
    foreach (i, ref v; agg.tupleof) {
        auto k = __traits(identifier, agg.tupleof[i]);
        result[k] = v.toJSON();
    }
    static if (is(BaseClassesTuple!T[0])) {
        return agg.toJSON!(BaseClassesTuple!T[0])(result);
    } else {
        return result;
    }
}

T fromJSON(T)(const JSONValue scl) if (isScalarType!T) {
    switch (scl.type) {
        case JSONType.integer:  return cast(T)scl.integer;
        case JSONType.uinteger: return cast(T)scl.uinteger;
        case JSONType.float_:   return cast(T)scl.floating;
        case JSONType.true_:    return cast(T)scl.boolean;
        case JSONType.false_:   return cast(T)scl.boolean;
        default:                assert(0, "Invalid JSONValue type");
    }
}
T fromJSON(T)(const JSONValue str) if (isSomeString!T) { return str.str; }
T fromJSON(T)(const JSONValue arr) if (isArray!T && !isSomeString!T) {
    return arr.array.map!(e => e.fromJSON!(ElementType!T)()).array;
}
T fromJSON(T)(const JSONValue obj) if (isAssociativeArray!T) {
    T result;
    foreach (ref k, ref v; obj.object) {
        result[k] = v.fromJSON!(typeof(result[k]))();
    }
    return result;
}
T fromJSON(T)(const JSONValue obj) if (is(T == struct)) {
    T result;
    foreach (i, ref v; result.tupleof) {
        auto k = __traits(identifier, result.tupleof[i]);
        if (auto value = k in obj) {
            v = (*value).fromJSON!(typeof(v))();
        }
    }
    return result;
}
T fromJSON(T)(const JSONValue obj, T result = null) if (is(T == class)) {
    if (obj.type == JSONType.null_) return null;
    if (!result) result = new T;
    foreach (i, ref v; result.tupleof) {
        auto k = __traits(identifier, result.tupleof[i]);
        if (auto value = k in obj) {
            v = (*value).fromJSON!(typeof(v))();
        }
    }
    static if (is(BaseClassesTuple!T[0])) {
        return cast(T)obj.fromJSON!(BaseClassesTuple!T[0])(result);
    } else {
        return result;
    }
}

struct PCG {
    import core.bitop;

    enum isUniformRandom = true;
    enum hasFixedRange = true;
    enum min = uint.min;
    enum max = uint.max;
    enum empty = false;
    enum a = 0x5851f42d4c957f2d;
    enum c = 0x14057b7ef767814f;

    ulong state;

    this(ulong s) @safe nothrow @nogc { seed(s); }
    void seed(ulong s) @safe nothrow @nogc { state = s; popFront(); }
    auto save() const @safe nothrow @nogc { return this; }
    @property uint front() const @safe nothrow @nogc { return ror(cast(uint)(((state >> 18) ^ state) >> 27), state >> 59); }
    void popFront() @safe nothrow @nogc { state = state * a + c; }
    uint next() @safe nothrow @nogc { uint f = front; popFront(); return f; }
}

struct SplitMix64 {
    enum isUniformRandom = true;
    enum hasFixedRange = true;
    enum min = ulong.min;
    enum max = ulong.max;
    enum empty = false;

    ulong state;

    this(ulong s) @safe nothrow @nogc { seed(s); }
    void seed(ulong s) @safe nothrow @nogc { state = s; popFront(); }
    auto save() const @safe nothrow @nogc { return this; }
    @property ulong front() const @safe nothrow @nogc { return hash(state); }
    void popFront() @safe nothrow @nogc { state += 0x9e3779b97f4a7c15; }
    ulong next() @safe nothrow @nogc { ulong f = front; popFront(); return f; }

    static ulong hash(ulong z) @safe nothrow @nogc pure {
        z ^= z >> 30; z *= 0xbf58476d1ce4e5b9;
        z ^= z >> 27; z *= 0x94d049bb133111eb;
        z ^= z >> 31; return z;
    }
}

struct Xoshiro256pp {
    import core.bitop;

    enum isUniformRandom = true;
    enum hasFixedRange = true;
    enum min = ulong.min;
    enum max = ulong.max;
    enum empty = false;

    ulong[4] state;
    
    this(ulong s) @safe nothrow @nogc { seed(s); }
    this(ulong[4] s) @safe nothrow @nogc { seed(s); }
    void seed(ulong s) @safe nothrow @nogc {
        auto r = SplitMix64(s);
        seed([r.next, r.next, r.next, r.next]);
    }
    void seed(ulong[4] s) @safe nothrow @nogc { state = s; }
    auto save() const @safe nothrow @nogc { return this; }
    @property ulong front() const @safe nothrow @nogc { return rol(state[0] + state[3], 23) + state[0]; }
    void popFront() @safe nothrow @nogc {
        auto temp = state[1] << 17;
        state[2] ^= state[0];
        state[3] ^= state[1];
        state[1] ^= state[2];
        state[0] ^= state[3];
        state[2] ^= temp;
        state[3] = rol(state[3], 45);
    }
    ulong next() @safe nothrow @nogc { ulong f = front; popFront(); return f; }
}

double normal(Random)(ref Random r) @safe {
    import std.math;

    double u = r.uniform01();
    double v = r.uniform01();
    return sqrt(-2 * log(u)) * cos(2 * PI * v);
}

Range frontDistanceShuffle(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length <= 1 || d == 0) return r;

    foreach (i, ref e; r[0..$-1]) {
        swap(e, r[i..min($, i+d+1)].choice(gen));
    }

    return r;
}

Range distanceShuffle(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length <= 1 || d == 0) return r;

    void dS(Range)(Range r) {
        auto w = min(d+1, r.length);
        auto cpy = cycle(r[0..w].array);
        auto src = cycle(new bool[w]);
        auto dst = cycle(new bool[w]);

        foreach (size_t i; iota(r.length)) {
            size_t j;

            if (!src[i]) {
                do { j = i + uniform(0, min(r.length-i, w), gen); } while (dst[j]);
                r[j] = cpy[i];
                dst[j] = true;
            }

            if (!dst[i]) {
                do { j = i + uniform(1, min(r.length-i, w), gen); } while (src[j]);
                r[i] = cpy[j];
                src[j] = true;
            }

            if (i+w < r.length) {
                cpy[i+w] = r[i+w];
                src[i+w] = false;
                dst[i+w] = false;
            }
        }
    }

    if (uniform!"[]"(0, 1, gen)) {
        dS(r);
    } else {
        dS(retro(r));
    }
    
    return r;
}

Range distanceShuffleUniform(Range, RandomGen)(Range r, size_t d, ref RandomGen gen) if (isRandomAccessRange!Range && isUniformRNG!RandomGen) {
    if (r.length <= 1 || d == 0) return r;

    auto p = iota(r.length).array; // Positions
    auto q = iota(r.length).array; // Inverse Positions

    void s(size_t i, size_t j) {
        swap(r[i], r[j]);
        swap(p[i], p[j]);
        swap(q[p[i]], q[p[j]]);
    }
    
    for (auto i = 0; i < r.length-1; i++) {
        auto j = uniform(i, min(i+d+1, r.length), gen);
        if (i >= d && q[i-d] >= i && q[i-d] != j) { // Dead End
            while (--i >= 0) s(i, q[i]);            // Reset
        } else {
            s(i, j);
        }
    }

    return r;
}

union Register(T) if (T.sizeof == 4) {
    ulong v;
    struct { T l, h; }
    @property ref U value(U)()  if (U.sizeof == 8) { return *cast(U*)&v; }
    @property ref U lo(U = T)() if (U.sizeof == 4) { return *cast(U*)&l; }
    @property ref U hi(U = T)() if (U.sizeof == 4) { return *cast(U*)&h; }
    ref T opAssign(T rhs) { return l = rhs; }
    alias l this;
}

union GPR {
    Register!uint[32] r;

    struct {
        Register!uint r0, at, v0, v1, a0, a1, a2, a3,
                      t0, t1, t2, t3, t4, t5, t6, t7,
                      s0, s1, s2, s3, s4, s5, s6, s7,
                      t8, t9, k0, k1, gp, sp, fp, ra;
    }
};

union FPR {
    Register!float[32] r;

    struct {
        Register!float f0,  f1,  f2,  f3,  f4,  f5,  f6,  f7,
                       f8,  f9,  f10, f11, f12, f13, f14, f15,
                       f16, f17, f18, f19, f20, f21, f22, f23,
                       f24, f25, f26, f27, f28, f29, f30, f31;
    }
};

enum BUTTON : ushort {
    C_R = 0x0001,
    C_L = 0x0002,
    C_D = 0x0004,
    C_U = 0x0008,
    R   = 0x0010,
    L   = 0x0020,
    D_R = 0x0100,
    D_L = 0x0200,
    D_D = 0x0400,
    D_U = 0x0800,
    S   = 0x1000,
    Z   = 0x2000,
    B   = 0x4000,
    A   = 0x8000
}

union InputData {
    struct {
        ushort buttons;
        byte analogY;
        byte analogX;
    }

    uint value;

    alias value this;
}

interface Plugin {
    void loadConfig();
    void saveConfig();
    void onStart();
    void onInput(int, InputData*);
    void onFrame(ulong);
    void onFinish();
}

abstract class Game(ConfigType) : Plugin {
    string romName;
    string romHash;
	string dllLocation;
    ConfigType config;

    this(string romName, string romHash) {
        this.romName = romName;
        this.romHash = romHash;

        loadConfig();
    }

    void loadConfig() {
        try {
            config = readText(romName ~ ".json").parseJSON().fromJSON!ConfigType();
        } catch (FileException e) {
            config = new ConfigType;
        }
    }

    void saveConfig() {
        std.file.write(romName ~ ".json", config.toJSON().toPrettyString());
    }

    void onStart() { }
    void onInput(int, InputData*) { }
    void onFrame(ulong) { }
    void onFinish() { saveConfig(); }
}

void addAddress(Address addr) {
    addrMask[(addr & 0b111111111100000) >> 5] |= (1 << ((addr & 0b11100) >> 2));
}

void onExec(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeHandlers[address] ~= callback;
    addAddress(address);
}

void onExec(Address address, void delegate() callback) {
    onExec(address, (Address) { callback(); });
}

void onExecOnce(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeOnceHandlers[address] ~= callback;
    addAddress(address);
}

void onExecOnce(Address address, void delegate() callback) {
    onExecOnce(address, (Address) { callback(); });
}

void onExecDone(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeDoneHandlers[address] ~= callback;
    addAddress(address);
}

void onExecDone(Address address, void delegate() callback) {
    onExecDone(address, (Address) { callback(); });
}

void onExecDoneOnce(Address address, void delegate(Address) callback) {
    assert(address % 4 == 0);
    executeDoneOnceHandlers[address] ~= callback;
    addAddress(address);
}

void onExecDoneOnce(Address address, void delegate() callback) {
    onExecDoneOnce(address, (Address) { callback(); });
}

void onRead(T)(ref T r, void delegate() callback)               { onRead!T(r, (ref T v, Address p, Address a) { callback(); }); }
void onRead(T)(ref T r, void delegate(ref T) callback)          { onRead!T(r, (ref T v, Address p, Address a) { callback(v); }); }
void onRead(T)(ref T r, void delegate(ref T, Address) callback) { onRead!T(r, (ref T v, Address p, Address a) { callback(v, p); }); }
void onRead(T)(ref T r, void delegate(ref T, Address, Address) callback) {
    handlers!(T.sizeof).read[r.addr] ~= (v, p, a) { callback(*cast(T*)v, p, a); };
    addAddress(r.addr);
}

void onWrite(T)(ref T r, void delegate() callback)               { onWrite!T(r, (ref T v, Address p, Address a) { callback(); }); }
void onWrite(T)(ref T r, void delegate(ref T) callback)          { onWrite!T(r, (ref T v, Address p, Address a) { callback(v); }); }
void onWrite(T)(ref T r, void delegate(ref T, Address) callback) { onWrite!T(r, (ref T v, Address p, Address a) { callback(v, p); }); }
void onWrite(T)(ref T r, void delegate(ref T, Address, Address) callback) {
    handlers!(T.sizeof).write[r.addr] ~= (v, p, a) { callback(*cast(T*)v, p, a); };
    addAddress(r.addr);
}

void jal(Address addr)                                                                   { jal(addr,  0,  0,  0,  0, (res) { }); }
void jal(Address addr,                                     void delegate()     callback) { jal(addr,  0,  0,  0,  0, (res) { callback(); }); }
void jal(Address addr,                                     void delegate(uint) callback) { jal(addr,  0,  0,  0,  0, callback); }
void jal(Address addr, uint a0)                                                          { jal(addr, a0,  0,  0,  0, (res) { }); }
void jal(Address addr, uint a0,                            void delegate()     callback) { jal(addr, a0,  0,  0,  0, (res) { callback(); }); }
void jal(Address addr, uint a0,                            void delegate(uint) callback) { jal(addr, a0,  0,  0,  0, callback); }
void jal(Address addr, uint a0, uint a1)                                                 { jal(addr, a0, a1,  0,  0, (res) { }); }
void jal(Address addr, uint a0, uint a1,                   void delegate()     callback) { jal(addr, a0, a1,  0,  0, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1,                   void delegate(uint) callback) { jal(addr, a0, a1,  0,  0, callback); }
void jal(Address addr, uint a0, uint a1, uint a2)                                        { jal(addr, a0, a1, a2,  0, (res) { }); }
void jal(Address addr, uint a0, uint a1, uint a2,          void delegate()     callback) { jal(addr, a0, a1, a2,  0, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1, uint a2,          void delegate(uint) callback) { jal(addr, a0, a1, a2,  0, callback); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3)                               { jal(addr, a0, a1, a2, a3, (res) { }); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3, void delegate()     callback) { jal(addr, a0, a1, a2, a3, (res) { callback(); }); }
void jal(Address addr, uint a0, uint a1, uint a2, uint a3, void delegate(uint) callback) {
    GPR g = *gpr;
    FPR f = *fpr;
    gpr.ra = pc();
    gpr.a0 = a0;
    gpr.a1 = a1;
    gpr.a2 = a2;
    gpr.a3 = a3;
    jump(addr);
    gpr.ra.onExecOnce({
        uint v0 = gpr.v0;
        *gpr = g;
        *fpr = f;
        if (callback) {
            callback(v0);
        }
    });
}

void allocConsole() {
    version (Windows) {
        import core.stdc.stdio;
        
        AllocConsole();
        freopen("CONIN$", "r", stdin);
        freopen("CONOUT$", "w", stdout);
        freopen("CONOUT$", "w", stderr);
    }
}

void handleException(Exception e) {
    version (Windows) {
        MessageBoxA(window, e.toString.toStringz, "Error", MB_OK);
    }
}

struct ExecutionInfo {
    void* window;
    const char* romName;
    const char* romHash;
    ubyte* addrMask;
    uint function() pc;
    void function(uint) jump;
    GPR* gpr;
    FPR* fpr;
    ubyte* memory;
    uint memorySize;
}

__gshared {
    immutable(char)* name;
    Xoshiro256pp random;
	void* dll;
    void* window;
    Plugin plugin;
    ubyte* addrMask;
    uint function() pc;
    void function(uint) jump;
    GPR* gpr;
    FPR* fpr;
    ubyte[] memory;
    ulong frame;
    InputData[4] previous;
    Plugin function(string, string) pluginFactory;
    void delegate(Address)[][Address] executeHandlers;
    void delegate(Address)[][Address] executeOnceHandlers;
    void delegate(Address)[][Address] executeDoneHandlers;
    void delegate(Address)[][Address] executeDoneOnceHandlers;
    template handlers(int S) {
        void delegate(void*, Address, Address)[][Address] read;
        void delegate(void*, Address, Address)[][Address] write;
    }
}

extern (C) {
    string getName();

    int startup();
    
    export int PluginStartup(void*, void*, void*) {
        return startup();
    }

    export int PluginShutdown() { return 0; }

    export int PluginGetVersion(int* pluginType, int* pluginVersion, int* apiVersion, immutable(char)** pluginNamePtr, int* pluginCapabilities) {
        if (pluginType) *pluginType = 5;
        if (pluginVersion) *pluginVersion = 0x020000;
        if (apiVersion) *apiVersion = 0x020000;
        if (pluginNamePtr) {
            name = getName().toStringz;
            *pluginNamePtr = name;
        }
        if (pluginCapabilities) *pluginCapabilities = 0;

        return 0;
    }

    export void RomOpen() {
        
    }

    export void RomClosed() {
        try {
            if (plugin) {
                plugin.onFinish();
                plugin = null;
            }
        } catch (Exception e) {
            handleException(e);
        }
    }

    export void InitiateExecution(ExecutionInfo info) {
        try {
            random.seed(0);
            window = info.window;
            addrMask = info.addrMask;
            pc = info.pc;
            jump = info.jump;
            gpr = info.gpr;
            fpr = info.fpr;
            memory = info.memory[0..info.memorySize];
            frame = 0;
            previous.each!((ref b) { b.value = 0; });
            executeHandlers.clear();
            executeOnceHandlers.clear();
            handlers!1.read.clear();
            handlers!2.read.clear();
            handlers!4.read.clear();
            handlers!8.read.clear();
            handlers!1.write.clear();
            handlers!2.write.clear();
            handlers!4.write.clear();
            handlers!8.write.clear();

            if (pluginFactory) {
                string romName = info.romName.to!string().strip();
                string romHash = info.romHash.to!string().strip();
                plugin = pluginFactory(romName, romHash);

                try { plugin.onStart(); }
                catch (Exception e) { handleException(e); }
            } else {
                plugin = null;
            }
        } catch (Exception e) {
            handleException(e);
        }
    }

    export void Input(int port, InputData* input) {
        if (*input && *input != previous[port]) {
            // Choose a random bit to flip in the state of the RNG by hashing the input, port, and frame
            ubyte bit = SplitMix64.hash((frame << 34) | (cast(ulong)port << 32) | *input) >> 56;
            random.state[bit/64] ^= 1UL << (bit%64);
        }
        previous[port] = *input;

        if (plugin) {
            try { plugin.onInput(port, input); }
            catch (Exception e) { handleException(e); }
        }
    }

    export void Frame(uint f) {
        if (plugin) {
            try { plugin.onFrame(frame); }
            catch (Exception e) { handleException(e); }
        }

        random.popFront();
        
        frame++;
    }

    export void Execute(Address pc) {
        if (auto handlers = (pc in executeHandlers)) {
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { handleException(e); }
            });
        }
        
        if (auto handlers = (pc in executeOnceHandlers)) {
            executeOnceHandlers.remove(pc);
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    export void ExecuteDone(Address pc) {
        if (auto handlers = (pc in executeDoneHandlers)) {
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { handleException(e); }
            });
        }
        
        if (auto handlers = (pc in executeDoneOnceHandlers)) {
            executeOnceHandlers.remove(pc);
            (*handlers).each!((h) {
                try { h(pc); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    void ReadHandler(int S)(void* value, Address pc, Address addr) {
        if (auto handlers = (addr in handlers!(S).read)) {
            (*handlers).each!((h) {
                try { h(value, pc, addr); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    void WriteHandler(int S)(void* value, Address pc, Address addr) {
        if (auto handlers = (addr in handlers!(S).write)) {
            (*handlers).each!((h) {
                try { h(value, pc, addr); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    export void Read8  (ubyte  *value, Address pc, Address addr) { ReadHandler !1(value, pc, addr); }
    export void Read16 (ushort *value, Address pc, Address addr) { ReadHandler !2(value, pc, addr); }
    export void Read32 (uint   *value, Address pc, Address addr) { ReadHandler !4(value, pc, addr); }
    export void Read64 (ulong  *value, Address pc, Address addr) { ReadHandler !8(value, pc, addr); }
    export void Write8 (ubyte  *value, Address pc, Address addr) { WriteHandler!1(value, pc, addr); }
    export void Write16(ushort *value, Address pc, Address addr) { WriteHandler!2(value, pc, addr); }
    export void Write32(uint   *value, Address pc, Address addr) { WriteHandler!4(value, pc, addr); }
    export void Write64(ulong  *value, Address pc, Address addr) { WriteHandler!8(value, pc, addr); }
}

version (Windows) {
    extern (Windows)
    BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved) {
        switch (ulReason) {
            case DLL_PROCESS_ATTACH:
                dll = hInstance;
                
                //wchar[MAX_PATH] my_location_array;
                //GetModuleFileName(hInstance, my_location_array.ptr, MAX_PATH);
                //dllPath = my_location_array.ptr.fromStringz.text;
                //dllPath = dllPath[0 .. dllPath.lastIndexOf('\\') + 1];
                
                dll_process_attach(hInstance, true);
                break;

            case DLL_PROCESS_DETACH:			
                dll_process_detach(hInstance, true);
                break;

            case DLL_THREAD_ATTACH:
                dll_thread_attach(true, true);
                break;

            case DLL_THREAD_DETACH:
                dll_thread_detach(true, true);
                break;

            default:
        }
        
        return true;
    }
}

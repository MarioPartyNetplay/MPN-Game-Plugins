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

alias uint Address;
alias uint Instruction;

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
    ref T opIndex(int i) { return *Ptr!T(address + i * T.sizeof); }
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
    ref T opIndex(int i) { return *swapAddrEndian(swapAddrEndian(&front) + i); }

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

    double u = uniform!"(]"(0.0, 1.0, r);
    double v = uniform!"(]"(0.0, 1.0, r);
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
        union Flag {
            ubyte value;
            mixin(bitfields!(
                bool, "src", 1,
                bool, "dst", 1,
                uint, "",    6
            ));
        }

        auto w = min(d+1, r.length);
        auto copy = cycle(r[0..w].array);
        auto flag = cycle(new Flag[w]);

        for (size_t i = 0, j; i < r.length; i++) {
            if (!flag[i].src) {
                do { j = i + uniform(0, min(r.length-i, w), gen); } while (flag[j].dst);
                r[j] = copy[i];
                flag[j].dst = true;
            }

            if (!flag[i].dst) {
                do { j = i + uniform(1, min(r.length-i, w), gen); } while (flag[j].src);
                r[i] = copy[j];
                flag[j].src = true;
            }

            if (i+w < r.length) {
                copy[i+w] = r[i+w];
                flag[i+w].value = 0;
            }
        }
    }

    if (uniform(0, 2, gen)) {
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

union Input {
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
    void onFrame(ulong, Input*);
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
            config = readText(dllPath ~ romName ~ ".json").parseJSON().fromJSON!ConfigType();
        } catch (FileException e) {
            config = new ConfigType;
        }
    }

    void saveConfig() {
        std.file.write(dllPath ~ romName ~ ".json", config.toJSON().toPrettyString());
    }

    void onStart() { }
    void onFrame(ulong, Input*) { }
    void onFinish() { saveConfig(); }
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

void onRead(T)(ref T r, void delegate() callback) { onRead!T(r, (ref T r, ref T v) { callback(); }); }
void onRead(T)(ref T r, void delegate(ref T) callback) { onRead!T(r, (ref T r, ref T v) { callback(v); }); }
void onRead(T)(ref T r, void delegate(ref T, ref T) callback) {
    handlers!(T.sizeof).read[r.addr] ~= (a, v) { callback(a.val!T, *cast(T*)v); };
    addAddress(r.addr);
}

void onWrite(T)(ref T r, void delegate() callback) { onWrite(r, (ref T r, ref T v) { callback(); }); }
void onWrite(T)(ref T r, void delegate(ref T) callback) { onWrite(r, (ref T r, ref T v) { callback(v); }); }
void onWrite(T)(ref T r, void delegate(ref T, ref T) callback) {
    handlers!(T.sizeof).write[r.addr] ~= (a, v) { callback(a.val!T, *cast(T*)v); };
    addAddress(r.addr);
}

void jal(Address addr, void delegate() callback) {
    auto ra = *pc + 4;
    *pc = addr - 4;
    addr.onExecOnce({
        auto g = *gpr;
        auto f = *fpr;
        gpr.ra = ra;
        callback();
        ra.onExecOnce({ *gpr = g; *fpr = f; });
    });
} 

void allocConsole() {
    import core.stdc.stdio;
    
    AllocConsole();
    freopen("CONIN$", "r", stdin);
    freopen("CONOUT$", "w", stdout);
    freopen("CONOUT$", "w", stderr);
}

void handleException(Exception e) {
    MessageBoxA(window, e.toString.toStringz, "Error", MB_OK);
}

__gshared {
    Xoshiro256pp random;
	HMODULE dll;
	string dllPath;
    HWND window;
    Plugin plugin;
    extern (C) void function(Address) addAddress;
    Address* pc;
    GPR* gpr;
    FPR* fpr;
    ubyte[] memory;
    ulong frame;
    Input[4] previous;
    Plugin function(string, string) pluginFactory;
    void delegate(Address)[][Address] executeHandlers;
    void delegate(Address)[][Address] executeOnceHandlers;
    template handlers(int S) {
        void delegate(Address, void*)[][Address] read;
        void delegate(Address, void*)[][Address] write;
    }
}

extern (C) {
    export void RomOpen(
      HWND hwnd,
      const char* romName,
      const char* romHash,
      void function(Address) _addAddress,
      Address* _pc,
      GPR* _gpr,
      FPR* _fpr,
      ubyte* _memory,
      uint _memorySize) {
        try {
            allocConsole();
            random.seed(0);
            window = hwnd;
            addAddress = _addAddress;
            pc = _pc;
            gpr = _gpr;
            fpr = _fpr;
            memory = _memory[0 .. _memorySize];
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
                plugin = pluginFactory(romName.to!string(), romHash.to!string());
            } else {
                plugin = null;
            }
        } catch (Exception e) {
            handleException(e);
        }
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

    export void FrameHandler(Input* input) {
        if (plugin) {
            if (frame == 0) {
                try { plugin.onStart(); }
                catch (Exception e) { handleException(e); }
            }

            try { plugin.onFrame(frame, input); }
            catch (Exception e) { handleException(e); }
        }

        foreach (port; 0..4) {
            if (input[port] && input[port] != previous[port]) {
                // Choose a random bit to flip in the state of the RNG by hashing the input, port, and frame
                ubyte bit = SplitMix64.hash((frame << 34) | (cast(ulong)port << 32) | input[port]) >> 56;
                random.state[bit/64] ^= 1UL << (bit%64);
            }
            previous[port] = input[port];
        }

        random.popFront();
        
        frame++;
    }

    export void ExecutionHandler(Address address) {
        if (auto handlers = (address in executeHandlers)) {
            (*handlers).each!((h) {
                try { h(address); }
                catch (Exception e) { handleException(e); }
            });
        }
        
        if (auto handlers = (address in executeOnceHandlers)) {
            (*handlers).each!((h) {
                try { h(address); }
                catch (Exception e) { handleException(e); }
            });
            executeOnceHandlers.remove(address);
        }
    }

    void ReadHandler(int S)(Address address, void* value) {
        if (auto handlers = (address in handlers!(S).read)) {
            (*handlers).each!((h) {
                try { h(address, value); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    void WriteHandler(int S)(Address address, void* value) {
        if (auto handlers = (address in handlers!(S).write)) {
            (*handlers).each!((h) {
                try { h(address, value); }
                catch (Exception e) { handleException(e); }
            });
        }
    }

    export void ReadByteHandler  (Address address, ubyte  *value) { ReadHandler !1(address, value); }
    export void ReadShortHandler (Address address, ushort *value) { ReadHandler !2(address, value); }
    export void ReadIntHandler   (Address address, uint   *value) { ReadHandler !4(address, value); }
    export void ReadLongHandler  (Address address, ulong  *value) { ReadHandler !8(address, value); }
    export void WriteByteHandler (Address address, ubyte  *value) { WriteHandler!1(address, value); }
    export void WriteShortHandler(Address address, ushort *value) { WriteHandler!2(address, value); }
    export void WriteIntHandler  (Address address, uint   *value) { WriteHandler!4(address, value); }
    export void WriteLongHandler (Address address, ulong  *value) { WriteHandler!8(address, value); }
}

extern (Windows)
BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved) {
    switch (ulReason) {
        case DLL_PROCESS_ATTACH:
			dll = hInstance;
			
			wchar[MAX_PATH] my_location_array;
			GetModuleFileName(hInstance, my_location_array.ptr, MAX_PATH);
			dllPath = my_location_array.ptr.fromStringz.text;
			dllPath = dllPath[0 .. dllPath.lastIndexOf('\\') + 1];
			
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

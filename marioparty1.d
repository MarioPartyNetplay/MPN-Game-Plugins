module me.timz.n64.marioparty2;

import me.timz.n64.marioparty;
import me.timz.n64.plugin;
import std.algorithm;
import std.range;
import std.stdio;
import std.json;
import std.conv;
import std.random;
import std.stdio;
import std.string;
import std.traits;

class Config {
    Character[] characters = [Character.UNDEFINED, Character.UNDEFINED, Character.UNDEFINED, Character.UNDEFINED];
    float[Block] blockWeights;

    this() {
        blockWeights = [
            Block.PLUS:    1,
            Block.MINUS:   1,
            Block.SPEED:   1,
            Block.SLOW:    1,
            Block.WARP:    1,
            Block.NORMAL: 27
        ];
    }
}

class PlayerState {
    
}

class State {
    PlayerState[] players = [
        new PlayerState(),
        new PlayerState(),
        new PlayerState(),
        new PlayerState()
    ];
}

union Player {
    ubyte[48] _data;
    mixin Field!(0x01, ubyte, "cpuDifficulty1");
    mixin Field!(0x02, ubyte, "cpuDifficulty2");
    mixin Field!(0x04, Character, "character");
    mixin Field!(0x07, ubyte, "flags");
    mixin Field!(0x08, ushort, "coins");
    mixin Field!(0x0A, short, "miniGameCoins");
    mixin Field!(0x0C, ushort, "stars");
    mixin Field!(0x0E, ushort, "currentChainIndex");
    mixin Field!(0x10, ushort, "currentSpaceIndex");
    mixin Field!(0x12, ushort, "nextChainIndex");
    mixin Field!(0x14, ushort, "nextSpaceIndex");
    mixin Field!(0x16, ubyte, "poisoned");
    mixin Field!(0x17, PanelColor, "color");
    mixin Field!(0x24, ushort, "miniGameCoins");
    mixin Field!(0x26, ushort, "maxCoins");
    mixin Field!(0x28, ubyte, "happeningSpaces");
    mixin Field!(0x29, ubyte, "redSpaces");
    mixin Field!(0x2A, ubyte, "blueSpaces");
    mixin Field!(0x2B, ubyte, "miniGameSpaces");
    mixin Field!(0x2C, ubyte, "chanceSpaces");
    mixin Field!(0x2D, ubyte, "mushroomSpaces");
    mixin Field!(0x2E, ubyte, "bowserSpaces");
}

union Memory {
    ubyte[0x800000] ram;
    mixin Field!(0x800175B8, Instruction, "randomByteRoutine");
    mixin Field!(0x800ED5C7, ubyte, "totalTurns");
    mixin Field!(0x800ED5C9, ubyte, "currentTurn");
    mixin Field!(0x800ED5DC, ushort, "currentPlayerIndex");
    mixin Field!(0x800F09F4, Scene, "currentScene");
    mixin Field!(0x800F32B0, Arr!(Player, 4), "players");
}

class MarioParty1 : MarioParty!(Config, State, Memory) {
    this(string name, string hash) {
        super(name, hash);
    }

    override void loadConfig() {
        super.loadConfig();
    }

    override bool lockTeams() const {
        return false;
    }

    override bool disableTeams() const {
        return false;
    }

    alias isBoardScene = typeof(super).isBoardScene;
    alias isScoreScene = typeof(super).isScoreScene;

    override bool isBoardScene(Scene scene) const {
        return false;
    }

    override bool isScoreScene(Scene scene) const {
        return false;
    }

    override void onStart() {
        super.onStart();

        0x80040828.onExec({
            gpr.v0 = weighted(config.blockWeights, random);
        });
    }
}

extern (C) {
    string getName() {
        return "Mario Party 1";
    }

    int startup() {
        pluginFactory = (name, hash) => new MarioParty1(name, hash);

        return 0;
    }
}

enum Block : ubyte {
    PLUS   = 0x00,
    MINUS  = 0x01,
    SPEED  = 0x02,
    SLOW   = 0x03,
    WARP   = 0x04,
    NORMAL = 0xFF
}

enum Scene : uint {
    BOOT = 0
}

module me.timz.n64.marioparty3;

import me.timz.n64.marioparty;
import me.timz.n64.plugin;
import std.algorithm;
import std.random;
import std.range;
import std.conv;
import std.traits;
import std.stdio;

enum Item : byte {
    NONE = -1
}

enum Scene : uint {
    CHILLY_WATERS_BOARD    =  72,
    DEEP_BLOOBER_SEA_BOARD =  73,
    SPINY_DESERT_BOARD     =  74,
    WOODY_WOODS_BOARD      =  75,
    CREEPY_CAVERN_BOARD    =  76,
    WALUIGIS_ISLAND_BOARD  =  77,
    FINISH_BOARD           =  79,
    BOWSER                 =  80,
    START_BOARD            =  83,
    CHANCE_TIME            = 106,
    MINI_GAME_RESULTS      = 113,
    GAMBLE_GAME_RESULTS    = 114,
    BATTLE_GAME_RESULTS    = 116,
    BATTLE_ROYAL_SETUP     = 120
}

class PlayerConfig {
    int team;

    this() {}
    this(int team) { this.team = team; }
}

class MarioParty3Config : MarioPartyConfig {
    bool replaceChanceSpaces = true;
    bool blockedMiniGames = true;
    PlayerConfig[] players = [
        new PlayerConfig(0),
        new PlayerConfig(0),
        new PlayerConfig(1),
        new PlayerConfig(1)
    ];
}

union Space {
    static enum Type : ubyte {
        CHANCE   = 0x5,
        GAME_GUY = 0xF
    }
}

union Player {
    ubyte[56] _data;
    mixin Field!(0x02, ubyte, "controller");
    mixin Field!(0x04, ubyte, "flags");
    mixin Field!(0x0A, ushort, "coins");
    mixin Field!(0x0E, ubyte, "stars");
    mixin Field!(0x18, Arr!(Item, 3), "items");
    mixin Field!(0x1C, Color, "color");
    mixin Field!(0x28, ushort, "gameCoins");
    mixin Field!(0x2A, ushort, "maxCoins");
    mixin Field!(0x2D, ubyte, "redSpaces");
    mixin Field!(0x32, ubyte, "itemSpaces");
}

union Data {
    ubyte[0x400000] memory;
    mixin Field!(0x800D1108, Arr!(Player, 4), "players");
    mixin Field!(0x800CE200, Scene, "currentScene");
    mixin Field!(0x800CD05A, ubyte, "turnLimit");
    mixin Field!(0x800CD05B, ubyte, "currentTurn");
    mixin Field!(0x800CD067, ubyte, "currentPlayerIndex");
    mixin Field!(0x8010570E, ubyte, "numberOfRolls");
    mixin Field!(0x80097650, uint, "randomState");
    mixin Field!(0x80102C58, Ptr!Instruction, "booRoutinePtr");
    mixin Field!(0x800DFE88, Instruction, "chooseGameRoutine");
    mixin Field!(0x800FAB98, Instruction, "duelRoutine");
    mixin Field!(0x8000B198, Instruction, "randomByteRoutine");
    mixin Field!(0x80102C08, Arr!(ubyte, 5), "miniGameSelection");
}

class MarioParty3 : MarioParty!(MarioParty3Config, Data) {
    MiniGame[uint] miniGames;
    
    this(string name, string hash) {
        super(name, hash);
    }

    alias isBoardScene = typeof(super).isBoardScene;
    alias isScoreScene = typeof(super).isScoreScene;

    override bool isBoardScene(Scene scene) const {
        switch (scene) {
            case Scene.CHILLY_WATERS_BOARD:
            case Scene.DEEP_BLOOBER_SEA_BOARD:
            case Scene.SPINY_DESERT_BOARD:
            case Scene.WOODY_WOODS_BOARD:
            case Scene.CREEPY_CAVERN_BOARD:
            case Scene.WALUIGIS_ISLAND_BOARD:
                return true;
            default:
                return false;
        }
    }

    override bool isScoreScene(Scene scene) const {
        switch (scene) {
            case Scene.FINISH_BOARD:
            case Scene.BOWSER:
            case Scene.START_BOARD:
            case Scene.CHANCE_TIME:
            case Scene.MINI_GAME_RESULTS:
            case Scene.GAMBLE_GAME_RESULTS:
            case Scene.BATTLE_GAME_RESULTS:
                return true;
            default:
                return isBoardScene(scene);
        }
    }

    override void onStart() {
        super.onStart();

        if (config.teams) {
            duelRoutine.addr.onExec({
                if (!isBoardScene()) return;
                writeln("\tDUEL!");
                teammates(currentPlayer).each!((t) {
                    t.coins = 0;
                });
                gpr.ra.onExecOnce({
                    teammates(currentPlayer).each!((t) {
                        t.coins = currentPlayer.coins;
                    });
                });
            });
        }

        if (config.alwaysDuel) {
            0x800FA854.onExec({ if (isBoardScene()) gpr.v0 = 1; });
        }

        if (config.replaceChanceSpaces) {
            0x800FC594.onExec({ 0x800FC5A4.val!Instruction = 0x10000085; });
            0x800EAEF4.onExec({ if (isBoardScene() && gpr.v0 == Space.Type.CHANCE) gpr.v0 = Space.Type.GAME_GUY; });
        }

        if (config.blockedMiniGames) {
            MiniGame[][MiniGame.Type] miniGameList;
            MiniGame[uint][MiniGame.Type] miniGameScreen;
            0x800DFE90.onExec({
                if (!isBoardScene()) return;
                0x800DFED4.val!Instruction = NOP;
                0x800DFF40.val!Instruction = NOP;
                0x800DFF64.val!Instruction = NOP;
                0x800DFF78.val!Instruction = NOP;
                auto t = miniGames[gpr.v0].type;
                miniGameList.require(t, miniGames.values
                                                 .filter!(g => g.type == t)
                                                 .filter!(g => g.enabled)
                                                 .array.randomShuffle(random));
                if (gpr.s0 !in miniGameScreen.require(t)) {
                    miniGameScreen[t][gpr.s0] = miniGameList[t].front;
                    miniGameList[t].popFront();
                }
                gpr.v0 = miniGameScreen[t][gpr.s0].id;
            });
            0x800DF468.onExec({
                if (!isBoardScene()) return;
                auto t = miniGames[miniGameSelection[gpr.v1]].type;
                miniGameList[t] ~= miniGameScreen[t][gpr.v1];
                miniGameList[t].swapAt(0, uniform(0, miniGameList[t].length / 3, random));
                miniGameScreen[t][gpr.v1] = miniGameList[t].front;
                miniGameList[t].popFront();
            });
        }

        [
            new MiniGame(0x01, MiniGame.Type.ONE_V_THREE, "Hand, Line and Sinker", false),
            new MiniGame(0x02, MiniGame.Type.ONE_V_THREE, "Coconut Conk"),
            new MiniGame(0x03, MiniGame.Type.ONE_V_THREE, "Spotlight Swim"),
            new MiniGame(0x04, MiniGame.Type.ONE_V_THREE, "Boulder Ball"),
            new MiniGame(0x05, MiniGame.Type.ONE_V_THREE, "Crazy Cogs"),
            new MiniGame(0x06, MiniGame.Type.ONE_V_THREE, "Hide and Sneak"),
            new MiniGame(0x07, MiniGame.Type.ONE_V_THREE, "Ridiculous Relay"),
            new MiniGame(0x08, MiniGame.Type.ONE_V_THREE, "Thwomp Pull"),
            new MiniGame(0x09, MiniGame.Type.ONE_V_THREE, "River Raiders"),
            new MiniGame(0x0A, MiniGame.Type.ONE_V_THREE, "Tidal Toss"),
            new MiniGame(0x0B, MiniGame.Type.TWO_V_TWO, "Eatsa Pizza"),
            new MiniGame(0x0C, MiniGame.Type.TWO_V_TWO, "Baby Bowser Broadside", false),
            new MiniGame(0x0D, MiniGame.Type.TWO_V_TWO, "Pump, Pump and Away"),
            new MiniGame(0x0E, MiniGame.Type.TWO_V_TWO, "Hyper Hydrants"),
            new MiniGame(0x0F, MiniGame.Type.TWO_V_TWO, "Picking Panic"),
            new MiniGame(0x10, MiniGame.Type.TWO_V_TWO, "Cosmic Coaster"),
            new MiniGame(0x11, MiniGame.Type.TWO_V_TWO, "Puddle Paddle"),
            new MiniGame(0x12, MiniGame.Type.TWO_V_TWO, "Etch 'n' Catch"),
            new MiniGame(0x13, MiniGame.Type.TWO_V_TWO, "Log Jam"),
            new MiniGame(0x14, MiniGame.Type.TWO_V_TWO, "Slot Synch"),
            new MiniGame(0x15, MiniGame.Type.FOUR_PLAYER, "Treadmill Grill"),
            new MiniGame(0x16, MiniGame.Type.FOUR_PLAYER, "Toadstool Titan"),
            new MiniGame(0x17, MiniGame.Type.FOUR_PLAYER, "Aces High"),
            new MiniGame(0x18, MiniGame.Type.FOUR_PLAYER, "Bounce 'n' Trounce"),
            new MiniGame(0x19, MiniGame.Type.FOUR_PLAYER, "Ice Rink Risk"),
            new MiniGame(0x1A, MiniGame.Type.BATTLE, "Locked Out"),
            new MiniGame(0x1B, MiniGame.Type.FOUR_PLAYER, "Chip Shot Challenge"),
            new MiniGame(0x1C, MiniGame.Type.FOUR_PLAYER, "Parasol Plummet"),
            new MiniGame(0x1D, MiniGame.Type.FOUR_PLAYER, "Messy Memory"),
            new MiniGame(0x1E, MiniGame.Type.FOUR_PLAYER, "Picture Imperfect"),
            new MiniGame(0x1F, MiniGame.Type.FOUR_PLAYER, "Mario's Puzzle Party"),
            new MiniGame(0x20, MiniGame.Type.FOUR_PLAYER, "The Beat Goes On"),
            new MiniGame(0x21, MiniGame.Type.FOUR_PLAYER, "M.P.I.Q."),
            new MiniGame(0x22, MiniGame.Type.FOUR_PLAYER, "Curtain Call"),
            new MiniGame(0x23, MiniGame.Type.FOUR_PLAYER, "Water Whirled"),
            new MiniGame(0x24, MiniGame.Type.FOUR_PLAYER, "Frigid Bridges"),
            new MiniGame(0x25, MiniGame.Type.FOUR_PLAYER, "Awful Tower"),
            new MiniGame(0x26, MiniGame.Type.FOUR_PLAYER, "Cheep Cheep Chase", false),
            new MiniGame(0x27, MiniGame.Type.FOUR_PLAYER, "Pipe Cleaners"),
            new MiniGame(0x28, MiniGame.Type.FOUR_PLAYER, "Snowball Summit"),
            new MiniGame(0x29, MiniGame.Type.BATTLE, "All Fired Up"),
            new MiniGame(0x2A, MiniGame.Type.BATTLE, "Stacked Deck"),
            new MiniGame(0x2B, MiniGame.Type.BATTLE, "Three Door Monty", false),
            new MiniGame(0x2C, MiniGame.Type.FOUR_PLAYER, "Rockin' Raceway"),
            new MiniGame(0x2D, MiniGame.Type.BATTLE, "Merry-Go-Chomp"),
            new MiniGame(0x2E, MiniGame.Type.BATTLE, "Slap Down"),
            new MiniGame(0x2F, MiniGame.Type.BATTLE, "Storm Chasers"),
            new MiniGame(0x30, MiniGame.Type.BATTLE, "Eye Sore"),
            new MiniGame(0x31, MiniGame.Type.DUEL, "Vine With Me"),
            new MiniGame(0x32, MiniGame.Type.DUEL, "Popgun Pick-Off"),
            new MiniGame(0x33, MiniGame.Type.DUEL, "End of the Line"),
            new MiniGame(0x34, MiniGame.Type.DUEL, "Bowser Toss", false),
            new MiniGame(0x35, MiniGame.Type.DUEL, "Baby Bowser Bonkers"),
            new MiniGame(0x36, MiniGame.Type.DUEL, "Motor Rooter"),
            new MiniGame(0x37, MiniGame.Type.DUEL, "Silly Screws"),
            new MiniGame(0x38, MiniGame.Type.DUEL, "Crowd Cover"),
            new MiniGame(0x39, MiniGame.Type.DUEL, "Tick Tock Hop"),
            new MiniGame(0x3A, MiniGame.Type.DUEL, "Fowl Play"),
            new MiniGame(0x3B, MiniGame.Type.ITEM, "Winner's Wheel"),
            new MiniGame(0x3C, MiniGame.Type.ITEM, "Hey, Batter, Batter!"),
            new MiniGame(0x3D, MiniGame.Type.ITEM, "Bobbling Bow-loons"),
            new MiniGame(0x3E, MiniGame.Type.ITEM, "Dorrie Dip"),
            new MiniGame(0x3F, MiniGame.Type.ITEM, "Swinging with Sharks"),
            new MiniGame(0x40, MiniGame.Type.ITEM, "Swing 'n' Swipe"),
            new MiniGame(0x41, MiniGame.Type.CHANCE, "Chance Time"),
            new MiniGame(0x42, MiniGame.Type.SPECIAL, "Stardust Battle"),
            new MiniGame(0x43, MiniGame.Type.GAMBLE, "Game Guy's Roulette", false),
            new MiniGame(0x44, MiniGame.Type.GAMBLE, "Game Guy's Lucky 7"),
            new MiniGame(0x45, MiniGame.Type.GAMBLE, "Game Guy's Magic Boxes"),
            new MiniGame(0x46, MiniGame.Type.GAMBLE, "Game Guy's Sweet Surprise"),
            new MiniGame(0x47, MiniGame.Type.SPECIAL, "Dizzy Dinghies"),
            new MiniGame(0x48, MiniGame.Type.SPECIAL, "Mario's Puzzle Party Pro")
        ].each!(m => miniGames[m.id] = m);
    }
}

shared static this() {
    pluginFactory = (name, hash) => new MarioParty3(name, hash);
}
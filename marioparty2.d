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

class PlayerConfig {
    Item[] items;
    
    this() {}
}

class MarioParty2Config : MarioPartyConfig {
    bool carryThreeItems = true;
    bool randomBoardMiniGames = true;
    int[string] teams;
    PlayerConfig[] players = [
        new PlayerConfig(),
        new PlayerConfig(),
        new PlayerConfig(),
        new PlayerConfig()
    ];
}

union Chain {
    ubyte[8] _data;
    mixin Field!(4, Ptr!ushort, "spaces");
}

union Space {
    static enum Type : ubyte {
        BLUE         = 0x1,
        RED          = 0x2,
        EMPTY        = 0x3,
        HAPPENING    = 0x4,
        CHANCE       = 0x5,
        ITEM         = 0x6,
        BANK         = 0x7,
        INTERSECTION = 0x8,
        BATTLE       = 0x9,
        BOWSER       = 0xC,
        ARROW        = 0xD,
        TOAD         = 0xE,
        BABY_BOWSER  = 0xF
    }

    ubyte[36] _data;
    mixin Field!(1, Type, "type");
}

union Player {
    ubyte[52] _data;
    mixin Field!(0x03, ubyte, "controller");
    mixin Field!(0x04, Character, "character");
    mixin Field!(0x07, ubyte, "flags");
    mixin Field!(0x08, ushort, "coins");
    mixin Field!(0x0E, ushort, "stars");
    mixin Field!(0x10, ushort, "chain");
    mixin Field!(0x12, ushort, "space");
    mixin Field!(0x19, Item, "item");
    mixin Field!(0x1B, Color, "color");
    mixin Field!(0x28, ushort, "gameCoins");
    mixin Field!(0x2A, ushort, "maxCoins");
    mixin Field!(0x2D, ubyte, "redSpaces");
    mixin Field!(0x32, ubyte, "itemSpaces");
}

union Memory {
    ubyte[0x400000] ram;
    mixin Field!(0x800FD2C0, Arr!(Player, 4), "players");
    mixin Field!(0x800FA63C, Scene, "currentScene");
    mixin Field!(0x800F93AE, ushort, "totalTurns");
    mixin Field!(0x800F93B0, ushort, "currentTurn");
    mixin Field!(0x800F93C6, ushort, "currentPlayerIndex");
    mixin Field!(0x800DF645, ubyte, "numberOfRolls");
    mixin Field!(0x800DF718, Ptr!Instruction, "booRoutinePtr");
    mixin Field!(0x80064200, Instruction, "duelRoutine");
    mixin Field!(0x80064478, Instruction, "duelCancelRoutine");
    mixin Field!(0x80018B28, Instruction, "randomByteRoutine");
    mixin Field!(0x8004DE7C, Instruction, "openItemMenuRoutine");
    mixin Field!(0x800F93AA, Board, "currentBoard");
    mixin Field!(0x800E18D4, Ptr!Space, "spaceData");
    mixin Field!(0x800E18D8, Ptr!Chain, "chainData");
    mixin Field!(0x800F851A, byte, "itemMenuOpen");
}

class MarioParty2 : MarioParty!(MarioParty2Config, Memory) {
    this(string name, string hash) {
        super(name, hash);
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
        switch (scene) {
            case Scene.WESTERN_LAND_BOARD:
            case Scene.PIRATE_LAND_BOARD:
            case Scene.HORROR_LAND_BOARD:
            case Scene.SPACE_LAND_BOARD:
            case Scene.MYSTERY_LAND_BOARD:
            case Scene.BOWSER_LAND_BOARD:
                return true;
            default:
                return false;
        }
    }

    override bool isScoreScene(Scene scene) const {
        switch (scene) {
            case Scene.CHANCE_TIME:
            case Scene.FINISH_BOARD:
            case Scene.BOWSER_EVENT:
            case Scene.START_BOARD:
            case Scene.BATTLE_GAME_RESULTS:
            case Scene.MINI_GAME_RESULTS:
                return true;
            default:
                return isBoardScene(scene);
        }
    }

    short getSpaceIndex(Player p) {
        if (!data.chainData) return -1;
        auto spaces = data.chainData[p.data.chain].spaces;
        if (!spaces) return -1;
        return spaces[p.data.space];
    }

    Space* getSpace(Player p) {
        auto i = getSpaceIndex(p);
        return i >= 0 ? &data.spaceData[i] : null;
    }

    bool itemsFull(Player p) {
        return p.config.items.length >= (p.isCPU ? 1 : 3);
    }

    override void onStart() {
        super.onStart();

        if (config.teamMode) {
            data.duelRoutine.addr.onExec({
                if (!isBoardScene()) return;
                teammates(currentPlayer).each!((t) {
                    t.data.coins = 0;
                });
            });
            data.duelCancelRoutine.addr.onExec({
                if (!isBoardScene()) return;
                teammates(currentPlayer).each!((t) {
                    t.data.coins = currentPlayer.data.coins;
                });
            });
        }

        if (config.alwaysDuel) {
            0x800661AC.onExec({ if (isBoardScene()) gpr.v0 = 1; });
        }

        if (config.carryThreeItems) {
            players.each!((p) {
                p.data.item.onRead((ref Item item, Address) {
                    if (!isBoardScene()) return;
                    if (p.config.items.empty) {
                        item = Item.NONE;
                    } else if (p.config.items.canFind(Item.BOWSER_BOMB)) {
                        item = Item.BOWSER_BOMB;
                    } else if (itemsFull(p) || data.itemMenuOpen || pc() == 0x8005EEA8 /* Display Item Icon */) {
                        item = p.config.items.back;
                    } else {
                        item = Item.NONE;
                    }
                    if (auto space = getSpace(p)) {
                        if (space.type == Space.Type.INTERSECTION && p.config.items.canFind(Item.SKELETON_KEY)) {
                            item = Item.SKELETON_KEY;
                        }
                    }
                });

                p.data.item.onWrite((ref Item item) {
                    if (!isBoardScene()) return;
                    if (item == Item.NONE) {
                        if (p.config.items.empty) return;
                        if (auto space = getSpace(p)) {
                            if (space.type == Space.Type.INTERSECTION) {
                                auto i = p.config.items.countUntil(Item.SKELETON_KEY);
                                if (i >= 0) p.config.items = p.config.items.remove(i);
                            } else {
                                p.config.items.popBack();
                            }
                        } else {
                            p.config.items.popBack();
                        }
                    } else {
                        if (itemsFull(p)) return;
                        if (item == Item.BOWSER_BOMB && p.config.items.canFind(Item.BOWSER_BOMB)) return;
                        p.config.items ~= item;
                    }
                    item = p.config.items.empty ? Item.NONE : p.config.items.back;
                    saveConfig();
                });
            });

            data.openItemMenuRoutine.addr.onExec({
                if (!isBoardScene()) return;
                if (currentPlayer is null) return;
                if (currentPlayer.config.items.length <= 1) return;
                if (currentPlayer.config.items.back == Item.BOWSER_BOMB) return;
                currentPlayer.config.items = currentPlayer.config.items.back ~ currentPlayer.config.items[0..$-1];
                currentPlayer.data.item = currentPlayer.config.items.back;
                saveConfig();
            });
        }

        if (config.randomBoardMiniGames) {
            data.currentBoard.onRead((ref Board board, Address) {
                if (!isBoardScene()) return;
                switch (pc()) {
                    case 0x80064574: // Duel Mini-Game
                    case 0x80066428: // Item Mini-Game
                        board = random.uniform!Board;
                        break;
                    default:
                        break;
                }
            });
        }
    }
}

shared static this() {
    name = "Mario Party 2".toStringz;
    pluginFactory = (name, hash) => new MarioParty2(name, hash);
}

enum Board : ushort {
    WESTERN = 0,
    PIRATE  = 1,
    HORROR  = 2,
    SPACE   = 3,
    MYSTERY = 4,
    BOWSER  = 5
}

enum Item : byte {
    NONE             = -1,
    MUSHROOM         =  0,
    SKELETON_KEY     =  1,
    PLUNDER_CHEST    =  2,
    BOWSER_BOMB      =  3,
    DUELING_GLOVE    =  4,
    WARP_BLOCK       =  5,
    GOLDEN_MUSHROOM  =  6,
    BOO_BELL         =  7,
    BOWSER_SUIT      =  8,
    MAGIC_LAMP       =  9
}

enum Scene : uint {
    BOOT                =   0,
    CHANCE_TIME         =  52,
    TRANSITION          =  61,
    WESTERN_LAND_BOARD  =  62,
    PIRATE_LAND_BOARD   =  65,
    HORROR_LAND_BOARD   =  67,
    SPACE_LAND_BOARD    =  69,
    MYSTERY_LAND_BOARD  =  71,
    BOWSER_LAND_BOARD   =  73,
    FINAL_RESULTS       =  81,
    FINISH_BOARD        =  82,
    BOWSER_EVENT        =  83,
    START_BOARD         =  85,
    OPENING_CREDITS     =  87,
    GAME_SETUP          =  88,
    MAIN_MENU           =  91,
    MINI_GAME_LAND      =  92,
    MINI_GAME_RULES_2   =  95,
    MINI_GAME_RULES     =  96,
    TITLE_SCREEN        =  98,
    BATTLE_GAME_RESULTS = 111,
    MINI_GAME_RESULTS   = 112
}

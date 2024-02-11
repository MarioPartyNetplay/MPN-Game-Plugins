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
    bool carryThreeItems = false;
    bool randomBoardMiniGames = false;
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
    mixin Field!(0x800DF724, Ptr!Instruction, "plunderChestRoutinePtr");
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
                p.data.item.onWrite((ref Item item, Address pc) {
                    if (!isBoardScene()) return;
                    //writeln(pc.to!string(16), ": P", p.index, " Write");

                    if (data.itemMenuOpen) {
                        if (item == Item.NONE) {
                            if (!p.config.items.empty) {
                                p.config.items.popFront();
                            }
                        } else if (p.config.items.empty) {
                            p.config.items ~= item;
                        } else {
                            p.config.items[0] = item;
                        }
                    } else if (item != Item.NONE) {
                        p.config.items ~= item;
                    }

                    saveConfig();

                    item = item.NONE;
                });

                p.data.item.onRead((ref Item item, Address pc) {
                    if (!isBoardScene()) return;
                    //if (pc != 0x8005EEA8) writeln(pc.to!string(16), ": P", p.index, " Read");
                    if (item != Item.NONE) return;
                    if (p.config.items.empty) return;

                    if (pc == data.plunderChestRoutinePtr + 0x354) {
                        p.config.items.partialShuffle(1, random); // Randomize item being plundered
                    }

                    if (data.itemMenuOpen) {
                        item = p.config.items.front;
                        return;
                    }

                    if ((pc + 4).val!Instruction == 0x24020001) { // ADDIU V0, R0, 0x0001 (Checking if item is key (hopefully))
                        auto i = p.config.items.countUntil(Item.SKELETON_KEY);
                        if (i >= 0) {
                            item = p.data.item = Item.SKELETON_KEY;
                            p.config.items = p.config.items.remove(i);
                            saveConfig();
                            return;
                        }
                    }

                    if (pc == 0x8004E984) { // Check for Bowser Bomb
                        item = p.config.items.canFind(Item.BOWSER_BOMB) ? Item.BOWSER_BOMB : Item.NONE;
                        return;
                    }

                    if (itemsFull(p) || pc == 0x8005EEA8) { // pc == Display Icon on Panel
                        item = p.config.items.front;
                    }
                });
            });

            data.itemMenuOpen.onWrite((ref byte isOpen) {
                if (!isBoardScene()) return;

                if (data.itemMenuOpen && !isOpen) {
                    players.each!((p) {
                        if (p.config.items.length <= 1) return;

                        p.config.items ~= p.config.items.front;
                        p.config.items.popFront();
                    });
                }

                saveConfig();
            });

            0x8005600C.onExec({ // Executes after declining to use key
                if (!isBoardScene()) return;

                players.each!((p) {
                    if (p.data.item == Item.NONE) return;

                    p.config.items ~= p.data.item; // Move key back
                    p.data.item = Item.NONE;
                    saveConfig();
                });
            });

            0x8006661C.onExec({ // Clear Bowser Bombs
                if (!isBoardScene()) return;

                bool found = false;
                players.each!((p) {
                    ptrdiff_t i;
                    while ((i = p.config.items.countUntil(Item.BOWSER_BOMB)) >= 0) {
                        p.config.items = p.config.items.remove(i);
                        saveConfig();

                        if (found) continue;
                        p.data.item = Item.BOWSER_BOMB;
                        found = true;
                    }
                });
            });
        }

        if (config.randomBoardMiniGames) {
            data.currentBoard.onRead((ref Board board, Address pc) {
                if (!isBoardScene()) return;
                switch (pc) {
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

extern (C) {
    string getName() {
        return "Mario Party 2";
    }

    int startup() {
        pluginFactory = (name, hash) => new MarioParty2(name, hash);

        return 0;
    }
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

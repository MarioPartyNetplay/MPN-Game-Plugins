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
    bool alwaysDuel = false;
    bool lastPlaceDoubleRoll = false;
    bool teamMode = false;
    bool carryThreeItems = false;
    bool randomItemAndDuelMiniGames = false;
    bool cheaperAndBetterItems = false;
    int[Character] teams;
    bool randomBonus = false;
    string[BonusType] bonuses;
    int itemSpacePercentage = 0;
    int extraChanceSpaces = 0;
    float mapScrollSpeedMultiplier = 1.0;
    bool preventRepeatMiniGames = false;
    MiniGame[] blockedMiniGames;

    this() {
        bonuses = [
            BonusType.MINI_GAME: "Mini-Game",
            BonusType.COIN:      "Coin",
            BonusType.HAPPENING: "Happening",
            BonusType.RED:       "Unlucky",
            BonusType.BLUE:      "Blue",
            BonusType.CHANCE:    "Chance",
            BonusType.BOWSER:    "Bowser",
            BonusType.BATTLE:    "Battle",
            BonusType.ITEM:      "Item",
            BonusType.BANK:      "Banking"
        ];
    }
}

class PlayerState {
    Item[] items;
}

class State {
    PlayerState[] players = [
        new PlayerState(),
        new PlayerState(),
        new PlayerState(),
        new PlayerState()
    ];
    ShuffleQueue!MiniGame[MiniGameType] miniGameQueue;
    ShuffleQueue!Board itemGameQueue;
    ShuffleQueue!Board duelGameQueue;
    Space.Type[] spaces;
}

union Chain {
    ubyte[8] _data;
    mixin Field!(4, Ptr!ushort, "spaces");
}

union Space {
    static enum Type : ubyte {
        UNDEFINED   = 0xFF,
        START       = 0x00,
        BLUE        = 0x01,
        RED         = 0x02,
        INVIS_1     = 0x03,
        HAPPENING   = 0x04,
        CHANCE      = 0x05,
        ITEM        = 0x06,
        BANK        = 0x07,
        INVIS_2     = 0x08,
        BATTLE      = 0x09,
        BOWSER      = 0x0C,
        ARROW       = 0x0D,
        STAR        = 0x0E,
        BLACK_STAR  = 0x0F,
        TOAD        = 0x10,
        BABY_BOWSER = 0x11
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
    mixin Field!(0x1B, PanelColor, "color");
    mixin Field!(0x28, ushort, "miniGameCoins");
    mixin Field!(0x2A, ushort, "maxCoins");
    mixin Field!(0x2C, ubyte, "happeningSpaces");
    mixin Field!(0x2D, ubyte, "redSpaces");
    mixin Field!(0x2E, ubyte, "blueSpaces");
    mixin Field!(0x2F, ubyte, "chanceSpaces");
    mixin Field!(0x30, ubyte, "bowserSpaces");
    mixin Field!(0x31, ubyte, "battleSpaces");
    mixin Field!(0x32, ubyte, "itemSpaces");
    mixin Field!(0x33, ubyte, "bankSpaces");

    uint getBonusStat(BonusType type) {
        final switch (type) {
            case BonusType.MINI_GAME: return miniGameCoins;
            case BonusType.COIN:      return maxCoins;
            case BonusType.HAPPENING: return happeningSpaces;
            case BonusType.RED:       return redSpaces;
            case BonusType.BLUE:      return blueSpaces;
            case BonusType.CHANCE:    return chanceSpaces;
            case BonusType.BOWSER:    return bowserSpaces;
            case BonusType.BATTLE:    return battleSpaces;
            case BonusType.ITEM:      return itemSpaces;
            case BonusType.BANK:      return bankSpaces;
        }
    }
}

union Memory {
    ubyte[0x800000] ram;
    mixin Field!(0x80018B28, Instruction, "randomByteRoutine");
    mixin Field!(0x8004DE7C, Instruction, "openItemMenuRoutine");
    mixin Field!(0x80064200, Instruction, "duelRoutine");
    mixin Field!(0x80064478, Instruction, "duelCancelRoutine");
    mixin Field!(0x800CC000, Arr!(ubyte, 10), "itemPrices");
    mixin Field!(0x800DF645, ubyte, "numberOfRolls");
    mixin Field!(0x800DF6C0, Arr!(MiniGame, 5), "miniGameRoulette");
    mixin Field!(0x800DF718, Ptr!Instruction, "booRoutinePtr");
    mixin Field!(0x800DF724, Ptr!Instruction, "plunderChestRoutinePtr");
    mixin Field!(0x800E18A8, float, "mapX");
    mixin Field!(0x800E18AC, float, "mapY");
    mixin Field!(0x800E18D0, ushort, "spaceCount");
    mixin Field!(0x800E18D2, ushort, "chainCount");
    mixin Field!(0x800E18D4, Ptr!Space, "spaces");
    mixin Field!(0x800E18D8, Ptr!Chain, "chains");
    mixin Field!(0x800F851A, byte, "itemMenuOpen");
    mixin Field!(0x800F93AA, Board, "currentBoard");
    mixin Field!(0x800F93AE, ushort, "totalTurns");
    mixin Field!(0x800F93B0, ushort, "currentTurn");
    mixin Field!(0x800F93C6, ushort, "currentPlayerIndex");
    mixin Field!(0x800FA63C, Scene, "currentScene");
    mixin Field!(0x800FD2C0, Arr!(Player, 4), "players");
}

void mallocPerm(size_t size, void delegate(uint ptr) callback) {
    0x80040DA4.jal(cast(ushort)size, callback);
}

void freePerm(uint ptr, void delegate() callback) {
    0x80040DC8.jal(ptr, callback);
}

void mallocTemp(size_t size, void delegate(uint ptr) callback) {
    0x80040E74.jal(cast(ushort)size, callback);
}

void freeTemp(uint ptr, void delegate() callback) {
    0x80040E98.jal(ptr, callback);
}

class MarioParty2 : MarioParty!(Config, State, Memory) {
    BonusType[] bonus;

    this(string name, string hash) {
        super(name, hash);
    }

    override void loadConfig() {
        super.loadConfig();

        bonus = config.bonuses.keys;
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
        if (!p) return -1;
        if (!data.chains) return -1;
        auto spaces = data.chains[p.data.chain].spaces;
        if (!spaces) return -1;
        return spaces[p.data.space];
    }

    Space* getSpace(Player p) {
        auto i = getSpaceIndex(p);
        return i >= 0 ? &data.spaces[i] : null;
    }

    bool itemsFull(Player p) {
        return p.state.items.length >= (p.isCPU ? 1 : 3);
    }

    override void onStart() {
        super.onStart();

        if (config.preventRepeatMiniGames || config.blockedMiniGames.length > 0) {
            data.currentScene.onWrite((ref Scene scene) {
                if (scene == Scene.START_BOARD) {
                    state.miniGameQueue.clear();
                    state.itemGameQueue.clear();
                    state.duelGameQueue.clear();
                    saveState();
                }
            });
            // Populate mini-game roulette
            0x8004AFA8.onExec({
                if (!isBoardScene()) return;
                0x8004AFEC.val!Instruction = NOP;
                0x8004B044.val!Instruction = NOP;
                0x8004B0F0.val!Instruction = NOP;
                0x8004B140.val!Instruction = NOP;
                if (gpr.s0 == 0) {
                    auto type = (cast(MiniGame)gpr.v0).type;
                    auto games = [EnumMembers!MiniGame].filter!(g => g.type == type).array;
                    auto choices = games.filter!(g => !config.blockedMiniGames.canFind(g));
                    auto game = state.miniGameQueue.require(type, ShuffleQueue!MiniGame(choices, random)).next(random);
                    auto altCount = (0x800CBD10 + gpr.s2).val!ubyte - 1;
                    auto roulette = game ~ games.filter!(g => g != game).array.partialShuffle(altCount, random)[0..altCount];
                    roulette.randomShuffle(random).each!((i, e) => data.miniGameRoulette[i] = e);
                    0x8004A1FC.onExecOnce({ gpr.v0 = cast(uint)roulette.countUntil(game); });
                    saveState();
                }
                gpr.v0 = data.miniGameRoulette[gpr.s0];
            });
        }

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
            data.currentScene.onWrite((ref Scene scene) { // Reset lucky spaces at start of game
                if (scene == Scene.START_BOARD) {
                    players.each!(p => p.state.items = []);
                    saveState();
                }
            });

            players.each!((p) {
                p.data.item.onWrite((ref Item item, Address pc) {
                    if (!isBoardScene()) return;
                    //writeln(pc.to!string(16), ": P", p.index, " Write");

                    if (data.itemMenuOpen) {
                        if (item == Item.NONE) {
                            if (!p.state.items.empty) {
                                p.state.items.popFront();
                            }
                        } else if (p.state.items.empty) {
                            p.state.items ~= item;
                        } else {
                            p.state.items[0] = item;
                        }
                    } else if (item != Item.NONE) {
                        p.state.items ~= item;
                    }

                    saveState();

                    item = item.NONE;
                });

                p.data.item.onRead((ref Item item, Address pc) {
                    if (!isBoardScene()) return;
                    //if (pc != 0x8005EEA8) writeln(pc.to!string(16), ": P", p.index, " Read");
                    if (item != Item.NONE) return;
                    if (p.state.items.empty) return;

                    if (pc == data.plunderChestRoutinePtr + 0x354) {
                        p.state.items.partialShuffle(1, random); // Randomize item being plundered
                    }

                    if (data.itemMenuOpen) {
                        item = p.state.items.front;
                        return;
                    }

                    if ((pc + 4).val!Instruction == 0x24020001) { // ADDIU V0, R0, 0x0001 (Checking if item is key (hopefully))
                        auto i = p.state.items.countUntil(Item.SKELETON_KEY);
                        if (i >= 0) {
                            item = p.data.item = Item.SKELETON_KEY;
                            p.state.items = p.state.items.remove(i);
                            saveState();
                            return;
                        }
                    }

                    if (p.state.items.canFind(Item.BOWSER_BOMB)) {
                        if (p.index != data.currentPlayerIndex || pc == 0x8004E984) { // pc == Check for Bowser Bomb
                            item = Item.BOWSER_BOMB;
                            return;
                        }
                    }

                    if (itemsFull(p) || pc == 0x8005EEA8) { // pc == Display Icon on Panel
                        item = p.state.items.front;
                    }
                });
            });

            data.itemMenuOpen.onWrite((ref byte isOpen) {
                if (!isBoardScene()) return;

                if (data.itemMenuOpen && !isOpen) {
                    players.each!((p) {
                        if (p.state.items.length <= 1) return;

                        p.state.items ~= p.state.items.front;
                        p.state.items.popFront();
                    });
                }

                saveState();
            });

            0x8005600C.onExec({ // Executes after declining to use key
                if (!isBoardScene()) return;

                players.each!((p) {
                    if (p.data.item == Item.NONE) return;

                    p.state.items ~= p.data.item; // Move key back
                    p.data.item = Item.NONE;
                    saveState();
                });
            });

            0x8006661C.onExec({ // Clear Bowser Bombs
                if (!isBoardScene()) return;

                bool found = false;
                players.each!((p) {
                    ptrdiff_t i;
                    while ((i = p.state.items.countUntil(Item.BOWSER_BOMB)) >= 0) {
                        p.state.items = p.state.items.remove(i);
                        saveState();

                        if (found) continue;
                        p.data.item = Item.BOWSER_BOMB;
                        found = true;
                    }
                });
            });
        }

        if (config.cheaperAndBetterItems) {
            // Decrease item price by 5 coins
            for (auto item = Item.MUSHROOM; item <= Item.MAGIC_LAMP; item++) {
                data.itemPrices[item].onRead((ref ubyte price) {
                    if (!isBoardScene()) return;
                    if (!price) return;

                    price -= 5;
                });
            }

            // Allow players with 5 or more coins to shop
            players.each!((p) {
                p.data.coins.onRead((ref ushort coins, Address pc) {
                    if (!isBoardScene()) return;

                    auto space = getSpace(currentPlayer);
                    if (!space || space.type != Space.Type.ARROW) return;

                    if (((pc + 4).val!Instruction & 0xFC00FFFF) == 0x2800000A) { // SLTI $T, $S, 10
                        coins += 5;
                    }
                });
            });

            // Update prices in dialog box
            0x8009DB18.onExecDone({
                if (!isBoardScene()) return;
                if (gpr.v0 < 16 || gpr.v0 >= 0x7FF) return;
                char[16] start;
                start.each!((i, ref c) => c = (gpr.a3 + cast(uint)i).val!char);
                if (start != "\x0B\x1A\x1A\x1A\x1AWhich \x0FItem") return;

                auto text = new char[gpr.v0];
                text.each!((i, ref c) => c = (gpr.a3 + cast(uint)i).val!char);
                text.replace("x 10", "x  5")
                    .replace("x 15", "x 10")
                    .replace("x 20", "x 15")
                    .replace("x 25", "x 20")
                    .replace("x 30", "x 25")
                    .each!((i, ref c) => (gpr.a3 + cast(uint)i).val!char = c);
            });

            // Make items available at all times
            data.currentTurn.onRead((ref ushort turn, Address pc) {
                if (!isBoardScene()) return;
                auto space = getSpace(currentPlayer);
                if (!space) return;

                if (space.type == Space.Type.ARROW) { // Item Shop
                    turn = cast(ushort)(data.totalTurns - 1);
                } else if (pc == 0x800663C8) {        // Item Space
                    turn = cast(ushort)(data.totalTurns - 1);
                }
            });
        }

        if (config.randomItemAndDuelMiniGames) {
            data.currentBoard.onRead((ref Board board, Address pc) {
                if (!isBoardScene()) return;

                if (state.duelGameQueue.empty) state.duelGameQueue.initialize([EnumMembers!Board], random);
                if (state.itemGameQueue.empty) state.itemGameQueue.initialize([EnumMembers!Board], random);

                switch (pc) {
                    case 0x80064574: board = state.duelGameQueue.next(random); break;
                    case 0x80066428: board = state.itemGameQueue.next(random); break;
                    default: return;
                }

                saveState();
            });
        }

        if (config.randomBonus) {
            data.currentScene.onWrite((ref Scene scene) {
                if (scene != Scene.FINISH_BOARD) return;
                bonus.partialShuffle(3, random);
                info("Bonus Stars: ", bonus[0..3]);
            });

            0x80103F04.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v1 = data.players[gpr.s1].getBonusStat(bonus[BonusType.MINI_GAME]);
            });

            0x80103F50.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v0 = data.players[gpr.s1].getBonusStat(bonus[BonusType.MINI_GAME]);
            });

            0x80104314.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v1 = data.players[gpr.s1].getBonusStat(bonus[BonusType.COIN]);
            });

            0x80104360.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v0 = data.players[gpr.s1].getBonusStat(bonus[BonusType.COIN]);
            });

            0x80104724.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v1 = data.players[gpr.s1].getBonusStat(bonus[BonusType.HAPPENING]);
            });

            0x80104770.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;
                gpr.v0 = data.players[gpr.s1].getBonusStat(bonus[BonusType.HAPPENING]);
            });

            void setText(string text) {
                text = text.replace("<BLACK>",  "\x01")
                           .replace("<BLUE>",   "\x02")
                           .replace("<RED>",    "\x03")
                           .replace("<PINK>",   "\x04")
                           .replace("<GREEN>",  "\x05")
                           .replace("<CYAN>",   "\x06")
                           .replace("<YELLOW>", "\x07")
                           .replace("<1>",      "\x11")
                           .replace("<2>",      "\x12")
                           .replace("<3>",      "\x13")
                           .replace("<RESET>",  "\x19")
                           .replace('-',        '\x3D')
                           .replace('\'',       '\x5C')
                           .replace(',',        '\x82')
                           .replace('.',        '\x85')
                           .replace('!',        '\xC2')
                           .replace('?',        '\xC3');
                text ~= "\xFF\x00";
                mallocTemp(text.length, (ptr) {
                    text.each!((i, c) { Ptr!char(ptr)[i] = c; });
                    gpr.a1 = ptr;
                });
            }

            0x800890CC.onExecDone({
                if (data.currentScene != Scene.FINISH_BOARD) return;

                switch (gpr.a1) {
                    case 0x5F8: setText("First, the <" ~ getColor(bonus[BonusType.MINI_GAME]) ~ ">" ~ config.bonuses[bonus[BonusType.MINI_GAME]] ~ " Star<RESET>\naward! This award goes to\nthe player who " ~ getDescription(bonus[BonusType.MINI_GAME])  ~ "."); break;
                    case 0x5F9: setText("The <" ~ getColor(bonus[BonusType.MINI_GAME]) ~ ">" ~ config.bonuses[bonus[BonusType.MINI_GAME]] ~ " Star<RESET>\ngoes to <1>!"); break;
                    case 0x5FA: setText("It's a tie! <YELLOW>Stars<RESET> go\nto two players...\n<1> and <2>!"); break;
                    case 0x5FB: setText("It's a three-way tie!\n<YELLOW>Stars<RESET> go to three\nplayers...<1>,\n<2> and <3>!"); break;
                    case 0x5FC: setText("It's a four-way tie!!!\nAll four players are\n<" ~ getColor(bonus[BonusType.MINI_GAME]) ~ ">" ~ config.bonuses[bonus[BonusType.MINI_GAME]] ~ " Stars<RESET>, so no\n<YELLOW>Stars<RESET> will be awarded."); break;
                    case 0x5FD: setText("Next, the <" ~ getColor(bonus[BonusType.COIN]) ~ ">" ~ config.bonuses[bonus[BonusType.COIN]] ~ " Star<RESET>\naward! This award goes to\nthe player who " ~ getDescription(bonus[BonusType.COIN])  ~ "."); break;
                    case 0x5FE: setText("The <" ~ getColor(bonus[BonusType.COIN]) ~ ">" ~ config.bonuses[bonus[BonusType.COIN]] ~ " Star<RESET>\ngoes to <1>!"); break;
                    case 0x5FF: setText("It's a tie! <YELLOW>Stars<RESET> go\nto two players...\n<1> and <2>!"); break;
                    case 0x600: setText("It's a three-way tie!\n<YELLOW>Stars<RESET> go to three\nplayers...<1>,\n<2> and <3>!"); break;
                    case 0x601: setText("It's a four-way tie!!!\nAll four players are\n<" ~ getColor(bonus[BonusType.COIN]) ~ ">" ~ config.bonuses[bonus[BonusType.COIN]] ~ " Stars<RESET>, so no\n<YELLOW>Stars<RESET> will be awarded."); break;
                    case 0x602: setText("Finally, the <" ~ getColor(bonus[BonusType.HAPPENING]) ~ ">" ~ config.bonuses[bonus[BonusType.HAPPENING]] ~ " Star<RESET>\naward! This award goes to\nthe player who " ~ getDescription(bonus[BonusType.HAPPENING])  ~ "."); break;
                    case 0x603: setText("The <" ~ getColor(bonus[BonusType.HAPPENING]) ~ ">" ~ config.bonuses[bonus[BonusType.HAPPENING]] ~ " Star<RESET>\ngoes to <1>!"); break;
                    case 0x604: setText("It's a tie! <YELLOW>Stars<RESET> go\nto two players...\n<1> and <2>!"); break;
                    case 0x605: setText("It's a three-way tie!\n<YELLOW>Stars<RESET> go to three\nplayers...<1>,\n<2> and <3>!"); break;
                    case 0x606: setText("It's a four-way tie!!!\nAll four players are\n<" ~ getColor(bonus[BonusType.HAPPENING]) ~ ">" ~ config.bonuses[bonus[BonusType.HAPPENING]] ~ " Stars<RESET>, so no\n<YELLOW>Stars<RESET> will be awarded."); break;
                    default:
                }
            });
        }

        if (config.itemSpacePercentage > 0 || config.extraChanceSpaces > 0) {
            data.currentScene.onWrite((ref Scene scene) {
                if (scene == Scene.START_BOARD) {
                    state.spaces = [];
                    saveState();
                }
            });

            0x80054AE0.onExec({
                if (!isBoardScene()) return;

                if (data.spaceCount > state.spaces.length) {
                    state.spaces.length = data.spaceCount;
                    auto blueSpaces = iota(data.spaceCount).filter!(i => data.spaces[i].type == Space.Type.BLUE).array;

                    long chanceCount = config.extraChanceSpaces
                                     - blueSpaces.count!(i => state.spaces[i] == Space.Type.CHANCE);
                    if (chanceCount > 0) {
                        blueSpaces.filter!(i => state.spaces[i] == Space.Type.UNDEFINED)
                                  .array.partialShuffle(chanceCount, random)[0..chanceCount]
                                  .each!(i => data.spaces[i].type = state.spaces[i] = Space.Type.CHANCE);
                    }

                    long itemCount = roundTo!long(blueSpaces.length * min(0.01 * config.itemSpacePercentage, 1.0))
                                   - blueSpaces.count!(i => state.spaces[i] == Space.Type.ITEM);
                    if (itemCount > 0) {
                        blueSpaces.filter!(i => state.spaces[i] == Space.Type.UNDEFINED)
                                  .array.partialShuffle(itemCount, random)[0..itemCount]
                                  .each!(i => data.spaces[i].type = state.spaces[i] = Space.Type.ITEM);
                    }

                    saveState();
                }
            });

            0x80054940.onExec({
                if (!isBoardScene()) return;
                if (gpr.s2 >= state.spaces.length) return;
                if (state.spaces[gpr.s2] == Space.Type.UNDEFINED) return;
                if (gpr.v0 == Space.Type.STAR || gpr.v0 == Space.Type.BLACK_STAR) return;

                gpr.v0 = state.spaces[gpr.s2];
            });
        }

        if (config.mapScrollSpeedMultiplier != 1.0) {
            0x80067944.onExec({
                if (!isBoardScene()) return;

                fpr.f12 *= config.mapScrollSpeedMultiplier;
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

enum BonusType {
    MINI_GAME,
    COIN,
    HAPPENING,
    RED,
    BLUE,
    CHANCE,
    BOWSER,
    BATTLE,
    ITEM,
    BANK
}

string getColor(BonusType type) {
    final switch (type) {
        case BonusType.MINI_GAME: return "CYAN";
        case BonusType.COIN:      return "YELLOW";
        case BonusType.HAPPENING: return "GREEN";
        case BonusType.RED:       return "RED";
        case BonusType.BLUE:      return "BLUE";
        case BonusType.CHANCE:    return "GREEN";
        case BonusType.BOWSER:    return "RED";
        case BonusType.BATTLE:    return "GREEN";
        case BonusType.ITEM:      return "GREEN";
        case BonusType.BANK:      return "YELLOW";
    }
}

string getDescription(BonusType type) {
    final switch (type) {
        case BonusType.MINI_GAME: return "collected the\nmost <YELLOW>Coins<RESET> in Mini-Games";
        case BonusType.COIN:      return "held the\nmost <YELLOW>Coins<RESET> at one time";
        case BonusType.HAPPENING: return "landed on\nthe most <GREEN>? Spaces<RESET>";
        case BonusType.RED:       return "landed on\nthe most <RED>Red Spaces<RESET>";
        case BonusType.BLUE:      return "landed on\nthe most <BLUE>Blue Spaces<RESET>";
        case BonusType.CHANCE:    return "landed on\nthe most <GREEN>! Spaces<RESET>";
        case BonusType.BOWSER:    return "landed on\nthe most <RED>Bowser Spaces<RESET>";
        case BonusType.BATTLE:    return "landed on\nthe most <GREEN>Battle Spaces<RESET>";
        case BonusType.ITEM:      return "landed on\nthe most <GREEN>Item Spaces<RESET>";
        case BonusType.BANK:      return "landed on\nthe most <GREEN>Bank Spaces<RESET>";
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
    NONE            = -1,
    MUSHROOM        =  0,
    SKELETON_KEY    =  1,
    PLUNDER_CHEST   =  2,
    BOWSER_BOMB     =  3,
    DUELING_GLOVE   =  4,
    WARP_BLOCK      =  5,
    GOLDEN_MUSHROOM =  6,
    BOO_BELL        =  7,
    BOWSER_SUIT     =  8,
    MAGIC_LAMP      =  9
}

enum MiniGameType {
    ONE_V_THREE,
    TWO_V_TWO,
    FOUR_PLAYER,
    BATTLE,
    DUEL,
    ITEM,
    SPECIAL
}

enum MiniGame : ubyte {
    BOWSER_SLOTS        =  1,
    ROLL_OUT_THE_BARELS =  2,
    COFFIN_CONGESTION   =  3,
    HAMMER_SLAMMER      =  4,
    GIVE_ME_A_BRAKE     =  5,
    MALLET_GO_ROUND     =  6,
    GRAB_BAG            =  7,
    BUMPER_BALLOON_CARS =  8,
    RAKE_EM_IN          =  9,
    DAY_AT_THE_RACES    = 11,
    FACE_LIFT           = 12,
    CRAZY_CUTTERS       = 13,
    HOT_BOB_OMB         = 14,
    BOWL_OVER           = 15,
    RAINBOW_RUN         = 16,
    CRANE_GAME          = 17,
    MOVE_TO_THE_MUSIC   = 18,
    BOB_OMB_BARRAGE     = 19,
    LOOK_AWAY           = 20,
    SHOCK_DROP_OR_ROLL  = 21,
    LIGHTS_OUT          = 22,
    FILET_RELAY         = 23,
    ARCHER_IVAL         = 24,
    TOAD_BANDSTAND      = 26,
    BOBSLED_RUN         = 27,
    HANDCAR_HAVOC       = 28,
    BALLOON_BURST       = 30,
    SKY_PILOTS          = 31,
    SPEED_HOCKEY        = 32,
    CAKE_FACTORY        = 33,
    DUNGEON_DASH        = 35,
    MAGNET_CARTA        = 36,
    LAVA_TILE_ISLE      = 37,
    HOT_ROPE_JUMP       = 38,
    SHELL_SHOCKED       = 39,
    TOAD_IN_THE_BOX     = 40,
    MECHA_MARATHON      = 41,
    ROLL_CALL           = 42,
    ABANDON_SHIP        = 43,
    PLATFORM_PERIL      = 44,
    TOTEM_POLE_POUND    = 45,
    BUMPER_BALLS        = 46,
    BOMBS_AWAY          = 48,
    TIPSY_TOURNEY       = 49,
    HONEYCOMB_HAVOC     = 50,
    HEXAGON_HEAT        = 51,
    SKATEBOARD_SCAMPER  = 52,
    SLOT_CAR_DERBY      = 53,
    SHY_GUY_SAYS        = 54,
    SNEAK_N_SNORE       = 55,
    DRIVERS_ED          = 57,
    CHANCE_TIME         = 58,
    QUICK_DRAW_CORKS    = 59,
    SABER_SLASHES       = 60,
    MUSHROOM_BREW       = 61,
    TIME_BOMB           = 62,
    PSYCHIC_SAFARI      = 63,
    ROCK_PAPER_MARIO    = 64,
    BOWSERS_BIG_BLAST   = 65,
    LOONEY_LUMBERJACKS  = 66,
    TORPEDO_TARGETS     = 67,
    DESTRUCTION_DUET    = 68,
    DIZZY_DANCING       = 69,
    TILE_DRIVER         = 70,
    QUICKSAND_CACHE     = 71,
    DEEP_SEA_SALVAGE    = 72
}

MiniGameType type(MiniGame game) {
    switch (game) {
        case MiniGame.LAVA_TILE_ISLE:
        case MiniGame.HOT_ROPE_JUMP:
        case MiniGame.SHELL_SHOCKED:
        case MiniGame.TOAD_IN_THE_BOX:
        case MiniGame.MECHA_MARATHON:
        case MiniGame.ROLL_CALL:
        case MiniGame.ABANDON_SHIP:
        case MiniGame.PLATFORM_PERIL:
        case MiniGame.TOTEM_POLE_POUND:
        case MiniGame.BUMPER_BALLS:
        case MiniGame.BOMBS_AWAY:
        case MiniGame.TIPSY_TOURNEY:
        case MiniGame.HONEYCOMB_HAVOC:
        case MiniGame.HEXAGON_HEAT:
        case MiniGame.SKATEBOARD_SCAMPER:
        case MiniGame.SLOT_CAR_DERBY:
        case MiniGame.SHY_GUY_SAYS:
        case MiniGame.SNEAK_N_SNORE:
        case MiniGame.DIZZY_DANCING:
        case MiniGame.TILE_DRIVER:
        case MiniGame.DEEP_SEA_SALVAGE:
            return MiniGameType.FOUR_PLAYER;

        case MiniGame.BOWL_OVER:
        case MiniGame.RAINBOW_RUN:
        case MiniGame.CRANE_GAME:
        case MiniGame.MOVE_TO_THE_MUSIC:
        case MiniGame.BOB_OMB_BARRAGE:
        case MiniGame.LOOK_AWAY:
        case MiniGame.SHOCK_DROP_OR_ROLL:
        case MiniGame.LIGHTS_OUT:
        case MiniGame.FILET_RELAY:
        case MiniGame.ARCHER_IVAL:
        case MiniGame.QUICKSAND_CACHE:
            return MiniGameType.ONE_V_THREE;

        case MiniGame.TOAD_BANDSTAND:
        case MiniGame.BOBSLED_RUN:
        case MiniGame.HANDCAR_HAVOC:
        case MiniGame.BALLOON_BURST:
        case MiniGame.SKY_PILOTS:
        case MiniGame.SPEED_HOCKEY:
        case MiniGame.CAKE_FACTORY:
        case MiniGame.DUNGEON_DASH:
        case MiniGame.MAGNET_CARTA:
        case MiniGame.LOONEY_LUMBERJACKS:
        case MiniGame.TORPEDO_TARGETS:
        case MiniGame.DESTRUCTION_DUET:
            return MiniGameType.TWO_V_TWO;

        case MiniGame.GRAB_BAG:
        case MiniGame.BUMPER_BALLOON_CARS:
        case MiniGame.RAKE_EM_IN:
        case MiniGame.DAY_AT_THE_RACES:
        case MiniGame.HOT_BOB_OMB:
        case MiniGame.FACE_LIFT:
        case MiniGame.CRAZY_CUTTERS:
        case MiniGame.BOWSERS_BIG_BLAST:
            return MiniGameType.BATTLE;

        case MiniGame.BOWSER_SLOTS:
        case MiniGame.ROLL_OUT_THE_BARELS:
        case MiniGame.COFFIN_CONGESTION:
        case MiniGame.HAMMER_SLAMMER:
        case MiniGame.GIVE_ME_A_BRAKE:
        case MiniGame.MALLET_GO_ROUND:
            return MiniGameType.ITEM;

        case MiniGame.QUICK_DRAW_CORKS:
        case MiniGame.SABER_SLASHES:
        case MiniGame.MUSHROOM_BREW:
        case MiniGame.TIME_BOMB:
        case MiniGame.PSYCHIC_SAFARI:
        case MiniGame.ROCK_PAPER_MARIO:
            return MiniGameType.DUEL;

        default:
            return MiniGameType.SPECIAL;
    }
}

enum Scene : uint {
    BOOT                =   0,
    BOWSER_SLOTS        =   1,
    ROLL_OUT_THE_BARELS =   2,
    COFFIN_CONGESTION   =   3,
    HAMMER_SLAMMER      =   4,
    GIVE_ME_A_BRAKE     =   5,
    MALLET_GO_ROUND     =   6,
    GRAB_BAG            =   7,
    LAVA_TILE_ISLE      =   8,
    BUMPER_BALLOON_CARS =   9,
    RAKE_EM_IN          =  10,
    DAY_AT_THE_RACES    =  11,
    HOT_ROPE_JUMP       =  12,
    HOT_BOB_OMB         =  13,
    BOWL_OVER           =  14,
    RAINBOW_RUN         =  15,
    CRANE_GAME          =  16,
    MOVE_TO_THE_MUSIC   =  17,
    BOB_OMB_BARRAGE     =  18,
    LOOK_AWAY           =  19,
    SHOCK_DROP_OR_ROLL  =  20,
    LIGHTS_OUT          =  21,
    FILET_RELAY         =  22,
    ARCHER_IVAL         =  23,
    TOAD_BANDSTAND      =  24,
    BOBSLED_RUN         =  25,
    HANDCAR_HAVOC       =  26,
    BALLOON_BURST       =  27,
    SKY_PILOTS          =  28,
    SPEED_HOCKEY        =  29,
    CAKE_FACTORY        =  30,
    DUNGEON_DASH        =  31,
    MAGNET_CARTA        =  32,
    FACE_LIFT           =  33,
    SHELL_SHOCKED       =  34,
    CRAZY_CUTTERS       =  35,
    TOAD_IN_THE_BOX     =  36,
    MECHA_MARATHON      =  37,
    ROLL_CALL           =  38,
    ABANDON_SHIP        =  39,
    PLATFORM_PERIL      =  40,
    TOTEM_POLE_POUND    =  41,
    BUMPER_BALLS        =  42,
    BOMBS_AWAY          =  43,
    TIPSY_TOURNEY       =  44,
    HONEYCOMB_HAVOC     =  45,
    HEXAGON_HEAT        =  46,
    SKATEBOARD_SCAMPER  =  47,
    SLOT_CAR_DERBY      =  48,
    SHY_GUY_SAYS        =  49,
    SNEAK_N_SNORE       =  50,
    DRIVERS_ED          =  51,
    CHANCE_TIME         =  52,
    LOONEY_LUMBERJACKS  =  53,
    DIZZY_DANCING       =  54,
    TILE_DRIVER         =  55,
    QUICKSAND_CACHE     =  56,
    BOWSERS_BIG_BLAST   =  57,
    TORPEDO_TARGETS     =  58,
    DESTRUCTION_DUET    =  59,
    DEEP_SEA_SALVAGE    =  60,
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
    MINI_GAME_PARK      =  93,
    MINI_GAME_RULES_2   =  95,
    MINI_GAME_RULES     =  96,
    TITLE_SCREEN        =  98,
    BATTLE_GAME_RESULTS = 111,
    MINI_GAME_RESULTS   = 112
}

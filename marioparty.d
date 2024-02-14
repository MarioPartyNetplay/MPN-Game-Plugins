module me.timz.n64.marioparty;

import me.timz.n64.plugin;
import std.algorithm;
import std.random;
import std.range;
import std.json;
import std.traits;
import std.stdio;
import std.conv;

enum PanelColor : ubyte {
    CLEAR = 0,
    BLUE  = 1,
    RED   = 2,
    GREEN = 4
}

enum Character : ubyte {
    MARIO   = 0,
    LUIGI   = 1,
    PEACH   = 2,
    YOSHI   = 3,
    WARIO   = 4,
    DK      = 5,
    WALUIGI = 6,
    DAISY   = 7
}

class MarioParty(ConfigType, StateType, MemoryType) : Game!(ConfigType, StateType) {
    alias typeof(MemoryType.currentScene) Scene;
    alias typeof(MemoryType.players.front) PlayerData;
    alias typeof(StateType.players.front) PlayerState;

    class Player {
        const uint index;
        PlayerData* data;
        PlayerState state;

        this(uint index, ref PlayerData data) {
            this.index = index;
            this.data = &data;
        }

        @property bool isCPU() const {
            return data.flags & 0b00000001;
        }

        bool isAheadOf(const Player o) const {
            if (data.stars == o.data.stars) {
                return data.coins > o.data.coins;
            } else {
                return data.stars > o.data.stars;
            }
        }
    }

    MemoryType* data;
    Player[] players;
    int[Character.max+1] teams = [1, 1, 0, 0, 0, 0, 0, 0];

    this(string name, string hash) {
        super(name, hash);

        data = cast(MemoryType*)memory.ptr;
        players = iota(4).map!(i => new Player(i, data.players[i])).array;
    }

    override void loadConfig() {
        super.loadConfig();

        teams.each!((c, ref t) => t = config.teams.require(cast(Character)c, t));
    }

    override void loadState() {
        super.loadState();

        players.each!(p => p.state = state.players[p.index]);
    }

    @property Player currentPlayer() {
        return data.currentPlayerIndex < 4 ? players[data.currentPlayerIndex] : null;
    }

    abstract bool lockTeams() const;
    abstract bool disableTeams() const;
    abstract bool isBoardScene(Scene scene) const;
    abstract bool isScoreScene(Scene scene) const;
    bool isBoardScene() const { return isBoardScene(data.currentScene); }
    bool isScoreScene() const { return isScoreScene(data.currentScene); }

    auto team(const Player p) const {
        return teams[p.data.character];
    }

    auto teammates(const Player p) {
        return players.filter!(t => p && t !is p && team(t) == team(p));
    }

    bool isIn4thPlace(const Player p) const {
        return p && players.filter!(o => o !is p).all!(o => o.isAheadOf(p));
    }

    bool isInLastPlace(const Player p) const {
        return p && !players.filter!(o => o !is p).any!(o => p.isAheadOf(o));
    }

    override void onStart() {
        super.onStart();

        data.currentScene.onWrite((ref Scene scene) {
            if (scene == data.currentScene) return;

            //info("Scene: ", scene);
        });

        static if (is(typeof(data.randomByteRoutine))) {
            data.randomByteRoutine.addr.onExec({
                gpr.v0 = random.uniform!ubyte;
            });
        }

        if (config.teamMode) {
            players.each!((p) {
                p.data.coins.onWrite((ref ushort coins) {
                    if (!isScoreScene()) return;
                    if (lockTeams()) {
                        coins = p.data.coins;
                    } if (!disableTeams()) {
                        teammates(p).each!((t) {
                            t.data.coins = coins;
                            t.data.maxCoins = max(t.data.maxCoins, coins);
                        });
                    }
                });
                p.data.stars.onWrite((ref typeof(p.data.stars) stars) {
                    if (!isScoreScene()) return;
                    if (lockTeams()) {
                        stars = p.data.stars;
                    } if (!disableTeams()) {
                        teammates(p).each!((t) {
                            t.data.stars = stars;
                        });
                    }
                });
                /*
                p.data.color.onWrite((ref PanelColor color) {
                    if (!isBoardScene()) return;
                    if (color == PanelColor.CLEAR) return;
                    auto t = teammates(p).find!(t => t.index < p.index);
                    if (!t.empty) {
                        color = t.front.data.color;
                    }
                });
                */
                p.data.flags.onWrite((ref ubyte flags) {
                    if (!isBoardScene()) return;
                    if (p.data.flags == flags) return;
                    p.data.flags = flags;
                });
                p.data.controller.onWrite((ref ubyte controller) {
                    if (!isBoardScene()) return;
                    if (p.data.controller == controller) return;
                    p.data.controller = controller;
                });
            });

            /*
            static if (is(typeof(data.playerPanels)) && is(typeof(data.drawPlayerColor))) {
                data.drawPlayerColor.addr.onExec({
                    if (!isBoardScene()) return;
                    if (gpr.a1 == PanelColor.CLEAR) return;
                    auto p = players[gpr.a0];
                    auto t = teammates(p).find!(t => t.index < p.index);
                    if (!t.empty) {
                        gpr.a1 = data.playerPanels[t.front.index].color;
                    }
                });
            }
            */

            static if (is(typeof(data.playerPanels)) && is(typeof(data.determineTeams))) {
                data.determineTeams.addr.onExec({
                    if (!isBoardScene()) return;

                    auto allTeamsSplit = players.all!(p => teammates(p).any!(t =>
                      data.playerPanels[t.index].color != data.playerPanels[p.index].color));
                      
                    if (!allTeamsSplit) return;
                    
                    players.each!((i, p) {
                        data.playerPanels[i].color = (team(p) == team(players[0]) ? PanelColor.BLUE : PanelColor.RED);
                    });
                });
            }

            data.currentPlayerIndex.onWrite((ref typeof(data.currentPlayerIndex) index) {
                if (!isBoardScene()) return;
                data.currentPlayerIndex = index;
                teammates(currentPlayer).each!((t) {
                    t.data.coins = currentPlayer.data.coins;
                    t.data.stars = currentPlayer.data.stars;
                });
            });

            static if (is(typeof(data.booRoutinePtr))) {
                Ptr!Instruction previousRoutinePtr = 0;
                auto booRoutinePtrHandler = delegate void(ref Ptr!Instruction routinePtr) {
                    if (!routinePtr || routinePtr == previousRoutinePtr || !isBoardScene()) return;
                    if (previousRoutinePtr) {
                        executeHandlers.remove(previousRoutinePtr);
                    }
                    routinePtr.onExec({
                        teammates(currentPlayer).each!((t) {
                            t.data.coins = 0;
                            t.data.stars = 0;
                        });
                        gpr.ra.onExecOnce({
                            teammates(currentPlayer).each!((t) {
                                t.data.coins = currentPlayer.data.coins;
                                t.data.stars = currentPlayer.data.stars;
                            });
                        });
                    });
                    previousRoutinePtr = routinePtr;
                };
                data.booRoutinePtr.onWrite(booRoutinePtrHandler);
                data.currentScene.onWrite((ref Scene scene) {
                    if (!isBoardScene(scene) && previousRoutinePtr) {
                        executeHandlers.remove(previousRoutinePtr);
                        previousRoutinePtr = 0;
                    }
                });
                booRoutinePtrHandler(data.booRoutinePtr);
            }
        }

        static if (is(typeof(data.numberOfRolls))) {
            if (config.lastPlaceDoubleRoll) {
                data.numberOfRolls.onRead((ref ubyte rolls) {
                    if (!isBoardScene()) return;
                    if (data.currentTurn <= 1) return;
                    if (isInLastPlace(currentPlayer) && rolls < 2) {
                        rolls = 2;
                    }
                });
            }
        }
    }
}

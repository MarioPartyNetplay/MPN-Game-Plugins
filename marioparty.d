module me.timz.n64.marioparty;

import me.timz.n64.plugin;
import std.algorithm;
import std.random;
import std.range;
import std.json;
import std.traits;
import std.stdio;

enum Color : ubyte {
    CLEAR = 0,
    BLUE  = 1,
    RED   = 2,
    GREEN = 4
}

class MarioPartyConfig {
    bool alwaysDuel = true;
    bool lastPlaceDoubleRoll = true;
    bool teams = true;
}

class MarioParty(ConfigType, MemoryType) : Game!ConfigType {
    alias typeof(MemoryType.currentScene) Scene;
    alias typeof(MemoryType.players.front) PlayerData;
    alias typeof(ConfigType.players.front) PlayerConfig;

    class Player {
        const uint index;
        PlayerData* data;
        PlayerConfig config;

        this(uint index, ref PlayerData data, PlayerConfig config) {
            this.index = index;
            this.data = &data;
            this.config = config;
        }
        @property bool isCPU() const { return data.flags & 1; }
        bool isAheadOf(const Player o) const { return data.stars > o.data.stars || data.stars == o.data.stars && data.coins > o.data.coins; }
    }

    MemoryType* data;
    Player[] players;

    this(string name, string hash) {
        super(name, hash);

        data = cast(MemoryType*)memory.ptr;

        foreach (i; 0..4) {
            players ~= new Player(i, data.players[i], config.players[i]);
        }
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

    void updateTeams() {
        players.dup.sort!(
            (a, b) => (a.isCPU ? 4 : a.data.controller) < (b.isCPU ? 4 : b.data.controller),
            SwapStrategy.stable
        ).each!((i, p) { p.config = config.players[i]; });
    }

    auto teammates(const Player p) {
        return players.filter!(t => p && t !is p && t.config.team == p.config.team);
    }

    bool isIn4thPlace(const Player p) const {
        return p && players.filter!(o => o !is p).all!(o => o.isAheadOf(p));
    }

    bool isInLastPlace(const Player p) const {
        return p && !players.filter!(o => o !is p).any!(o => p.isAheadOf(o));
    }

    override void onStart() {
        super.onStart();

        /*
        data.currentScene.onWrite((ref Scene scene) {
            if (scene != data.currentScene) {
                writeln("Scene: ", scene);
            }
        });
        */

        static if (is(typeof(data.randomByteRoutine))) {
            data.randomByteRoutine.addr.onExec({
                gpr.v0 = random.uniform!ubyte;
            });
        }

        if (config.teams) {
            if (isBoardScene()) {
                updateTeams();
            }

            data.currentScene.onWrite((ref Scene scene) {
                if (isBoardScene(scene)) {
                    updateTeams();
                }
            });
            
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
                p.data.color.onWrite((ref Color color) {
                    if (!isBoardScene()) return;
                    if (color == Color.CLEAR) return;
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
                    updateTeams();
                });
                p.data.controller.onWrite((ref ubyte controller) {
                    if (!isBoardScene()) return;
                    if (p.data.controller == controller) return;
                    p.data.controller = controller;
                    updateTeams();
                });
            });

            /*
            static if (is(typeof(data.playerCards)) && is(typeof(data.drawPlayerColor))) {
                data.drawPlayerColor.addr.onExec({
                    if (!isBoardScene()) return;
                    if (gpr.a1 == Color.CLEAR) return;
                    auto p = players[gpr.a0];
                    auto t = teammates(p).find!(t => t.index < p.index);
                    if (!t.empty) {
                        gpr.a1 = data.playerCards[t.front.index].color;
                    }
                });
            }
            */

            static if (is(typeof(data.playerCards)) && is(typeof(data.determineTeams))) {
                data.determineTeams.addr.onExec({
                    if (!isBoardScene()) return;

                    auto splitTeams = players.all!(p => teammates(p).any!(t =>
                      data.playerCards[t.index].color != data.playerCards[p.index].color));
                      
                    if (splitTeams) {
                        foreach(i; 0..4) {
                            data.playerCards[i].color = cast(ubyte)players[i].config.team;
                        }
                    }
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

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
        bool isAheadOf(Player o) const { return data.stars > o.data.stars || data.stars == o.data.stars && data.coins > o.data.coins; }
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
        return players.filter!(t => p && t.config.team == p.config.team && t !is p);
    }

    bool isInLastPlace(const Player p) {
        return p && !players.canFind!(o => p.isAheadOf(o));
    }

    override void onStart() {
        super.onStart();

        allocConsole();

        data.currentScene.onWrite((ref Scene scene) {
            if (scene != data.currentScene) {
                writeln("Scene: ", scene);
            }
        });

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
                    teammates(p).each!((t) {
                        t.data.coins = coins;
                        t.data.stars = p.data.stars;
                    });
                });
                p.data.stars.onWrite((ref typeof(p.data.stars) stars) {
                    if (!isScoreScene()) return;
                    teammates(p).each!((t) {
                        t.data.coins = p.data.coins;
                        t.data.stars = stars;
                    });
                });
                p.data.color.onWrite((ref Color color) {
                    if (!isBoardScene()) return;
                    if (color == Color.CLEAR) return;
                    auto t = teammates(p).find!(t => t.index < p.index);
                    if (!t.empty) {
                        color = t.front.data.color;
                    } else if (color == Color.GREEN) {
                        color = (random.uniform01() < 0.75 ? Color.BLUE : Color.RED);
                    }
                });
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

        static if (is(typeof(numberOfRolls))) {
            if (config.lastPlaceDoubleRoll) {
                numberOfRolls.onRead((ref ubyte rolls) {
                    if (!isBoardScene()) return;
                    if (isInLastPlace(currentPlayer) && rolls < 2) {
                        rolls = 2;
                    }
                });
            }
        }
    }
}

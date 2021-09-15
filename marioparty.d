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
    bool altBonus = true;
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
        @property bool isCPU() const { return flags & 1; }
        bool isAheadOf(Player o) const { return stars > o.stars || stars == o.stars && coins > o.coins; }

        alias data this;
    }

    MemoryType* data;
    Player[] players;

    alias data this;

    this(string name, string hash) {
        super(name, hash);

        data = cast(MemoryType*)memory.ptr;

        foreach (i; 0..4) {
            players ~= new Player(i, data.players[i], config.players[i]);
        }
    }

    @property Player currentPlayer() {
        return currentPlayerIndex < 4 ? players[currentPlayerIndex] : null;
    }

    abstract bool isBoardScene(Scene scene) const;
    abstract bool isScoreScene(Scene scene) const;
    bool isBoardScene() const { return isBoardScene(currentScene); }
    bool isScoreScene() const { return isScoreScene(currentScene); }

    void updateTeams() {
        players.dup.sort!(
            (a, b) => (a.isCPU ? 4 : a.controller) < (b.isCPU ? 4 : b.controller),
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

        //allocConsole();

        currentScene.onWrite((ref Scene scene) {
            if (scene != currentScene) {
                writeln("Scene: ", scene);
            }
        });

        static if (is(typeof(randomByteRoutine))) {
            randomByteRoutine.addr.onExec({
                gpr.v0 = random.uniform!ubyte;
            });
        }

        if (config.teams) {
            if (isBoardScene()) {
                updateTeams();
            }

            currentScene.onWrite((ref Scene scene) {
                if (isBoardScene(scene)) {
                    updateTeams();
                }
            });
            
            players.each!((p) {
                p.coins.onWrite((ref ushort coins) {
                    if (!isScoreScene()) return;
                    teammates(p).each!((t) {
                        t.coins = coins;
                        t.stars = p.stars;
                    });
                });
                p.stars.onWrite((ref typeof(p.stars) stars) {
                    if (!isScoreScene()) return;
                    teammates(p).each!((t) {
                        t.coins = p.coins;
                        t.stars = stars;
                    });
                });
                p.color.onWrite((ref Color color) {
                    if (!isBoardScene()) return;
                    if (color == Color.CLEAR) return;
                    auto t = teammates(p).find!(t => t.index < p.index);
                    if (!t.empty) {
                        color = t.front.color;
                    } else if (color == Color.GREEN) {
                        color = (random.uniform01() < 0.75 ? Color.BLUE : Color.RED);
                    }
                });
                p.flags.onWrite((ref ubyte flags) {
                    if (!isBoardScene()) return;
                    if (p.flags == flags) return;
                    p.flags = flags;
                    updateTeams();
                });
                p.controller.onWrite((ref ubyte controller) {
                    if (!isBoardScene()) return;
                    if (p.controller == controller) return;
                    p.controller = controller;
                    updateTeams();
                });
            });
            
            currentPlayerIndex.onWrite((ref typeof(currentPlayerIndex) index) {
                if (!isBoardScene()) return;
                currentPlayerIndex = index;
                teammates(currentPlayer).each!((t) {
                    t.coins = currentPlayer.coins;
                    t.stars = currentPlayer.stars;
                });
            });

            static if (is(typeof(booRoutinePtr))) {
                Ptr!Instruction previousRoutinePtr = 0;
                auto booRoutinePtrHandler = delegate void(ref Ptr!Instruction routinePtr) {
                    if (!routinePtr || routinePtr == previousRoutinePtr || !isBoardScene()) return;
                    if (previousRoutinePtr) {
                        executeHandlers.remove(previousRoutinePtr);
                    }
                    routinePtr.onExec({
                        teammates(currentPlayer).each!((t) {
                            t.coins = 0;
                            t.stars = 0;
                        });
                        gpr.ra.onExecOnce({
                            teammates(currentPlayer).each!((t) {
                                t.coins = currentPlayer.coins;
                                t.stars = currentPlayer.stars;
                            });
                        });
                    });
                    previousRoutinePtr = routinePtr;
                };
                booRoutinePtr.onWrite(booRoutinePtrHandler);
                currentScene.onWrite((ref Scene scene) {
                    if (!isBoardScene(scene) && previousRoutinePtr) {
                        executeHandlers.remove(previousRoutinePtr);
                        previousRoutinePtr = 0;
                    }
                });
                booRoutinePtrHandler(booRoutinePtr);
            }
        }

        if (config.altBonus) {
            players.each!((p) {
                p.itemSpaces.onWrite((ref ubyte itemSpaces) { if (!isBoardScene()) return; p.gameCoins = itemSpaces; });
                p.redSpaces.onWrite( (ref ubyte redSpaces)  { if (!isBoardScene()) return; p.maxCoins  = redSpaces; });
                p.gameCoins.onWrite( (ref ushort gameCoins) { if (!isScoreScene()) return; gameCoins   = p.itemSpaces; });
                p.maxCoins.onWrite(  (ref ushort maxCoins)  { if (!isScoreScene()) return; maxCoins    = p.redSpaces; });
            });
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

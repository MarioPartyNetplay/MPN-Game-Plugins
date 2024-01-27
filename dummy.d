module me.timz.n64.dummy;

import me.timz.n64.plugin;
import std.string;

class Config {

}

class Dummy : Game!Config {
    this(string name, string hash) {
        super(name, hash);
    }

    override void loadConfig() { }
    override void saveConfig() { }
}

shared static this() {
    name = "Dummy Execution".toStringz;
    pluginFactory = (name, hash) => new Dummy(name, hash);
}

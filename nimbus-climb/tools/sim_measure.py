# tools/sim_measure.py: run tools/sim_measure.lua on the real battle modules (read-only, the feel-balance fit).
# From the repo root (nimbus-climb), one run at a time:
#   py -3.12 tools/sim_measure.py "raid lava_golem Max 1 48 0 off;raid lava_golem Max 1 48 8 off"
# Each cell is: raid <boss> <tier> <players> <seeds> <standoff> <on|off>  (on|off = the real cast).
import sys
import time

import lupa.luajit21 as L

args = sys.argv[1]
script = sys.argv[2] if len(sys.argv) > 2 else "tools/sim_measure.lua"
rt = L.LuaRuntime()
rt.execute("SIM_BATTLE_LIBRARY = true")
sim = rt.execute(open("tools/sim_battle.lua", encoding="utf-8").read())
g = rt.globals()
g.SIM = sim
g.MEASURE_ARGS = args
t0 = time.time()
print(rt.execute(open(script, encoding="utf-8").read()))
print("(%.0f s)" % (time.time() - t0))

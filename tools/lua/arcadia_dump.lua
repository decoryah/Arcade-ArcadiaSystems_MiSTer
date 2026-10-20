-- Arcadia Systems: MAME 0.289's side of the comparison with the simulation (sim/run_sys.sh).
--   DUMPFRAMES=<f,f,...>  frames to capture, DUMPDIR=<dir>: snap_<f>.png (MAME's visible area) and chip_<f>.bin (the 512 KB of
--                         chip RAM, big-endian words)
--   SCHED=<file>          scripted inputs, the simulation's -sched file: lines "<frame> <signal> <0|1>"
--   SNAPEVERY=<k>         also capture every k-th frame
-- Frames count from power-on (MAME's frame_number). The simulation counts from the 68000 leaving reset, which is the same start.
local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local scr  = mach.screens[":screen"]
local FR, LAST = {}, 0
for n in string.gmatch(os.getenv("DUMPFRAMES") or "", "%d+") do FR[tonumber(n)] = true; if tonumber(n) > LAST then LAST = tonumber(n) end end
local EVERY = tonumber(os.getenv("SNAPEVERY") or "0")
local LASTF = tonumber(os.getenv("LASTFRAME") or "0")
if LASTF > LAST then LAST = LASTF end
local DIR = os.getenv("DUMPDIR") or "."

-- the simulation's signal names -> MAME's input fields
local NAMES = {
  coin1 = "Coin 1", coin2 = "Coin 2", start1 = "1 Player Start", start2 = "2 Players Start", service = "Service Mode",
  b1 = "P1 Button 1", b2 = "P1 Button 2", up = "P1 Up", down = "P1 Down", left = "P1 Left", right = "P1 Right",
  p2b1 = "P2 Button 1", p2b2 = "P2 Button 2", p2up = "P2 Up", p2down = "P2 Down", p2left = "P2 Left", p2right = "P2 Right",
}
local FIELDS = {}
for _, port in pairs(mach.ioport.ports) do
  for name, f in pairs(port.fields) do FIELDS[name] = f end
end

local EV = {}
local sf = os.getenv("SCHED")
if sf and sf ~= "" then
  for line in io.lines(sf) do
    local fr, sig, v = string.match(line, "^(%d+)%s+(%S+)%s+(%d+)")
    if fr then EV[#EV + 1] = { tonumber(fr), sig, tonumber(v) } end
  end
end
local state = {}
local ei = 1

local function be16(v) return string.char((v >> 8) & 0xff, v & 0xff) end
local function dump(f)
  local t = {}
  for a = 0, 0x7fffe, 2 do t[#t + 1] = be16(sp:read_u16(a)) end
  local fh = io.open(string.format("%s/chip_%d.bin", DIR, f), "wb"); fh:write(table.concat(t)); fh:close()
  scr:snapshot(string.format("%s/snap_%d.png", DIR, f))
end

emu.register_frame_done(function()
  local f = scr:frame_number()
  while ei <= #EV and EV[ei][1] <= f do state[EV[ei][2]] = EV[ei][3]; ei = ei + 1 end
  for sig, name in pairs(NAMES) do
    local fld = FIELDS[name]
    if fld then fld:set_value(state[sig] or 0) end
  end
  if FR[f] or (EVERY > 0 and f % EVERY == 0) then dump(f) end
  if f >= LAST then mach:exit() end
end)

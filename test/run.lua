-- Run from the add-on directory: lua test/run.lua
local now, gamepad, l2, blocking, combat = 0, true, 0, false, false
local stickX = 0
local events, updates, messages = {}, {}, {}
EVENT_ADD_ON_LOADED, EVENT_PLAYER_ACTIVATED, EVENT_PLAYER_DEACTIVATED = 1, 2, 3
EVENT_GAMEPAD_PREFERRED_MODE_CHANGED, EVENT_CONTROLLER_DISCONNECTED, EVENT_CONTROLLER_CONNECTED = 4, 5, 6
EVENT_PLAYER_COMBAT_STATE, EVENT_SCREENSHOT_SAVED = 7, 8
SCENE_FRAGMENT_HIDDEN = 'hidden'
EVENT_MANAGER = {
    RegisterForEvent = function(_, _, event, callback) events[event] = callback end,
    UnregisterForEvent = function(_, _, event) events[event] = nil end,
    RegisterForUpdate = function(_, name, _, callback) updates[name] = callback end,
    UnregisterForUpdate = function(_, name) updates[name] = nil end,
}
function IsUnitInCombat(unit) assert(unit == "player"); return combat end
function GetGameTimeSeconds() return now end
function IsInGamepadPreferredMode() return gamepad end
function GetGamepadLeftTriggerMagnitude() return l2 end
GAMEPAD_INCLUDE_DEADZONE = true
-- The reading the add-on asks for is the deadzone-corrected one, so a resting stick is 0.
function GetGamepadLeftStickX(includeDeadzone)
    assert(includeDeadzone == GAMEPAD_INCLUDE_DEADZONE, 'stick read without the deadzone applied')
    return stickX
end
function IsBlockActive() return blocking end
function ZO_CreateStringId(id, value) _G[id] = id; messages[id] = value end
function SafeAddString(id, value) messages[id] = value end
function GetString(id) assert(messages[id], 'missing string: '..tostring(id)); return messages[id] end
function GetCVar() return 'ja' end
function d() end
SLASH_COMMANDS = {}
ZO_SavedVars = { NewAccountWide = function(_, _, _, _, defaults)
    local copy = {}; for k,v in pairs(defaults) do copy[k] = v end; return copy
end }
local guiHidden = false
function SetGuiHidden(_, hidden) guiHidden = hidden end
ZO_ActionLayerFragment = {New = function(_, name)
    return {name = name, RegisterCallback = function(self, _, cb) self.callback = cb end}
end}
local hud = {fragments = {}}
function hud:AddFragment(f) self.fragments[f] = true end
function hud:RemoveFragment(f)
    if self.fragments[f] then self.fragments[f] = nil; f.callback(nil, SCENE_FRAGMENT_HIDDEN) end
end
local shot = {callbackRegistry = {StateChange = {'original'}}, fragments = {}}
shot.AddFragment = hud.AddFragment
shot.RemoveFragment = hud.RemoveFragment
SCENE_MANAGER = {hudName = 'hud', showing = 'hud'}
function SCENE_MANAGER:GetScene(name) if name == 'hud' then return hud else return shot end end
function SCENE_MANAGER:GetHUDSceneName() return self.hudName end
function SCENE_MANAGER:IsShowing(name) return self.showing == name end
function SCENE_MANAGER:SetHUDScene(name)
    self.hudName = name
    assert(shot.callbackRegistry.StateChange[1] == 'original', 'client callbacks altered')
    if self.fail then error('simulated scene failure') end
    -- Shared fragments must stay active during the transition, otherwise a
    -- HIDDEN callback would discard the consumed Left release.
    for f in pairs(hud.fragments) do
        if not shot.fragments[f] then f.callback(nil, SCENE_FRAGMENT_HIDDEN) end
    end
    self.showing = name
end
function SCENE_MANAGER:RestoreHUDScene() self.hudName = 'hud'; self.showing = 'hud' end
SCREENSHOT_MODE_GAMEPAD = {}
local shots, shotFails = 0, false
function TakeScreenshot()
    if shotFails then error('private function') end
    shots = shots + 1
end
-- A stand-in for the library: enough of it to build the panel and press its rows.
LibHarvensAddonSettings = {
    ST_LABEL = 'label', ST_SECTION = 'section', ST_CHECKBOX = 'checkbox',
    ST_DROPDOWN = 'dropdown', ST_BUTTON = 'button',
}
function LibHarvensAddonSettings:AddAddon()
    local panel = {rows = {}, updates = 0}
    function panel:AddSetting(row) self.rows[#self.rows + 1] = row end
    function panel:UpdateControls() self.updates = self.updates + 1 end
    return panel
end
dofile('lang/strings.lua'); dofile('lang/ja.lua'); dofile('Main.lua'); dofile('Settings.lua')
local a = PBS_SCREENSHOT_MODE_SHORTCUT
local count = 0
local weaponDowns, weaponUps = 0, 0
local function test(name, fn) fn(); count = count + 1; print('PASS '..name) end
local function tick()
    local snapshot = {}; for k,v in pairs(updates) do snapshot[k] = v end
    for k,v in pairs(snapshot) do if updates[k] == v then v() end end
end
-- Model binding dispatch: a true result consumes input before the lower action.
-- Actual ESO inherited-binding routing still requires an in-game check.
local function leftDown()
    local consumed = a:OnTriggerDown()
    if not consumed then weaponDowns = weaponDowns + 1 end
    return consumed
end
local function leftUp()
    local consumed = a:OnTriggerUp()
    if not consumed then weaponUps = weaponUps + 1 end
    return consumed
end
local function reset()
    a:Stop(); SCENE_MANAGER:RestoreHUDScene(); SCENE_MANAGER.fail = false
    a.sv.enabled = true; a.sv.mode = 'auto'; a.error = nil
    gamepad = true; combat = false; now = 0; l2 = 0; blocking = false; stickX = 0
    a.sv.quickShot = false; a.sv.quickShotHoldMs = a.DEFAULTS.quickShotHoldMs
    shots = 0; shotFails = false
    weaponDowns = 0; weaponUps = 0; a:Start()
end
local function chord()
    l2 = 1; assert(leftDown()); assert(leftUp()); tick()
end
events[EVENT_ADD_ON_LOADED](nil, a.name)
events[EVENT_PLAYER_ACTIVATED]()
test('manifest initialization and localized commands', function()
    for _, command in ipairs({'help', 'status', 'mode scene', 'mode invalid', 'off', 'on', 'reset', 'unknown',
        'quick on', 'quick off', 'quick maybe', 'hold 3', 'hold 2', 'hold'}) do a:Command(command) end
end)
test('first chord works without an L2 binding event or polling tick', function()
    reset(); assert(a.triggerLayerAdded); l2 = 1
    assert(leftDown()); assert(not a:InScreenshotMode())
    assert(leftUp()); assert(not a:InScreenshotMode()); assert(a.triggerLayerAdded)
    tick(); assert(a:InScreenshotMode()); assert(weaponDowns == 0 and weaponUps == 0)
end)
test('plain Left passes down and up to weapon binding', function()
    reset(); assert(not leftDown()); assert(not leftUp()); tick()
    assert(weaponDowns == 1 and weaponUps == 1); assert(not a:InScreenshotMode())
end)
test('L2 alone does not fire', function() reset(); l2 = 1; tick(); assert(not a:InScreenshotMode()) end)
test('L2 release before Left still consumes weapon release', function()
    reset(); l2 = 1; assert(leftDown()); l2 = 0; assert(leftUp()); tick()
    assert(a:InScreenshotMode()); assert(weaponDowns == 0 and weaponUps == 0)
end)
test('L2 pressed after unmodified Left does not split input ownership', function()
    reset(); assert(not leftDown()); l2 = 1; assert(not leftUp()); tick()
    assert(not a:InScreenshotMode()); assert(weaponDowns == 1 and weaponUps == 1)
end)
test('repeat events schedule only one transition', function()
    reset(); local before = a.entries or 0; l2 = 1
    assert(leftDown()); assert(leftDown()); assert(leftUp()); tick(); tick()
    assert(a.entries == before + 1)
end)
test('missing Left Up does not prevent activation or leak later Up', function()
    reset(); l2 = 1; assert(leftDown()); tick()
    assert(a:InScreenshotMode()); assert(a.triggerLayerAdded)
    assert(shot.fragments[a.triggerFragment]); assert(leftUp())
    assert(weaponDowns == 0 and weaponUps == 0)
end)
test('long L2 hold can still start a fresh chord', function()
    reset(); l2 = 1; now = 60; chord(); assert(a:InScreenshotMode())
end)
test('menu opening before deferred transition cancels activation', function()
    reset(); l2 = 1; leftDown(); leftUp(); SCENE_MANAGER.showing = 'menu'; tick()
    assert(not a:InScreenshotMode()); assert(not guiHidden)
end)
test('native failure rolls back before fallback and next chord restores UI', function()
    reset(); SCENE_MANAGER.fail = true; chord(); assert(guiHidden); assert(a:OnHud())
    chord(); assert(not guiHidden); assert(weaponDowns == 0 and weaponUps == 0)
end)
test('scene-only failure does not hide UI', function()
    reset(); a.sv.mode = 'scene'; SCENE_MANAGER.fail = true; chord(); assert(not guiHidden)
end)
test('loading and disconnect cancel pending transition and restore GUI', function()
    for _, event in ipairs({EVENT_PLAYER_DEACTIVATED, EVENT_CONTROLLER_DISCONNECTED}) do
        reset(); l2 = 1; leftDown(); leftUp(); events[event](); tick()
        assert(not a:InScreenshotMode()); assert(not a.triggerLayerAdded)
        reset(); a.sv.mode = 'gui'; chord(); assert(guiHidden); events[event]()
        assert(not guiHidden); assert(not a.triggerLayerAdded); assert(not a.watching)
    end
end)
test('keyboard mode removes input layer and cancels pending transition', function()
    reset(); l2 = 1; leftDown(); leftUp(); gamepad = false
    events[EVENT_GAMEPAD_PREFERRED_MODE_CHANGED](); tick()
    assert(not a.triggerLayerAdded); assert(not a:InScreenshotMode())
end)
test('fragment initialization can retry', function()
    reset(); a:Stop(); a.fragmentsBuilt = false
    local original = SCENE_MANAGER; SCENE_MANAGER = nil; assert(not a:EnsureFragments())
    SCENE_MANAGER = original; a:Start(); assert(a.triggerLayerAdded); assert(not a.error)
end)
test('missing analog API leaves normal Left available', function()
    reset(); local original = GetGamepadLeftTriggerMagnitude; GetGamepadLeftTriggerMagnitude = nil
    assert(not leftDown()); assert(not leftUp()); tick(); assert(not a:InScreenshotMode())
    GetGamepadLeftTriggerMagnitude = original
end)
test('L2 and block bindings are never intercepted', function()
    local file = assert(io.open('Bindings.xml')); local xml = file:read('*a'); file:close()
    assert(not xml:find('inheritsBindFrom="UI_SHORTCUT_LEFT_TRIGGER"', 1, true))
    assert(not xml:find('SPECIAL_MOVE_BLOCK', 1, true))
    assert(not xml:find('PBSSCREENSHOTMODE_MODIFIER', 1, true))
    local actions = 0; for _ in xml:gmatch('<Action ') do actions = actions + 1 end
    assert(actions == 2); assert(a.OnModifierDown == nil and a.OnModifierUp == nil)
end)
test('active block is read when analog always returns zero', function()
    reset(); blocking = true; assert(leftDown()); tick(); assert(a:InScreenshotMode()); assert(leftUp())
    assert(blocking, 'add-on changed block state')
end)
test('active block works when analog API is missing', function()
    reset(); local original = GetGamepadLeftTriggerMagnitude; GetGamepadLeftTriggerMagnitude = nil
    blocking = true; assert(leftDown()); tick(); assert(a:InScreenshotMode())
    GetGamepadLeftTriggerMagnitude = original
end)
test('analog error does not break block detection or diagnostics', function()
    reset(); local original = GetGamepadLeftTriggerMagnitude
    GetGamepadLeftTriggerMagnitude = function() error('private API') end
    blocking = true; assert(leftDown()); tick(); assert(a:InScreenshotMode()); a:PrintStatus()
    GetGamepadLeftTriggerMagnitude = original
end)
test('ended block does not latch for next plain Left', function()
    reset(); blocking = true; assert(a:IsL2Held()); blocking = false
    assert(not leftDown()); assert(not leftUp())
end)
test('block release does not leak the already consumed Left Up', function()
    reset(); blocking = true; assert(leftDown()); blocking = false; assert(leftUp()); tick()
    assert(a:InScreenshotMode()); assert(weaponDowns == 0 and weaponUps == 0)
end)
test('long block hold does not expire modifier', function()
    reset(); blocking = true; now = 60; assert(leftDown()); tick(); assert(a:InScreenshotMode())
end)
test('UI fallback consumes release and fires once with missing Up', function()
    reset(); a.sv.mode = 'gui'; blocking = true; assert(leftDown()); tick(); assert(guiHidden)
    assert(leftDown()); tick(); assert(guiHidden); assert(leftUp())
    assert(weaponDowns == 0 and weaponUps == 0)
end)
local sheathed, toggleCalls = false, 0
function ArePlayerWeaponsSheathed() return sheathed end
function TogglePlayerWield() toggleCalls = toggleCalls + 1; sheathed = not sheathed end
local function screenshotWithWeapon()
    reset(); chord(); l2 = 0; blocking = false; sheathed = false; toggleCalls = 0
end
test('screenshot sheathe uses native hold action inside blocking layer', function()
    local file = assert(io.open('Bindings.xml')); local xml = file:read('*a'); file:close()
    local layer = assert(xml:match('<Layer name="ScreenshotMode"(.-)</Layer>'))
    assert(layer:find('allowFallthrough="false"', 1, true))
    assert(layer:find('inheritsBindFrom="SHEATHE_WEAPON_TOGGLE"', 1, true))
    assert(layer:find(':OnScreenshotSheathe()', 1, true))
end)
test('screenshot sheathe stows weapon without leaving scene or changing UI', function()
    screenshotWithWeapon(); SetGuiHidden('ingame', true)
    assert(a:OnScreenshotSheathe()); assert(sheathed and toggleCalls == 1)
    assert(a:InScreenshotMode() and guiHidden)
    SetGuiHidden('ingame', false)
end)
test('holding again does not draw a sheathed weapon', function()
    screenshotWithWeapon(); a:OnScreenshotSheathe(); a:OnScreenshotSheathe()
    assert(sheathed and toggleCalls == 1)
end)
test('HUD or disabled add-on does not run screenshot sheathe', function()
    reset(); toggleCalls = 0; assert(not a:OnScreenshotSheathe()); assert(toggleCalls == 0)
    screenshotWithWeapon(); a.sv.enabled = false
    assert(not a:OnScreenshotSheathe()); assert(toggleCalls == 0)
end)
test('release block before sheathing', function()
    screenshotWithWeapon(); blocking = true; assert(a:OnScreenshotSheathe()); assert(toggleCalls == 0)
    blocking = false; assert(a:OnScreenshotSheathe()); assert(sheathed)
end)
test('missing or denied sheathe API does not break screenshot mode', function()
    screenshotWithWeapon(); local original = TogglePlayerWield; TogglePlayerWield = nil
    assert(a:OnScreenshotSheathe()); assert(a:InScreenshotMode())
    TogglePlayerWield = function() error('denied') end
    assert(a:OnScreenshotSheathe()); assert(a:InScreenshotMode())
    TogglePlayerWield = original
end)
test('combat disables shortcut layer and rejects Down before combat event', function()
 reset(); l2 = 1; combat = true; assert(not leftDown()); assert(not a.triggerLayerAdded)
 a:Start(); assert(not a.triggerLayerAdded); assert(not a:Fire())
end)
test('combat beginning cancels queued screenshot and resumes after combat', function()
 reset(); l2 = 1; leftDown(); combat = true; events[EVENT_PLAYER_COMBAT_STATE](nil, true); tick()
 assert(not a:InScreenshotMode()); assert(not a.triggerLayerAdded)
 combat = false; events[EVENT_PLAYER_COMBAT_STATE](nil, false); assert(a.triggerLayerAdded)
 chord(); assert(a:InScreenshotMode())
end)
test('deferred activation rechecks combat even before event dispatch', function()
 reset(); l2 = 1; leftDown(); combat = true; tick(); assert(not a:InScreenshotMode())
end)
test('combat blocks sheathe shortcut and restores fallback GUI', function()
 screenshotWithWeapon(); combat = true; assert(not a:OnScreenshotSheathe()); assert(toggleCalls == 0)
 reset(); a.sv.mode = 'gui'; chord(); assert(guiHidden)
 combat = true; events[EVENT_PLAYER_COMBAT_STATE](nil, true); assert(not guiHidden)
end)
test('analog stick left is handed back to the game, not read as the D-pad', function()
    reset(); l2 = 1; stickX = -1
    assert(not leftDown()); assert(not leftUp()); tick()
    assert(not a:InScreenshotMode()); assert(not guiHidden)
    assert(weaponDowns == 1 and weaponUps == 1)
end)
test('walking left and then letting go still leaves the chord working', function()
    reset(); l2 = 1; stickX = -1; assert(not leftDown()); assert(not leftUp())
    stickX = 0; chord(); assert(a:InScreenshotMode())
end)
test('a stick short of the threshold, or pushed the other way, does not block it', function()
    reset(); l2 = 1; stickX = -0.3; chord(); assert(a:InScreenshotMode())
    reset(); l2 = 1; stickX = 1; chord(); assert(a:InScreenshotMode())
end)
test('an unreadable stick is treated as centred', function()
    reset(); local original = GetGamepadLeftStickX
    GetGamepadLeftStickX = nil; l2 = 1; chord(); assert(a:InScreenshotMode())
    reset(); GetGamepadLeftStickX = function() error('private API') end
    l2 = 1; chord(); assert(a:InScreenshotMode()); a:PrintStatus()
    GetGamepadLeftStickX = original
end)
test('walking left in screenshot mode does not sheathe', function()
    screenshotWithWeapon(); stickX = -1
    assert(not a:OnScreenshotSheathe()); assert(toggleCalls == 0); assert(a:InScreenshotMode())
    stickX = 0; assert(a:OnScreenshotSheathe()); assert(sheathed and toggleCalls == 1)
end)
-- ---- quick shot ----------------------------------------------------------------------
local function quickChord() a.sv.quickShot = true; chord() end
local function advance(seconds) now = now + seconds; tick() end

test('quick shot hides the UI, takes the picture and puts the UI back', function()
    reset(); quickChord()
    assert(guiHidden); assert(not a:InScreenshotMode()); assert(shots == 0, 'shot before the UI was down')
    advance(0.2); assert(shots == 1); assert(guiHidden, 'UI came back in the same frame as the shot')
    advance(1); assert(not guiHidden); assert(not a:QuickShotRunning())
end)
test('the saved event brings the UI back before the hold runs out', function()
    reset(); a.sv.quickShotHoldMs = 5000; quickChord(); advance(0.2); assert(shots == 1)
    events[EVENT_SCREENSHOT_SAVED](nil, 'dir', 'shot.jpg'); advance(0.05)
    assert(not guiHidden); assert(tostring(a.lastShot):find('shot.jpg', 1, true))
end)
test('a second chord during a quick shot gives the UI straight back', function()
    reset(); quickChord(); assert(guiHidden)
    chord(); assert(not guiHidden); assert(not a:QuickShotRunning()); assert(shots == 0)
end)
test('quick shot ignores the mode setting and never opens the scene', function()
    reset(); a.sv.mode = 'scene'; quickChord()
    assert(guiHidden); assert(not a:InScreenshotMode())
    advance(0.2); advance(1); assert(not a:InScreenshotMode())
end)
test('a loading screen during a quick shot restores the UI', function()
    reset(); quickChord(); SCENE_MANAGER.showing = 'menu'; advance(0.2)
    assert(not guiHidden); assert(not a:QuickShotRunning()); assert(shots == 0)
    reset(); quickChord(); events[EVENT_PLAYER_DEACTIVATED]()
    assert(not guiHidden); assert(not a:QuickShotRunning())
end)
test('a refused or missing TakeScreenshot still restores the UI', function()
    reset(); shotFails = true; quickChord(); advance(0.2); advance(1)
    assert(not guiHidden); assert(tostring(a.lastShot):find('refused', 1, true))
    reset(); local original = TakeScreenshot; TakeScreenshot = nil
    quickChord(); advance(0.2); advance(1)
    assert(not guiHidden); assert(a.lastShot == 'TakeScreenshot unavailable')
    TakeScreenshot = original
end)
test('the hold length is what decides when the UI comes back', function()
    reset(); a.sv.quickShotHoldMs = 3000; quickChord(); advance(0.2); advance(1)
    assert(guiHidden, 'came back before the configured hold'); advance(2.1); assert(not guiHidden)
end)
test('quick shot off leaves the old behaviour alone', function()
    reset(); chord(); assert(a:InScreenshotMode()); assert(shots == 0)
end)

-- ---- settings panel -------------------------------------------------------------------
a:InitSettings()
local panel = assert(a.settingsControls, 'panel was not built')
local function row(labelId)
    for _, entry in ipairs(panel.rows) do
        if entry.label == GetString(labelId) then return entry end
    end
    error('no row for ' .. tostring(labelId))
end
test('the panel carries every switch the slash commands have', function()
    assert(#panel.rows == 9)
    assert(row(SI_PBSSMS_ENABLED).type == LibHarvensAddonSettings.ST_CHECKBOX)
    assert(row(SI_PBSSMS_QUICK).type == LibHarvensAddonSettings.ST_CHECKBOX)
    assert(row(SI_PBSSMS_MODE).type == LibHarvensAddonSettings.ST_DROPDOWN)
    assert(row(SI_PBSSMS_HOLD).type == LibHarvensAddonSettings.ST_DROPDOWN)
end)
test('the quick shot checkbox is the same switch as /pbshot quick', function()
    reset(); local checkbox = row(SI_PBSSMS_QUICK)
    assert(checkbox.getFunction() == false)
    checkbox.setFunction(true); assert(a:QuickShot()); assert(checkbox.getFunction() == true)
    chord(); assert(guiHidden); assert(not a:InScreenshotMode()); a:Stop()
    a:Command('quick off'); assert(checkbox.getFunction() == false)
end)
test('the hold dropdown stores milliseconds and refuses anything else', function()
    reset(); local dropdown = row(SI_PBSSMS_HOLD)
    dropdown.setFunction(nil, nil, {data = 3000}); assert(a:QuickShotHoldMs() == 3000)
    dropdown.setFunction(nil, nil, {data = 1234}); assert(a:QuickShotHoldMs() == 3000)
    assert(dropdown.getFunction() == string.format(GetString(SI_PBSSMS_HOLD_ITEM), 3))
end)
test('the mode row goes grey while quick shot owns the chord', function()
    reset(); local mode = row(SI_PBSSMS_MODE)
    assert(not mode.disable()); a:SetQuickShot(true); assert(mode.disable())
    assert(row(SI_PBSSMS_HOLD).disable() == false)
    a:SetQuickShot(false); assert(row(SI_PBSSMS_HOLD).disable() == true)
end)
test('panel rows and slash commands both refresh the panel', function()
    reset(); local before = panel.updates
    a:Command('quick on'); a:Command('mode gui'); a:Command('hold 5')
    assert(panel.updates > before)
end)
test('the enable checkbox puts the input layer back when it is turned on', function()
    reset(); local checkbox = row(SI_PBSSMS_ENABLED)
    checkbox.setFunction(false); assert(not a.triggerLayerAdded); assert(checkbox.getFunction() == false)
    checkbox.setFunction(true); assert(a.triggerLayerAdded)
end)
test('the run button and the reset button are wired to the add-on', function()
    reset(); row(SI_PBSSMS_RUN_NOW).clickHandler(); assert(a:InScreenshotMode())
    a.sv.quickShot = true; a.sv.mode = 'gui'
    row(SI_PBSSMS_RESET_ROW).clickHandler()
    assert(a:QuickShot() == a.DEFAULTS.quickShot); assert(a:Mode() == a.DEFAULTS.mode)
end)
print(string.format('%d tests passed', count))

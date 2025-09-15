--[[
* Goal of this addon is to calculate weight and cost of items obtained through clamming.
*
* Used SlowedHaste HGather as a base for this addon: https://github.com/SlowedHaste/HGather
* Testing on local server: !pos -371 -1 -421 4
--]] addon.name = 'hxiclam';
addon.author = 'jimmy58663';
addon.version = '1.2.6';
addon.desc = 'HorizonXI clamming tracker addon.';
addon.link = 'https://github.com/jimmy58663/HXIClam';
addon.commands = {'/hxiclam'};

require('common');
local chat = require('chat');
local d3d = require('d3d8');
local ffi = require('ffi');
local fonts = require('fonts');
local imgui = require('imgui');
local prims = require('primitives');
local scaling = require('scaling');
local settings = require('settings');
local data = require('constants');

local C = ffi.C;
local d3d8dev = d3d.get_device();

local logs = T {
    drop_log_dir = 'drops',
    turnin_log_dir = 'turnins',
    char_name = nil
};

-- Default Settings
local default_settings = T {
    visible = T {true},
    display_timeout = T {600},
    opacity = T {1.0},
    padding = T {1.0},
    scale = T {1.0},
    item_index = data.ItemIndex,
    item_weight_index = data.ItemWeightIndex,
    font_scale = T {1.0},
    enable_logging = T {true},

    -- Clamming Display Settings
    clamming = T {bucket_cost = T {500}, bucket_subtract = T {true}},
    reset_on_load = T {false},
    first_attempt = 0,
    rewards = {},
    bucket_count = 0,
    item_count = 0,
    session_view = 1, -- 0 no session stats, 1 session summary, 2 session details

    bucket = {},
    bucket_is_active = false,
    bucket_weight = 0,
    bucket_capacity = 50,
    bucket_weight_warn_color = {1.0, 1.0, 0.0, 1.0}, -- yellow
    bucket_weight_warn_threshold = T {20},
    bucket_weight_crit_color = {1.0, 0.0, 0.0, 1.0}, -- red
    bucket_weight_crit_threshold = T {7},
    dig_timer_ready_color = {0.0, 1.0, 0.0, 1.0}, -- green
    bucket_weight_font_scale = T {1.0},

    last_dig = 0,
    dig_timer = 0,
    dig_timer_countdown = true,

    enable_tone = T {true},
    tone = 'clam.wav',
    tone_selected_idx = 1,
    available_tones = T {'clam.wav'},

    enable_bucket_total_color = T {false},
    negative_value_bucket_color = {1.0, 0.0, 0.0, 1.0}, -- red
    mid_value_bucket_color = {1.0, 1.0, 0.0, 1.0}, -- yellow
    mid_value_bucket_threshold = T {1000},
    high_value_bucket_color = {0.0, 1.0, 0.0, 1.0}, -- green
    high_value_bucket_threshold = T {5000},

    enable_item_color = T {false},
    zero_value_item_color = {1.0, 0.0, 0.0, 1.0}, -- red
    mid_tier_item_color = {1.0, 1.0, 0.0, 1.0}, -- yellow
    mid_tier_gil_threshold = T {500},
    high_tier_item_color = {0.0, 1.0, 0.0, 1.0}, -- green
    high_tier_gil_threshold = T {1000}
};

-- HXIClam Variables
local hxiclam = T {
    settings = settings.load(default_settings),

    -- Editor variables..
    editor = T {is_open = T {false}},

    last_attempt = ashita.time.clock()['ms'],
    pricing = T {},
    weights = T {},
    gil_per_hour = 0,

    play_tone = false
};

local MAX_HEIGHT_IN_LINES = 30;

----------------------------------------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------------------------------------
local function split(inputstr, sep)
    if sep == nil then sep = '%s'; end
    local t = {};
    for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
        table.insert(t, str);
    end
    return t;
end

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
local function format_int(number)
    if (string.len(number) < 4) then return number end
    if (number ~= nil and number ~= '' and type(number) == 'number') then
        local i, j, minus, int, fraction =
            tostring(number):find('([-]?)(%d+)([.]?%d*)');

        -- we sometimes get a nil int from the above tostring, just return number in those cases
        if (int == nil) then return number end

        -- reverse the int-string and append a comma to all blocks of 3 digits
        int = int:reverse():gsub("(%d%d%d)", "%1,");

        -- reverse the int-string back remove an optional comma and put the
        -- optional minus and fractional part back
        return minus .. int:reverse():gsub("^,", "") .. fraction;
    else
        return 'NaN';
    end
end

function WriteLog(logtype, item)
    -- Current log types supported are drop and turnin
    local logdir = nil
    if logtype == 'drop' then
        logdir = logs.drop_log_dir;
    elseif logtype == 'turnin' then
        logdir = logs.turnin_log_dir;
    end

    local datetime = os.date('*t');
    local log_file_name = ('%s_%.4u.%.2u.%.2u.log'):fmt(logs.char_name,
                                                        datetime.year,
                                                        datetime.month,
                                                        datetime.day);
    local full_directory = ('%s/addons/hxiclam/logs/%s/'):fmt(
                               AshitaCore:GetInstallPath(), logdir);

    if (not ashita.fs.exists(full_directory)) then
        ashita.fs.create_dir(full_directory);
    end

    local file = io.open(('%s/%s'):fmt(full_directory, log_file_name), 'a');
    if (file ~= nil) then
        local filedata = ('%s, %s\n'):fmt(os.date('[%H:%M:%S]'), item);
        file:write(filedata);
        file:close();
    end
end

----------------------------------------------------------------------------------------------------
-- Helper functions borrowed from luashitacast
----------------------------------------------------------------------------------------------------
function GetTimestamp()
    local pVanaTime = ashita.memory.find('FFXiMain.dll', 0,
                                         'B0015EC390518B4C24088D4424005068', 0,
                                         0);
    local pointer = ashita.memory.read_uint32(pVanaTime + 0x34);
    local rawTime = ashita.memory.read_uint32(pointer + 0x0C) + 92514960;
    local timestamp = {};
    timestamp.day = math.floor(rawTime / 3456);
    timestamp.hour = math.floor(rawTime / 144) % 24;
    timestamp.minute = math.floor((rawTime % 144) / 2.4);
    return timestamp;
end

----------------------------------------------------------------------------------------------------
-- Core functions
----------------------------------------------------------------------------------------------------
--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error(
                                                 'Invalid command syntax for command: '))
                  :append(chat.success('/' .. addon.name)));
    else
        print(
            chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T {
        {'/hxiclam', 'Toggles the HXIClam editor.'},
        {'/hxiclam edit', 'Toggles the HXIClam editor.'},
        {'/hxiclam save', 'Saves the current settings to disk.'},
        {'/hxiclam reload', 'Reloads the current settings from disk.'},
        {'/hxiclam clear', 'Clears the HXIClam bucket and session stats.'},
        {'/hxiclam clear bucket', 'Clears the HXIClam bucket stats.'},
        {'/hxiclam clear session', 'Clears the HXIClam session stats.'},
        {'/hxiclam show', 'Shows the HXIClam information.'},
        {'/hxiclam show session', 'Shows the HXIClam session stats.'},
        {'/hxiclam hide', 'Hides the HXIClam information.'},
        {'/hxiclam hide session', 'Hides the HXIClam session stats.'},
        {'/hxiclam update', 'Updates the HXIClam item pricing and weight info.'},
        {'/hxiclam update pricing', 'Updates the HXIClam item pricing info.'},
        {'/hxiclam update weights', 'Updates the HXIClam item weight info.'}
    };

    -- Print the command list..
    cmds:ieach(function(v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(
                  chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

local function update_pricing()
    local itemname;
    local itemvalue;
    for k, v in pairs(hxiclam.settings.item_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then itemname = v2; end
            if (k2 == 2) then itemvalue = v2; end
        end

        hxiclam.pricing[itemname] = itemvalue;
    end
end

local function update_weights()
    local itemname;
    local itemvalue;
    for k, v in pairs(hxiclam.settings.item_weight_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then itemname = v2; end
            if (k2 == 2) then itemvalue = v2; end
        end

        hxiclam.weights[itemname] = itemvalue;
    end

    hxiclam.settings.bucket_weight = 0;
    for k, v in pairs(hxiclam.settings.bucket) do
        if (hxiclam.weights[k] ~= nil) then
            hxiclam.settings.bucket_weight =
                hxiclam.settings.bucket_weight + hxiclam.weights[k];
        end
    end
end

local function update_tones()
    hxiclam.settings.available_tones = T {};
    local tone_path = ("%stones/"):format(addon.path);
    local cmd = 'dir "' .. tone_path .. '" /B';
    local idx = 1;
    for file in io.popen(cmd):lines() do
        hxiclam.settings.available_tones[idx] = file;
        idx = idx + 1;
    end
end

local function clear_rewards()
    hxiclam.last_attempt = ashita.time.clock()['ms'];
    hxiclam.settings.first_attempt = 0;
    hxiclam.settings.rewards = {};
    hxiclam.settings.item_count = 0;
    hxiclam.settings.bucket_count = 0;
end

local function clear_bucket()
    hxiclam.settings.bucket = {};
    hxiclam.settings.bucket_weight = 0;
    hxiclam.settings.bucket_capacity = 50;
end

local function play_sound()
    if (hxiclam.settings.enable_tone[1] == true and hxiclam.play_tone == true) then
        ashita.misc.play_sound(("%stones/%s"):format(addon.path,
                                                     hxiclam.settings.tone));
        hxiclam.play_tone = false;
    end
end

--[[
* Renders the HXIClam settings editor.
--]]
local function render_general_config(settings)
    imgui.Text('General Settings');
    imgui.BeginChild('settings_general', {
        0,
        imgui.GetTextLineHeightWithSpacing() * ((MAX_HEIGHT_IN_LINES / 3) + 1)
    }, true, ImGuiWindowFlags_AlwaysAutoResize);
    if (imgui.Checkbox('Visible', hxiclam.settings.visible)) then
        -- if the checkbox is interacted with, reset the last_attempt
        -- to force the window back open
        hxiclam.last_attempt = ashita.time.clock()['ms'];
    end
    imgui.ShowHelp('Toggles if HXIClam is visible or not.');
    imgui.Checkbox('Enable sound', hxiclam.settings.enable_tone);
    imgui.ShowHelp(
        'Enable/Disable a tone to be played when the dig timer is ready.');
    imgui.SameLine();
    if (imgui.BeginCombo('', hxiclam.settings.tone)) then
        for k, v in pairs(hxiclam.settings.available_tones) do
            local is_selected = k == hxiclam.settings.tone_selected_idx;
            if (imgui.Selectable(v, is_selected)) then
                hxiclam.settings.tone_selected_idx = k;
                hxiclam.settings.tone = v;
            end
            if (is_selected) then imgui.SetItemDefaultFocus(); end
        end
        imgui.EndCombo();
    end
    imgui.SameLine();
    if (imgui.ArrowButton("Tone_Test", ImGuiDir_Right)) then
        ashita.misc.play_sound(("%stones/%s"):format(addon.path,
                                                     hxiclam.settings.tone));
    end
    imgui.SliderFloat('Opacity', hxiclam.settings.opacity, 0.125, 1.0, '%.3f');
    imgui.ShowHelp('The opacity of the HXIClam window.');
    imgui.SliderFloat('Font Scale', hxiclam.settings.font_scale, 0.1, 2.0,
                      '%.3f');
    imgui.ShowHelp('The scaling of the font size.');
    imgui.SliderFloat('Weight Font Scale',
                      hxiclam.settings.bucket_weight_font_scale, 0.1, 2.0,
                      '%.3f');
    imgui.ShowHelp('The scaling of the font size for bucket weight.');

    imgui.InputInt('Display Timeout', hxiclam.settings.display_timeout);
    imgui.ShowHelp(
        'How long should the display window stay open after the last dig.');
    imgui.Checkbox('Reset Rewards On Load', hxiclam.settings.reset_on_load);
    imgui.ShowHelp(
        'Toggles whether we reset rewards each time the addon is loaded.');
    imgui.Checkbox('Enable Logging', hxiclam.settings.enable_logging);
    imgui.ShowHelp(
        'Toggles whether drops and bucket turnins are logged in a text file.');
    imgui.SameLine();
    imgui.EndChild();
    imgui.Text('Clamming Display Settings');
    imgui.BeginChild('clam_general', {
        0, imgui.GetTextLineHeightWithSpacing() * MAX_HEIGHT_IN_LINES * 2 / 3
    }, true, ImGuiWindowFlags_AlwaysAutoResize);
    if (imgui.RadioButton('Hide Session Stats',
                          hxiclam.settings.session_view == 0)) then
        hxiclam.settings.session_view = 0;
    end
    imgui.ShowHelp('Hides the session stats.');
    imgui.SameLine();
    if (imgui.RadioButton('Session Summary', hxiclam.settings.session_view == 1)) then
        hxiclam.settings.session_view = 1;
    end
    imgui.ShowHelp('Shows only session stats as a summary.');
    imgui.SameLine();
    if (imgui.RadioButton('Session Details', hxiclam.settings.session_view == 2)) then
        hxiclam.settings.session_view = 2;
    end
    imgui.ShowHelp('Shows full session details.');
    if (imgui.RadioButton('Dig Timer Count Up',
                          hxiclam.settings.dig_timer_countdown == false)) then
        hxiclam.settings.dig_timer_countdown = false;
    end
    imgui.ShowHelp('Dig timer will count up to 9 and then display Dig Ready.');
    imgui.SameLine();
    if (imgui.RadioButton('Dig Timer Count Down',
                          hxiclam.settings.dig_timer_countdown == true)) then
        hxiclam.settings.dig_timer_countdown = true;
    end
    imgui.ShowHelp(
        'Dig timer will count down from 10 and then display Dig Ready.');
    imgui.Checkbox('Subtract Bucket Cost',
                   hxiclam.settings.clamming.bucket_subtract);
    imgui.ShowHelp(
        'Toggles if bucket costs are automatically subtracted from gil earned.');
    imgui.InputInt('Warning Weight Limit',
                   hxiclam.settings.bucket_weight_warn_threshold);
    imgui.ShowHelp(
        'How much weight left in your bucket will turn the bucket weight to the warning bucket color.');
    imgui.ColorEdit4('Warning Bucket Color',
                     hxiclam.settings.bucket_weight_warn_color);
    imgui.ShowHelp(
        'The color bucket weight will turn when it reached the warning weight limit.');
    imgui.InputInt('Critical Weight Limit',
                   hxiclam.settings.bucket_weight_crit_threshold);
    imgui.ShowHelp(
        'How much weight left in your bucket will turn the bucket weight to the critical bucket color.');
    imgui.ColorEdit4('Critical Bucket Color',
                     hxiclam.settings.bucket_weight_crit_color);
    imgui.ShowHelp(
        'The color bucket weight will turn when it reached the critical weight limit.');
    imgui.ColorEdit4('Dig Timer Ready Color',
                     hxiclam.settings.dig_timer_ready_color);
    imgui.ShowHelp('The color dig timer will turn when it reaches Dig Ready.');
    imgui.Separator();

    imgui.Checkbox('Enable Bucket Total Colors',
                   hxiclam.settings.enable_bucket_total_color);
    imgui.ShowHelp(
        'Enable or disable coloring of bucket profit/revenue based on gil values.');
    imgui.ColorEdit4('Negative Value Bucket Color',
                     hxiclam.settings.negative_value_bucket_color);
    imgui.ShowHelp(
        'The color profit/revenue will turn if the total is less than or equal to 0.');
    imgui.InputInt('Mid Value Bucket Threshold',
                   hxiclam.settings.mid_value_bucket_threshold);
    imgui.ShowHelp(
        'The profit/reveunue threshold to color with Mid Value Bucket Color.');
    imgui.ColorEdit4('Mid Value Bucket Color',
                     hxiclam.settings.mid_value_bucket_color);
    imgui.ShowHelp(
        'The color profit/revenue will turn if the total is equal or more than Mid Value Bucket Threshold and less than High Value Bucket Threshold.');
    imgui.InputInt('High Value Bucket Threshold',
                   hxiclam.settings.high_value_bucket_threshold);
    imgui.ShowHelp(
        'The profit/reveunue threshold to color with High Value Bucket Color.');
    imgui.ColorEdit4('High Value Bucket Color',
                     hxiclam.settings.high_value_bucket_color);
    imgui.ShowHelp(
        'The color profit/revenue will turn if the total equal or more than Mid Value Bucket Threshold.');
    imgui.Separator();

    imgui.Checkbox('Enable Item Colors', hxiclam.settings.enable_item_color);
    imgui.ShowHelp(
        'Enable or disable coloring of items in your bucket based on gil values.');
    imgui.ColorEdit4('Zero Value Item Color',
                     hxiclam.settings.zero_value_item_color);
    imgui.ShowHelp('The color items will turn if their value is 0.');
    imgui.InputInt('Mid Tier Gil Threshold',
                   hxiclam.settings.mid_tier_gil_threshold);
    imgui.ShowHelp(
        'How much gil an item is worth to color it Mid Tier Item Color.');
    imgui.ColorEdit4('Mid Tier Item Color', hxiclam.settings.mid_tier_item_color);
    imgui.ShowHelp(
        'The color items will turn if their value is equal to or more than Mid Tier Gil Threshold.');
    imgui.InputInt('High Tier Gil Threshold',
                   hxiclam.settings.high_tier_gil_threshold);
    imgui.ShowHelp(
        'How much gil an item is worth to color it High Tier Item Color.');
    imgui.ColorEdit4('High Tier Item Color',
                     hxiclam.settings.high_tier_item_color);
    imgui.ShowHelp(
        'The color items will turn if their value is equal to or more than High Tier Gil Threshold.');
    imgui.EndChild();
end

local function render_item_price_config(settings)
    imgui.Text('Item Prices');
    imgui.BeginChild('settings_general', {
        0, imgui.GetTextLineHeightWithSpacing() * MAX_HEIGHT_IN_LINES
    }, true, ImGuiWindowFlags_AlwaysAutoResize);

    imgui.InputInt('Bucket Cost', hxiclam.settings.clamming.bucket_cost);
    imgui.ShowHelp('Cost of a single bucket.');

    imgui.Separator();

    local temp_strings = T {};
    temp_strings[1] = table.concat(hxiclam.settings.item_index, '\n');
    if (imgui.InputTextMultiline('\nItem Prices', temp_strings, 8192, {
        0, imgui.GetTextLineHeightWithSpacing() * (MAX_HEIGHT_IN_LINES - 3)
    })) then
        hxiclam.settings.item_index = split(temp_strings[1], '\n');
        table.sort(hxiclam.settings.item_index);
    end
    imgui.ShowHelp(
        'Individual items, lowercase, separated by : with price on right side.');
    imgui.EndChild();
end

local function render_item_weight_config(settings)
    imgui.Text('Item Weights');
    imgui.BeginChild('settings_general', {
        0, imgui.GetTextLineHeightWithSpacing() * MAX_HEIGHT_IN_LINES
    }, true, ImGuiWindowFlags_AlwaysAutoResize);

    local temp_strings = T {};
    temp_strings[1] = table.concat(hxiclam.settings.item_weight_index, '\n');
    if (imgui.InputTextMultiline('\nItem Weights', temp_strings, 8192, {
        0, imgui.GetTextLineHeightWithSpacing() * (MAX_HEIGHT_IN_LINES - 3)
    })) then
        hxiclam.settings.item_weight_index = split(temp_strings[1], '\n');
        table.sort(hxiclam.settings.item_weight_index);
    end
    imgui.ShowHelp(
        'Individual items, lowercase, separated by : with weight on right side.');
    imgui.EndChild();
end

local function render_editor()
    if (not hxiclam.editor.is_open[1]) then return; end

    imgui.SetNextWindowSize({0, 0}, ImGuiCond_Always);
    if (imgui.Begin('HXIClam##Config', hxiclam.editor.is_open,
                    ImGuiWindowFlags_AlwaysAutoResize)) then

        -- imgui.SameLine();
        if (imgui.Button('Save Settings')) then
            settings.save();
            print(
                chat.header(addon.name):append(chat.message('Settings saved.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reload Settings')) then
            settings.reload();
            print(chat.header(addon.name):append(chat.message(
                                                     'Settings reloaded.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reset Settings')) then
            settings.reset();
            print(chat.header(addon.name):append(chat.message(
                                                     'Settings reset to defaults.')));
        end
        imgui.SameLine();
        if (imgui.Button('Update Pricing')) then
            update_pricing();
            print(chat.header(addon.name):append(
                      chat.message('Pricing updated.')));
        end
        imgui.SameLine();
        if (imgui.Button('Update Weights')) then
            update_weights();
            print(chat.header(addon.name):append(
                      chat.message('Weights updated.')));
        end
        if (imgui.Button('Clear Session')) then
            clear_rewards();
            print(chat.header(addon.name):append(
                      chat.message('Cleared session.')));
        end
        imgui.SameLine();
        if (imgui.Button('Clear Bucket')) then
            clear_bucket();
            print(
                chat.header(addon.name):append(chat.message('Cleared bucket.')));
        end
        imgui.SameLine();
        if (imgui.Button('Clear All')) then
            clear_rewards();
            clear_bucket();
            print(chat.header(addon.name):append(chat.message(
                                                     'Cleared session and bucket.')));
        end

        imgui.Separator();

        if (imgui.BeginTabBar('##hxiclam_tabbar',
                              ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
            if (imgui.BeginTabItem('General', nil)) then
                render_general_config(settings);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Item Price', nil)) then
                render_item_price_config(settings);
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Item Weight', nil)) then
                render_item_weight_config(settings);
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end

    end
    imgui.End();
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', function(s)
    if (s ~= nil) then hxiclam.settings = s; end

    -- Save the current settings..
    settings.save();
    update_pricing();
    update_weights();
end);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function()
    update_pricing();
    update_weights();
    update_tones();
    if (hxiclam.settings.reset_on_load[1]) then
        print('Reset bucket and session on reload.');
        clear_rewards();
        clear_bucket();
    end

    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    if (name ~= nil and name:len() > 0) then logs.char_name = name; end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function()
    -- Save the current settings..
    settings.save();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function(e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hxiclam')) then return; end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /hxiclam - Toggles the hxiclam editor.
    -- Handle: /hxiclam edit - Toggles the hxiclam editor.
    if (#args == 1 or (#args >= 2 and args[2]:any('edit'))) then
        hxiclam.editor.is_open[1] = not hxiclam.editor.is_open[1];
        return;
    end

    -- Handle: /hxiclam save - Saves the current settings.
    if (#args >= 2 and args[2]:any('save')) then
        update_pricing();
        update_weights();
        settings.save();
        print(chat.header(addon.name):append(chat.message('Settings saved.')));
        return;
    end

    -- Handle: /hxiclam reload - Reloads the current settings from disk.
    if (#args >= 2 and args[2]:any('reload')) then
        settings.reload();
        update_tones();
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        return;
    end

    -- Handle: /hxiclam clear - Clears the current session and bucket info.
    -- Handle: /hxiclam clear bucket - Clears the current bucket info.
    -- Handle: /hxiclam clear session - Clears the current session info.
    if (#args >= 2 and args[2]:any('clear')) then
        if (#args == 3 and args[3]:any('bucket')) then
            clear_bucket();
            print(chat.header(addon.name):append(chat.message(
                                                     'Cleared hxiclam bucket.')));
        elseif (#args == 3 and args[3]:any('session')) then
            clear_rewards();
            print(chat.header(addon.name):append(chat.message(
                                                     'Cleared hxiclam session.')));
        else
            clear_rewards();
            clear_bucket();
            print(chat.header(addon.name):append(chat.message(
                                                     'Cleared hxiclam bucket and session.')));
        end
        return;
    end

    -- Handle: /hxiclam show - Shows the hxiclam object.
    if (#args >= 2 and args[2]:any('show')) then
        if (#args == 3 and args[3]:any('session')) then
            hxiclam.settings.session_view = 2;
        elseif (#args == 3 and args[3]:any('summary')) then
            hxiclam.settings.session_view = 1;
        else
            -- reset last dig on show command to reset timeout counter
            hxiclam.last_attempt = ashita.time.clock()['ms'];
            hxiclam.settings.visible[1] = true;
        end
        return;
    end

    -- Handle: /hxiclam hide - Hides the hxiclam object.
    if (#args >= 2 and args[2]:any('hide')) then
        if (#args == 3 and args[3]:any('session')) then
            hxiclam.settings.session_view = 0;
        else
            hxiclam.settings.visible[1] = false;
        end
        return;
    end

    -- Handle: /hxiclam update - Updates the current pricing and weight info for items.
    -- Handle: /hxiclam update pricing - Updates the current pricing info for items.
    -- Handle: /hxiclam update weights - Updates the current weight info for items.
    if (#args >= 2 and args[2]:any('update')) then
        if (#args == 3 and args[3]:any('pricing')) then
            update_pricing();
            print(chat.header(addon.name):append(
                      chat.message('Pricing updated.')));
        elseif (#args == 3 and args[3]:any('weights')) then
            update_weights();
            print(chat.header(addon.name):append(
                      chat.message('Weights updated.')));
        else
            update_pricing();
            update_weights();
            print(chat.header(addon.name):append(chat.message(
                                                     'Pricing and weights updated.')));
        end
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function(e)
    local last_attempt_secs =
        (ashita.time.clock()['ms'] - hxiclam.last_attempt) / 1000.0;
    local message = e.message;
    message = string.lower(message);
    message = string.strip_colors(message);

    local bucket = string.match(message, "obtained key item: clamming kit");
    local item = string.match(message,
                              "you find a[n]? (.*) and toss it into your bucket.*");
    local bucket_upgrade = string.match(message,
                                        "your clamming capacity has increased to (%d+) ponzes!");
    local bucket_turnin = string.match(message, "you return the clamming kit");
    local overweight = string.match(message,
                                    ".*for the bucket and its bottom breaks.*");
    local incident =
        string.match(message, ".*somthing jumps into your bucket.*"); -- need an example text of this

    -- Update last attempt timestamp if any clamming action occurs
    -- show hxiclam once a clamming action occurs
    if (bucket) then hxiclam.settings.bucket_is_active = true
    elseif (bucket_turnin) then hxiclam.settings.bucket_is_active = false end

    if (bucket or item or bucket_turnin or overweight or incident) then
        hxiclam.last_attempt = ashita.time.clock()['ms']
        if (hxiclam.settings.first_attempt == 0) then
            hxiclam.settings.first_attempt = ashita.time.clock()['ms'];
        end
        if (hxiclam.settings.visible[1] == false) then
            hxiclam.settings.visible[1] = true;
        end
    end

    -- Clear bucket and add to bucket count when a bucket is obtained.
    if (bucket) then
        clear_bucket();
        hxiclam.settings.bucket_count = hxiclam.settings.bucket_count + 1;
    elseif (item) then
        hxiclam.play_tone = true;
        -- Update last dig time and reset dig_timer
        hxiclam.settings.last_dig = ashita.time.clock()['ms'];

        if (hxiclam.settings.dig_timer_countdown) then
            hxiclam.settings.dig_timer = 10;
        else
            hxiclam.settings.dig_timer = 0;
        end

        -- Update bucket item list
        if (hxiclam.settings.bucket[item] == nil) then
            hxiclam.settings.bucket[item] = 1;
        elseif (hxiclam.settings.bucket[item] ~= nil) then
            hxiclam.settings.bucket[item] = hxiclam.settings.bucket[item] + 1;
        end

        -- Log the item
        if (hxiclam.settings.enable_logging[1]) then
            WriteLog('drop', item);
        end

        -- Update bucket weight
        if (hxiclam.weights[item] ~= nil) then
            hxiclam.settings.bucket_weight =
                hxiclam.settings.bucket_weight + hxiclam.weights[item];
        end
    elseif (bucket_upgrade) then
        hxiclam.settings.bucket_capacity = bucket_upgrade;
    elseif (bucket_turnin) then
        if (hxiclam.settings.bucket ~= nil and hxiclam.settings.bucket ~= {}) then
            for k, v in pairs(hxiclam.settings.bucket) do
                hxiclam.settings.item_count = hxiclam.settings.item_count + v;
                if (hxiclam.settings.rewards[k] == nil) then
                    hxiclam.settings.rewards[k] = v;
                elseif (hxiclam.settings.rewards[k] ~= nil) then
                    hxiclam.settings.rewards[k] =
                        hxiclam.settings.rewards[k] + v
                end

                -- Log the items turned in
                if (hxiclam.settings.enable_logging[1]) then
                    for i = 1, v do WriteLog('turnin', k); end
                end
            end
            clear_bucket();
        end
    end

    if (overweight or incident) then clear_bucket(); end
end);

--[[
* event: d3d_beginscene
* desc : Event called when the Direct3D device is beginning a scene.
--]]
ashita.events.register('d3d_beginscene', 'beginscene_cb',
                       function(isRenderingBackBuffer) end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function()
    local last_attempt_secs =
        (ashita.time.clock()['ms'] - hxiclam.last_attempt) / 1000.0;
    render_editor();

    if (last_attempt_secs > hxiclam.settings.display_timeout[1]) then
        hxiclam.settings.visible[1] = false;
    end

    -- Hide the hxiclam object if not visible..
    if (not hxiclam.settings.visible[1]) then return; end

    -- Hide the hxiclam object if Ashita is currently hiding font objects..
    if (not AshitaCore:GetFontManager():GetVisible()) then return; end

    imgui.SetNextWindowBgAlpha(hxiclam.settings.opacity[1]);
    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always);
    if (imgui.Begin('HXIClam##Display', hxiclam.settings.visible[1],
                    bit.bor(ImGuiWindowFlags_NoDecoration,
                            ImGuiWindowFlags_AlwaysAutoResize,
                            ImGuiWindowFlags_NoFocusOnAppearing,
                            ImGuiWindowFlags_NoNav))) then
        local elapsed_time = ashita.time.clock()['s'] -
                                 math.floor(
                                     hxiclam.settings.first_attempt / 1000.0);
        local timer_display = hxiclam.settings.dig_timer;

        if (hxiclam.settings.dig_timer_countdown) then
            local dig_diff = (math.floor(hxiclam.settings.last_dig / 1000.0) +
                                 10) - ashita.time.clock()['s'];
            if (dig_diff < hxiclam.settings.dig_timer) then
                hxiclam.settings.dig_timer = dig_diff;
            end

            timer_display = hxiclam.settings.dig_timer;
            if (timer_display <= 0) then timer_display = "Dig Ready" end
        else
            local dig_diff = ashita.time.clock()['s'] -
                                 math.floor(hxiclam.settings.last_dig / 1000.0);
            if (dig_diff > hxiclam.settings.dig_timer) then
                hxiclam.settings.dig_timer = dig_diff
            end

            timer_display = hxiclam.settings.dig_timer;
            if (timer_display >= 10) then timer_display = "Dig Ready" end
        end

        local total_worth = 0;
        local bucket_total = 0;

        imgui.SetWindowFontScale(hxiclam.settings.font_scale[1] + 0.1);
        imgui.Text('Bucket Stats:');
        imgui.SameLine()
        if (hxiclam.settings.bucket_is_active) then
            imgui.TextColored(hxiclam.settings.dig_timer_ready_color, 'ACTIVE')
        else
            imgui.TextColored(hxiclam.settings.bucket_weight_crit_color, 'INACTIVE')
        end
        imgui.SetWindowFontScale(hxiclam.settings.bucket_weight_font_scale[1]);
        imgui.Text('Bucket Weight: ');
        imgui.SameLine();
        if ((hxiclam.settings.bucket_capacity - hxiclam.settings.bucket_weight) <=
            hxiclam.settings.bucket_weight_crit_threshold[1]) then
            imgui.TextColored(hxiclam.settings.bucket_weight_crit_color,
                              tostring(hxiclam.settings.bucket_weight) .. '/' ..
                                  hxiclam.settings.bucket_capacity);
        elseif ((hxiclam.settings.bucket_capacity -
            hxiclam.settings.bucket_weight) <=
            hxiclam.settings.bucket_weight_warn_threshold[1]) then
            imgui.TextColored(hxiclam.settings.bucket_weight_warn_color,
                              tostring(hxiclam.settings.bucket_weight) .. '/' ..
                                  hxiclam.settings.bucket_capacity);
        else
            imgui.Text(tostring(hxiclam.settings.bucket_weight) .. '/' ..
                           hxiclam.settings.bucket_capacity);
        end
        imgui.SetWindowFontScale(hxiclam.settings.font_scale[1]);

        imgui.Text('Dig Timer: ');
        imgui.SameLine();
        if (timer_display == 'Dig Ready') then
            imgui.TextColored(hxiclam.settings.dig_timer_ready_color,
                              tostring(timer_display));
            play_sound();
        else
            imgui.Text(tostring(timer_display));
        end

        for k, v in pairs(hxiclam.settings.bucket) do
            if (hxiclam.pricing[k] ~= nil) then
                bucket_total = bucket_total + hxiclam.pricing[k] * v;
            end
        end

        if (hxiclam.settings.clamming.bucket_subtract[1]) then
            bucket_total = bucket_total -
                               hxiclam.settings.clamming.bucket_cost[1];
            imgui.Text('Bucket Profit:');
        else
            imgui.Text('Bucket Revenue:');
        end
        imgui.SameLine();

        if (hxiclam.settings.enable_bucket_total_color[1]) then
            if (bucket_total <= 0) then
                imgui.TextColored(hxiclam.settings.negative_value_bucket_color,
                                  format_int(bucket_total) .. 'g');
            elseif (bucket_total >=
                hxiclam.settings.mid_value_bucket_threshold[1] and bucket_total <
                hxiclam.settings.high_value_bucket_threshold[1]) then
                imgui.TextColored(hxiclam.settings.mid_value_bucket_color,
                                  format_int(bucket_total) .. 'g');
            elseif (bucket_total >=
                hxiclam.settings.high_value_bucket_threshold[1]) then
                imgui.TextColored(hxiclam.settings.high_value_bucket_color,
                                  format_int(bucket_total) .. 'g');
            else
                imgui.Text(tostring(format_int(bucket_total) .. 'g'));
            end
        else
            imgui.Text(tostring(format_int(bucket_total) .. 'g'));
        end

        imgui.Separator();

        for k, v in pairs(hxiclam.settings.bucket) do
            local itemTotal = 0;
            local text = '';
            local itemPrice = 0;
            if (hxiclam.pricing[k] ~= nil) then
                itemPrice = tonumber(hxiclam.pricing[k]);
                itemTotal = itemPrice * v;
            end
            text = k .. ': ' .. 'x' .. format_int(v) .. ' (' ..
                       format_int(itemTotal) .. 'g)';

            if hxiclam.settings.enable_item_color[1] then
                if (itemPrice == 0) then
                    imgui.TextColored(hxiclam.settings.zero_value_item_color,
                    text);
                elseif (itemPrice >= hxiclam.settings.mid_tier_gil_threshold[1] and
                itemPrice < hxiclam.settings.high_tier_gil_threshold[1]) then
                    imgui.TextColored(hxiclam.settings.mid_tier_item_color, text);
                elseif (itemPrice >= hxiclam.settings.high_tier_gil_threshold[1]) then
                    imgui.TextColored(hxiclam.settings.high_tier_item_color,
                                      text);
                else
                    imgui.Text(text);
                end
            else
                imgui.Text(text);
            end
        end

        if (hxiclam.settings.session_view > 0) then
            imgui.Separator();
            imgui.SetWindowFontScale(hxiclam.settings.font_scale[1] + 0.1);
            imgui.Text('Session Stats:');
            imgui.SetWindowFontScale(hxiclam.settings.font_scale[1]);
            imgui.Text('Buckets Cost: ' ..
                           format_int(hxiclam.settings.bucket_count *
                                          hxiclam.settings.clamming.bucket_cost[1]));
            imgui.Text('Items Dug: ' .. tostring(hxiclam.settings.item_count));
            imgui.Separator();

            for k, v in pairs(hxiclam.settings.rewards) do
                local itemTotal = 0;
                if (hxiclam.pricing[k] ~= nil) then
                    total_worth = total_worth + hxiclam.pricing[k] * v;
                    itemTotal = v * hxiclam.pricing[k];
                end

                if (hxiclam.settings.session_view > 1) then
                    imgui.Text(k .. ': ' .. 'x' .. format_int(v) .. ' (' ..
                                   format_int(itemTotal) .. 'g)');
                end
            end
            if (hxiclam.settings.session_view > 1) then
                imgui.Separator();
            end

            if (hxiclam.settings.clamming.bucket_subtract[1]) then
                total_worth = total_worth -
                                  (hxiclam.settings.bucket_count *
                                      hxiclam.settings.clamming.bucket_cost[1]);
                -- only update gil_per_hour every 3 seconds
                if ((ashita.time.clock()['s'] % 3) == 0) then
                    hxiclam.gil_per_hour =
                        math.floor((total_worth / elapsed_time) * 3600);
                end
                imgui.Text('Total Profit: ' .. format_int(total_worth) .. 'g' ..
                               ' (' .. format_int(hxiclam.gil_per_hour) ..
                               ' gph)');
            else
                -- only update gil_per_hour every 3 seconds
                if ((ashita.time.clock()['s'] % 3) == 0) then
                    hxiclam.gil_per_hour =
                        math.floor((total_worth / elapsed_time) * 3600);
                end
                imgui.Text(
                    'Total Revenue: ' .. format_int(total_worth) .. 'g' .. ' (' ..
                        format_int(hxiclam.gil_per_hour) .. ' gph)');
            end
        end
    end
    imgui.End();

end);

--[[
Copyright © 2024, jimmy58663
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of HXIClam nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL jimmy58663 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]] -- Testing on local server: !pos -371 -1 -421 4
_addon.name = 'hxiclam';
_addon.author = 'jimmy58663';
_addon.version = '1.2.6';
-- _addon.desc      = 'HorizonXI clamming tracker addon.';
-- _addon.link      = 'https://github.com/jimmy58663/HXIClam';
_addon.commands = {'hxiclam'};

require('tables');
require('strings');
local logger = require('logger');
local config = require('config');
local data = require('constants');
local texts = require('texts');

local logs = T {
    drop_log_dir = 'drops',
    turnin_log_dir = 'turnins',
    char_name = nil
};

-- Default Settings
local default_settings = T {
    visible = T {true},
    display_timeout = T {600},
    item_index = data.ItemIndex,
    item_weight_index = data.ItemWeightIndex,
    enable_logging = T {true},

    -- Clamming Display Settings
    clamming = T {
        bucket_cost = T {500},
        bucket_subtract = T {true},
        count_free_bucket = T {true},
        do_not_use_fourth_bucket = T {true}
    },
    reset_on_load = T {false},

    session_view = 1, -- 0 no session stats, 1 session summary, 2 session details

    bucket_weight_warn_color = {255, 255, 0}, -- yellow
    bucket_weight_warn_threshold = T {19},
    bucket_weight_crit_color = {255, 0, 0}, -- red
    bucket_weight_crit_threshold = T {7},
    dig_timer_ready_color = {0, 255, 0}, -- green
    bucket_weight_font_size = 16,

    last_dig = 0,
    dig_timer = 0,
    dig_timer_countdown = true,

    enable_tone = T {true},
    tone = 'clam.wav',

    -- Text object display settings
    display = {
        padding = 1,
        pos = {x = 100, y = 100},
        text = {
            font = 'Arial',
            size = 14
            -- red = ,
            -- green = ,
            -- blue = ,
            -- alpha = ,
            -- stroke = {
            -- width = ,
            -- red = ,
            -- green = ,
            -- blue = ,
            -- alpha = ,
            -- },
        },
        flags = {italic = false, bold = false, right = false, bottom = false},
        bg = {
            -- red = ,
            -- green = ,
            -- blue = ,
            alpha = 200,
            visible = true
        }
    }
};

-- HXIClam Variables
local hxiclam = T {
    settings = config.load(default_settings),

    -- hxiclam movement variables..
    move = T {dragging = false, drag_x = 0, drag_y = 0, shift_down = false},

    -- Editor variables..
    editor = T {is_open = T {false}},

    last_attempt = os.clock(),
    pricing = T {},
    weights = T {},
    probabilities = T {},
    gil_per_hour = 0,

    -- Session data
    bucket = {},
    bucket_weight = 0,
    bucket_capacity = 50,

    rewards = {},
    bucket_count = 0,
    item_count = 0,
    first_attempt = 0,

    play_tone = false
};

-- Display setup
local hxiclam_display = texts.new('', hxiclam.settings.display);
hxiclam_display:draggable(true);

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

local function WriteLog(logtype, item)
    -- Current log types supported are drop and turnin
    local logdir = nil
    if logtype == 'drop' then
        logdir = logs.drop_log_dir;
    elseif logtype == 'turnin' then
        logdir = logs.turnin_log_dir;
    end

    local datetime = os.date('*t');
    local log_file_name = ('%s_%.4u.%.2u.%.2u.log'):format(logs.char_name,
                                                           datetime.year,
                                                           datetime.month,
                                                           datetime.day);
    local full_directory = ('%slogs/%s'):format(windower.addon_path, logdir);

    -- Set up log dirs if they do not exist
    if not windower.dir_exists(('%slogs'):format(windower.addon_path)) then
        windower.create_dir(('%slogs'):format(windower.addon_path))
    end
    if not windower.dir_exists(full_directory) then
        windower.create_dir(full_directory)
    end

    local file = io.open(('%s/%s'):format(full_directory, log_file_name), 'a');
    if (file ~= nil) then
        local filedata = ('%s, %s\n'):format(os.date('[%H:%M:%S]'), item);
        file:write(filedata);
        file:close();
    end
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
        windower.add_to_chat(38,
                             ('[%s] Invalid command syntax for command: //%s'):format(
                                 _addon.name, _addon.name));
    else
        windower.add_to_chat(121,
                             ('[%s] Available commands:'):format(_addon.name));
    end

    local cmds = T {
        {'//hxiclam save', 'Saves the current settings to disk.'},
        {'//hxiclam reload', 'Reloads the current settings from disk.'},
        {'//hxiclam clear', 'Clears the HXIClam bucket and session stats.'},
        {'//hxiclam clear bucket', 'Clears the HXIClam bucket stats.'},
        {'//hxiclam clear session', 'Clears the HXIClam session stats.'},
        {'//hxiclam show', 'Shows the HXIClam information.'},
        {'//hxiclam show session', 'Shows the HXIClam session stats.'},
        {'//hxiclam show summary', 'Shows the HXIClam session summary.'},
        {'//hxiclam hide', 'Hides the HXIClam information.'},
        {'//hxiclam hide session', 'Hides the HXIClam session stats.'},
        {
            '//hxiclam update',
            'Updates the HXIClam item pricing and weight info.'
        },
        {'//hxiclam update pricing', 'Updates the HXIClam item pricing info.'},
        {'//hxiclam update weights', 'Updates the HXIClam item weight info.'}
    };

    -- Print the command list..
    for k, v in pairs(cmds) do
        windower.add_to_chat(121, ('[%s] Usage: %s - %s'):format(_addon.name,
                                                                 v[1], v[2]));
    end
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

local function update_probabilities()
    hxiclam.probabilities = T {};
    local total_percent = 0;

    for _, entry in pairs(data.ItemProbabilityIndex) do
        local parts = split(entry, ':');
        local itemname = parts[1];
        local percent = tonumber(parts[2]) or 0;
        hxiclam.probabilities[itemname] = percent;
        total_percent = total_percent + percent;
    end

    if (total_percent > 0) then
        for itemname, percent in pairs(hxiclam.probabilities) do
            hxiclam.probabilities[itemname] = percent / total_percent;
        end
    end
end

local function get_bucket_contents_value()
    local value = 0;
    local bucket = hxiclam.bucket;
    for itemname, count in pairs(bucket) do
        local price = tonumber(hxiclam.pricing[itemname]) or 0;
        value = value + (price * tonumber(count));
    end
    return value;
end

local function qualifies_for_free_bucket(new_weight, capacity)
    if (not hxiclam.settings.clamming.count_free_bucket[1]) then return false; end
    if (capacity == 50) then return new_weight >= 45 and new_weight <= 50; end
    if (capacity == 100) then return new_weight >= 95 and new_weight <= 100; end
    if (capacity == 150 and not hxiclam.settings.clamming.do_not_use_fourth_bucket[1]) then
        return new_weight >= 145 and new_weight <= 150;
    end
    return false;
end

local function should_turn_in_bucket()
    local current_weight = tonumber(hxiclam.bucket_weight) or 0;
    local capacity = tonumber(hxiclam.bucket_capacity) or 50;

    if (capacity == 50) then
        return current_weight >= 45 and current_weight <= 50;
    end
    if (capacity == 100) then
        return current_weight >= 95 and current_weight <= 100;
    end
    if (capacity == 150) then
        return current_weight >= 145 and current_weight <= 150;
    end

    return false;
end

local function is_next_dig_safe()
    local current_weight = tonumber(hxiclam.bucket_weight) or 0;
    local capacity = tonumber(hxiclam.bucket_capacity) or 50;

    for itemname, probability in pairs(hxiclam.probabilities) do
        if (probability > 0) then
            local item_weight = tonumber(hxiclam.weights[itemname]);
            if (item_weight ~= nil and current_weight + item_weight > capacity) then
                return false;
            end
        end
    end

    return true;
end

local function calculate_expected_value()
    local current_weight = tonumber(hxiclam.bucket_weight) or 0;
    local capacity = tonumber(hxiclam.bucket_capacity) or 50;
    local current_value = get_bucket_contents_value();
    local expected_value = 0;
    local bust_probability = 0;

    for itemname, probability in pairs(hxiclam.probabilities) do
        local item_weight = tonumber(hxiclam.weights[itemname]);
        if (item_weight ~= nil) then
            local new_weight = current_weight + item_weight;
            if (new_weight > capacity) then
                bust_probability = bust_probability + probability;
                expected_value = expected_value - (current_value * probability);
            else
                local reward_value = tonumber(hxiclam.pricing[itemname]) or 0;
                if (qualifies_for_free_bucket(new_weight, capacity)) then
                    reward_value = reward_value + 500;
                end
                expected_value = expected_value + (reward_value * probability);
            end
        end
    end

    return expected_value, bust_probability;
end

local function round_nearest(number)
    if (number >= 0) then return math.floor(number + 0.5); end
    return math.ceil(number - 0.5);
end

local function get_expected_value_color(expected_value)
    local saturation = 500;
    local strength = math.min(math.abs(expected_value) / saturation, 1);

    if (expected_value >= 0) then
        return 1 - strength, 1, 1 - strength;
    end
    return 1 - (strength * 0.37), 1 - strength, 1 - strength;
end

local function get_expected_value_display()
    local ready_color = hxiclam.settings.dig_timer_ready_color;

    if (should_turn_in_bucket()) then
        return 'TURN IN', ready_color[1], ready_color[2], ready_color[3];
    end

    if (is_next_dig_safe()) then
        return 'DIG!!!', ready_color[1], ready_color[2], ready_color[3];
    end

    local expected_value, bust_probability = calculate_expected_value();
    local rounded_expected_value = round_nearest(expected_value);
    local rounded_bust_percent = string.format('%.1f', bust_probability * 100);
    local red, green, blue = get_expected_value_color(expected_value);
    return format_int(rounded_expected_value) .. 'g',
           math.floor(red * 255), math.floor(green * 255), math.floor(blue * 255),
           rounded_bust_percent;
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

        hxiclam.bucket_weight = 0
        for k, v in pairs(hxiclam.bucket) do
            if (hxiclam.weights[k] ~= nil) then
                hxiclam.bucket_weight = hxiclam.bucket_weight +
                                            hxiclam.weights[k];
            end
        end
    end
end

-- Needed to move session data out of settings because of how Windower saves the settings
local function save_session_data()
    local filepath = ('%sdata/session_data'):format(windower.addon_path)
    local file = io.open(filepath, "w");
    if (file ~= nil) then
        file:write('bucket\n');
        file:write(('%s\n'):format(hxiclam.bucket_weight));
        file:write(('%s\n'):format(hxiclam.bucket_capacity));
        for k, v in pairs(hxiclam.bucket) do
            file:write(('%s:%d\n'):format(k, v));
        end

        file:write('session\n');
        file:write(('%s\n'):format(hxiclam.bucket_count));
        file:write(('%s\n'):format(hxiclam.item_count));
        for k, v in pairs(hxiclam.rewards) do
            file:write(('%s:%d\n'):format(k, v));
        end
        file:close();
    end
end

local function load_session_data()
    local filepath = ('%sdata/session_data'):format(windower.addon_path);
    if (windower.file_exists(filepath)) then
        local file = io.open(filepath, 'r');
        if (file ~= nil) then
            local trash = file:read();
            hxiclam.bucket_weight = file:read();
            hxiclam.bucket_capacity = file:read();
            local line = file:read();
            while (line ~= 'session') do
                local splitTable = split(line, ':');
                hxiclam.bucket[splitTable[1]] = splitTable[2];
                line = file:read();
            end
            hxiclam.bucket_count = file:read();
            hxiclam.item_count = file:read();
            line = file:read();
            while (line ~= nil) do
                local splitTable = split(line, ':');
                hxiclam.rewards[splitTable[1]] = splitTable[2];
                line = file:read();
            end
            file:close();
        end
    end
end

local function clear_rewards()
    hxiclam.last_attempt = os.time();
    hxiclam.first_attempt = 0;
    hxiclam.rewards = {};
    hxiclam.item_count = 0;
    hxiclam.bucket_count = 0;
    save_session_data();
end

local function clear_bucket()
    hxiclam.bucket = {};
    hxiclam.bucket_weight = 0;
    hxiclam.bucket_capacity = 50;
    save_session_data();
end

local function play_sound()
    if (hxiclam.settings.enable_tone[1] == true and hxiclam.play_tone == true) then
        windower.play_sound(("%sShared/tones/%s"):format(windower.addon_path, hxiclam.settings.tone));
        hxiclam.play_tone = false;
    end
end
----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------
--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
windower.register_event('load', function()
    update_pricing();
    update_weights();
    update_probabilities();
    load_session_data();
    if (hxiclam.settings.reset_on_load[1]) then
        notice('Reset bucket and session on reload.');
        clear_rewards();
        clear_bucket();
    end

    local name = windower.ffxi.get_player().name
    if (name ~= nil and name:len() > 0) then logs.char_name = name; end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
windower.register_event('unload', function()
    -- Save the current settings..
    hxiclam.settings:save();
    save_session_data();
end);

--[[
* event: logout
* desc : Event called when the character logs out.
--]]
windower.register_event('logout', function()
    -- Save the current settings..
    hxiclam.settings:save();
    save_session_data();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
windower.register_event('addon command', function(command, ...)
    -- Parse the command arguments..
    command = command and command:lower() or '';
    local args = (...) and (...):lower() or '';

    -- Handle: //hxiclam save - Saves the current settings.
    if (command:match('save')) then
        update_pricing();
        update_weights();
        update_probabilities();
        hxiclam.settings:save();
        save_session_data();
        notice('Settings saved.');
        return;
    end

    -- Handle: //hxiclam reload - Reloads the current settings from disk.
    if (command:match('reload')) then
        config.reload(hxiclam.settings);
        update_pricing();
        update_weights();
        update_probabilities();
        notice('Settings reloaded.');
        return;
    end

    -- Handle: //hxiclam clear - Clears the current session and bucket info.
    -- Handle: //hxiclam clear bucket - Clears the current bucket info.
    -- Handle: //hxiclam clear session - Clears the current session info.
    if (command:match('clear')) then
        if (args:match('bucket')) then
            clear_bucket();
            notice('Cleared hxiclam bucket.');
        elseif (args:match('session')) then
            clear_rewards();
            notice('Cleared hxiclam session.');
        else
            clear_rewards();
            clear_bucket();
            notice('Cleared hxiclam bucket and session.');
        end
        return;
    end

    -- Handle: //hxiclam show - Shows the hxiclam object.
    if (command:match('show')) then
        if (args:match('session')) then
            hxiclam.settings.session_view = 2;
        elseif (args:match('summary')) then
            hxiclam.settings.session_view = 1;
        else
            -- reset last dig on show command to reset timeout counter
            hxiclam.last_attempt = os.time();
            hxiclam.settings.visible[1] = true;
        end
        return;
    end

    -- Handle: //hxiclam hide - Hides the hxiclam object.
    if (command:match('hide')) then
        if (args:match('session')) then
            hxiclam.settings.session_view = 0;
        else
            hxiclam.settings.visible[1] = false;
        end
        return;
    end

    -- Handle: //hxiclam update - Updates the current pricing and weight info for items.
    -- Handle: //hxiclam update pricing - Updates the current pricing info for items.
    -- Handle: //hxiclam update weights - Updates the current weight info for items.
    if (command:match('update')) then
        if (args:match('pricing')) then
            update_pricing();
            notice('Pricing updated.');
        elseif (args:match('weights')) then
            update_weights();
            notice('Weights updated.');
        else
            update_pricing();
            update_weights();
            notice('Pricing and weights updated.');
        end
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
windower.register_event('incoming text',
                        function(original, modified, original_mode,
                                 modified_mode, blocked)
    if (original_mode == 142 or original_mode == 148 or original_mode == 150 or
        original_mode == 151) then
        local message = string.lower(original);
        message = string.strip_colors(message);

        local bucket = string.match(message, "obtained key item: clamming kit");
        local item = string.match(message,
                                  "you find a[n]? (.*) and toss it into your bucket.*");
        local bucket_upgrade = string.match(message,
                                            "your clamming capacity has increased to (%d+) ponzes!");
        local bucket_turnin = string.match(message,
                                           "you return the clamming kit");
        local overweight = string.match(message,
                                        ".*for the bucket and its bottom breaks.*");
        local incident = string.match(message,
                                      ".*somthing jumps into your bucket.*"); -- need an example text of this

        -- Update last attempt timestamp if any clamming action occurs
        -- show hxiclam once a clamming action occurs
        if (bucket or item or bucket_turnin or overweight or incident) then
            hxiclam.last_attempt = os.time();
            if (hxiclam.first_attempt == 0) then
                hxiclam.first_attempt = os.time();
            end
            if (hxiclam.settings.visible[1] == false) then
                hxiclam.settings.visible[1] = true;
            end
        end

        -- Clear bucket and add to bucket count when a bucket is obtained.
        if (bucket) then
            clear_bucket();
            hxiclam.bucket_count = hxiclam.bucket_count + 1;
        elseif (item) then
            hxiclam.play_tone = true;
            -- Update last dig time and reset dig_timer
            hxiclam.settings.last_dig = os.time();

            if (hxiclam.settings.dig_timer_countdown) then
                hxiclam.settings.dig_timer = 10;
            else
                hxiclam.settings.dig_timer = 0;
            end

            -- Update bucket weight
            if (hxiclam.weights[item] ~= nil) then
                hxiclam.bucket_weight = hxiclam.bucket_weight +
                                            hxiclam.weights[item];
            end

            -- Update bucket item list
            if (hxiclam.bucket[item] == nil) then
                hxiclam.bucket[item] = 1;
            elseif (hxiclam.bucket[item] ~= nil) then
                hxiclam.bucket[item] = hxiclam.bucket[item] + 1;
            end

            -- Log the item
            if (hxiclam.settings.enable_logging[1]) then
                WriteLog('drop', item);
            end
        elseif (bucket_upgrade) then
            hxiclam.bucket_capacity = bucket_upgrade;
        elseif (bucket_turnin) then
            if (hxiclam.bucket ~= nil and hxiclam.bucket ~= {}) then
                for k, v in pairs(hxiclam.bucket) do
                    hxiclam.item_count = hxiclam.item_count + v;
                    if (hxiclam.rewards[k] == nil) then
                        hxiclam.rewards[k] = v;
                    elseif (hxiclam.rewards[k] ~= nil) then
                        hxiclam.rewards[k] = hxiclam.rewards[k] + v
                    end

                    -- Log the items turned in
                    if (hxiclam.settings.enable_logging[1]) then
                        for i = 1, v do
                            WriteLog('turnin', k);
                        end
                    end
                end
                clear_bucket();
            end
        end

        if (overweight or incident) then clear_bucket(); end
    end
end);

windower.register_event('prerender', function()
    local last_attempt_secs = os.time() - hxiclam.last_attempt;

    if (last_attempt_secs > hxiclam.settings.display_timeout[1]) then
        hxiclam.settings.visible[1] = false;
    end

    -- Hide the hxiclam object if not visible..
    if (not hxiclam.settings.visible[1]) then
        hxiclam_display:hide();
        return;
    end

    local elapsed_time = os.time() - math.floor(hxiclam.first_attempt);
    local timer_display = hxiclam.settings.dig_timer;

    if (hxiclam.settings.dig_timer_countdown) then
        local dig_diff = (math.floor(hxiclam.settings.last_dig) + 10) -
                             os.time();
        if (dig_diff < hxiclam.settings.dig_timer) then
            hxiclam.settings.dig_timer = dig_diff;
        end

        timer_display = hxiclam.settings.dig_timer;
        if (timer_display <= 0) then timer_display = 'Dig Ready'; end
    else
        local dig_diff = os.time() - math.floor(hxiclam.settings.last_dig);
        if (dig_diff > hxiclam.settings.dig_timer) then
            hxiclam.settings.dig_timer = dig_diff;
        end

        timer_display = hxiclam.settings.dig_timer;
        if (timer_display >= 10) then timer_display = 'Dig Ready'; end
    end

    local total_worth = 0;
    local bucket_total = 0;

    local output_text = 'Bucket Stats:';
    output_text = output_text .. '\nBucket Weight: ';
    if ((hxiclam.bucket_capacity - hxiclam.bucket_weight) <=
        hxiclam.settings.bucket_weight_crit_threshold[1]) then
        local color = hxiclam.settings.bucket_weight_crit_color;
        output_text = output_text ..
                          ('%d/%d'):format(hxiclam.bucket_weight,
                                           hxiclam.bucket_capacity):text_color(
                              color[1], color[2], color[3]);
    elseif ((hxiclam.bucket_capacity - hxiclam.bucket_weight) <=
        hxiclam.settings.bucket_weight_warn_threshold[1]) then
        local color = hxiclam.settings.bucket_weight_warn_color;
        output_text = output_text ..
                          ('%d/%d'):format(hxiclam.bucket_weight,
                                           hxiclam.bucket_capacity):text_color(
                              color[1], color[2], color[3]);
    else
        output_text = output_text ..
                          ('%d/%d'):format(hxiclam.bucket_weight,
                                           hxiclam.bucket_capacity);
    end

    output_text = output_text .. '\nDig Timer: ';
    if (timer_display == 'Dig Ready') then
        local color = hxiclam.settings.dig_timer_ready_color;
        output_text = output_text ..
                          timer_display:text_color(color[1], color[2], color[3]);
        play_sound();
    else
        output_text = output_text .. tostring(timer_display);
    end

    local bucket_contents = '';
    for k, v in pairs(hxiclam.bucket) do
        local itemTotal = 0;
        if (hxiclam.pricing[k] ~= nil) then
            itemTotal = v * hxiclam.pricing[k];
            bucket_total = bucket_total + itemTotal;
        end

        if (bucket_contents == '') then
            bucket_contents = k .. ': ' .. 'x' .. format_int(v) .. ' (' ..
                                  format_int(itemTotal) .. 'g)';
        else
            bucket_contents = bucket_contents .. '\n' .. k .. ': ' .. 'x' ..
                                  format_int(v) .. ' (' .. format_int(itemTotal) ..
                                  'g)';
        end
    end

    if (hxiclam.settings.clamming.bucket_subtract[1]) then
        bucket_total = bucket_total - hxiclam.settings.clamming.bucket_cost[1];
        output_text = output_text .. '\nBucket Profit: ' ..
                          format_int(bucket_total) .. 'g';
    else
        output_text = output_text .. '\nBucket Revenue: ' ..
                          format_int(bucket_total) .. 'g';
    end

    local ev_text, ev_red, ev_green, ev_blue, bust_percent =
        get_expected_value_display();
    local expected_value_text = ev_text:text_color(ev_red, ev_green, ev_blue);
    output_text = output_text .. '\nExpected Value: ' .. expected_value_text;
    if (bust_percent ~= nil) then
        local bust_text = (' (' .. tostring(bust_percent) .. '% to bust)'):
                              text_color(255, 0, 0);
        output_text = output_text .. bust_text;
    end
    output_text = output_text .. '\n--------------------------';

    output_text = output_text .. '\n' .. bucket_contents;

    if (hxiclam.settings.session_view > 0) then
        output_text = output_text .. '\n--------------------------';
        output_text = output_text .. '\n--------------------------';
        output_text = output_text .. '\nSession Stats:';
        output_text = output_text .. '\nBuckets Cost: ' ..
                          format_int(
                              hxiclam.bucket_count *
                                  hxiclam.settings.clamming.bucket_cost[1]);
        output_text = output_text .. '\nItems Dug: ' ..
                          tostring(hxiclam.item_count);
        output_text = output_text .. '\n--------------------------';

        for k, v in pairs(hxiclam.rewards) do
            local itemTotal = 0;
            if (hxiclam.pricing[k] ~= nil) then
                total_worth = total_worth + hxiclam.pricing[k] * v;
                itemTotal = v * hxiclam.pricing[k];
            end

            if (hxiclam.settings.session_view > 1) then
                output_text = output_text .. '\n' .. k .. ': ' .. 'x' ..
                                  format_int(v) .. ' (' .. format_int(itemTotal) ..
                                  'g)';
            end
        end
        if (hxiclam.settings.session_view > 1) then
            output_text = output_text .. '\n--------------------------';
        end

        if (hxiclam.settings.clamming.bucket_subtract[1]) then
            total_worth = total_worth -
                              (hxiclam.bucket_count *
                                  hxiclam.settings.clamming.bucket_cost[1]);
            -- only update gil_per_hour every 3 seconds
            if ((os.time() % 3) == 0) then
                hxiclam.gil_per_hour = math.floor(
                                           (total_worth / elapsed_time) * 3600);
            end
            output_text = output_text .. '\nTotal Profit: ' ..
                              format_int(total_worth) .. 'g' .. ' (' ..
                              format_int(hxiclam.gil_per_hour) .. ' gph)';
        else
            -- only update gil_per_hour every 3 seconds
            if ((os.time() % 3) == 0) then
                hxiclam.gil_per_hour = math.floor(
                                           (total_worth / elapsed_time) * 3600);
            end
            output_text = output_text .. 'Total Revenue: ' ..
                              format_int(total_worth) .. 'g' .. ' (' ..
                              format_int(hxiclam.gil_per_hour) .. ' gph)';
        end
    end
    hxiclam_display:text(output_text);

    if (not hxiclam_display:visible()) then hxiclam_display:show(); end
end);

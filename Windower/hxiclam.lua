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
--]]

_addon.name      = 'hxiclam';
_addon.author    = 'jimmy58663';
_addon.version   = '1.2.2';
--_addon.desc      = 'HorizonXI clamming tracker addon.';
--_addon.link      = 'https://github.com/jimmy58663/HXIClam';
_addon.commands  = {'hxiclam'};

require('tables');
require('strings');
local logger = require('logger');
local config = require('config');
local data = require('constants');
local texts = require('texts');

local logs = T{
	drop_log_dir = 'drops',
	turnin_log_dir = 'turnins',
	char_name = nil,
};

-- Default Settings
local default_settings = T{
    visible = T{ true, },
	display_timeout = T{ 600 },
    item_index = data.ItemIndex,
	item_weight_index = data.ItemWeightIndex,
	enable_logging = T{ true },

    -- Clamming Display Settings
    clamming = T{ 
        bucket_cost = T{ 500 },
        bucket_subtract = T{ true, },
    },
    reset_on_load = T{ false, },
    first_attempt = 0,
    rewards = { },
	bucket_count = 0,
	item_count = 0,
	session_view = 1, -- 0 no session stats, 1 session summary, 2 session details
	
	bucket = { },
	bucket_weight = 0,
	bucket_capacity = 50,
	bucket_weight_warn_color = {255, 255, 0}, --yellow
	bucket_weight_warn_threshold = T{ 20 },
	bucket_weight_crit_color = {255, 0, 0}, --red
	bucket_weight_crit_threshold = T{ 7 },
	dig_timer_ready_color = {0, 255, 0}, --green
	bucket_weight_font_size = 16,
	
	
	last_dig = 0,
	dig_timer = 0,
	dig_timer_countdown = true,

	--Text object display settings
	display = {
		padding = 1,
		pos = {
			x = 100,
			y = 100,
		},
		text = {
			font = 'Arial',
			size = 14,
			--red = ,
			--green = ,
			--blue = ,
			--alpha = ,
			--stroke = {
				--width = ,
				--red = ,
				--green = ,
				--blue = ,
				--alpha = ,
			--},
		},
		flags = {
			italic = false,
			bold = false,
			right = false,
			bottom = false,
		},
		bg = {
			--red = ,
			--green = ,
			--blue = ,
			alpha = 200,
			visible = true,
		},
	},
};

-- HXIClam Variables
local hxiclam = T{
    settings = config.load(default_settings),

    -- hxiclam movement variables..
    move = T{
        dragging = false,
        drag_x = 0,
        drag_y = 0,
        shift_down = false,
    },

    -- Editor variables..
    editor = T{
        is_open = T{ false, },
    },

    last_attempt = os.clock(),
    pricing = T{ },
	weights = T{ },
    gil_per_hour = 0,
};

-- Display setup
local hxiclam_display = texts.new('', hxiclam.settings.display);
hxiclam_display:draggable(true);

----------------------------------------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------------------------------------
local function split(inputstr, sep)
    if sep == nil then
        sep = '%s';
    end
    local t = {};
    for str in string.gmatch(inputstr, '([^'..sep..']+)') do
        table.insert(t, str);
    end
    return t;
end

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
local function format_int(number)
    if (string.len(number) < 4) then
        return number
    end
    if (number ~= nil and number ~= '' and type(number) == 'number') then
        local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)');

        -- we sometimes get a nil int from the above tostring, just return number in those cases
        if (int == nil) then
            return number
        end

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
	local log_file_name = ('%s_%.4u.%.2u.%.2u.log'):format(logs.char_name, datetime.year, datetime.month, datetime.day);
	local full_directory = ('%slogs/%s'):format(windower.addon_path, logdir);

    --Set up log dirs if they do not exist
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
        windower.add_to_chat(38, ('[%s] Invalid command syntax for command: //%s'):format(_addon.name, _addon.name));
    else
        windower.add_to_chat(121, ('[%s] Available commands:'):format(_addon.name));
    end

    local cmds = T{
        { '//hxiclam save', 'Saves the current settings to disk.' },
        { '//hxiclam reload', 'Reloads the current settings from disk.' },
        { '//hxiclam clear', 'Clears the HXIClam bucket and session stats.' },
		{ '//hxiclam clear bucket', 'Clears the HXIClam bucket stats.' },
		{ '//hxiclam clear session', 'Clears the HXIClam session stats.' },
        { '//hxiclam show', 'Shows the HXIClam information.' },
		{ '//hxiclam show session', 'Shows the HXIClam session stats.' },
		{ '//hxiclam show summary', 'Shows the HXIClam session summary.' },
        { '//hxiclam hide', 'Hides the HXIClam information.' },
		{ '//hxiclam hide session', 'Hides the HXIClam session stats.' },
		{ '//hxiclam update', 'Updates the HXIClam item pricing and weight info.' },
		{ '//hxiclam update pricing', 'Updates the HXIClam item pricing info.' },
		{ '//hxiclam update weights', 'Updates the HXIClam item weight info.' },
    };

    -- Print the command list..
    for k, v in pairs(cmds) do
        windower.add_to_chat(121, ('[%s] Usage: %s - %s'):format(_addon.name, v[1], v[2]));
    end;
end

local function update_pricing()
    local itemname
	local itemvalue
	for k, v in pairs(hxiclam.settings.item_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then
                itemname = v2;
            end
            if (k2 == 2) then
                itemvalue = v2;
            end
        end

        hxiclam.pricing[itemname] = itemvalue;
    end
end

local function update_weights()
    local itemname
	local itemvalue
	for k, v in pairs(hxiclam.settings.item_weight_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then
                itemname = v2;
            end
            if (k2 == 2) then
                itemvalue = v2;
            end
        end

        hxiclam.weights[itemname] = itemvalue;
    end
end

local function clear_rewards()
    hxiclam.last_attempt = os.time();
    hxiclam.settings.first_attempt = 0;
    hxiclam.settings.rewards = { };
    hxiclam.settings.item_count = 0;
	hxiclam.settings.bucket_count = 0;
end

local function clear_bucket()
	hxiclam.settings.bucket = { };
	hxiclam.settings.bucket_weight = 0;
	hxiclam.settings.bucket_capacity = 50;
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------
--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
windower.register_event('load', function ()
    update_pricing();
	update_weights();
    if ( hxiclam.settings.reset_on_load[1] ) then
        notice('Reset bucket and session on reload.');
        clear_rewards();
		clear_bucket();
    end

	local name = windower.ffxi.get_player().name
    if (name ~= nil and name:len() > 0) then
        logs.char_name = name;
    end
end);


--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
windower.register_event('unload', function ()
    -- Save the current settings..
    hxiclam.settings:save();
end);

--[[
* event: logout
* desc : Event called when the character logs out.
--]]
windower.register_event('logout', function()
	-- Save the current settings..
    hxiclam.settings:save();
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
        hxiclam.settings:save();
        notice('Settings saved.');
        return;
    end

    -- Handle: //hxiclam reload - Reloads the current settings from disk.
    if (command:match('reload')) then
        config.reload(hxiclam.settings);
		update_pricing();
		update_weights();
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
windower.register_event('incoming text', function (original, modified, original_mode, modified_mode, blocked)
	if (original_mode == 142 or original_mode == 150 or original_mode == 151) then
		message = string.lower(original);
		message = string.strip_colors(message);
		
		local bucket = string.match(message, "obtained key item: clamming kit");
		local item = string.match(message, "you find a[n]? (.*) and toss it into your bucket.*");
		local bucket_upgrade = string.match(message, "your clamming capacity has increased to (%d+) ponzes!");
		local bucket_turnin = string.match(message, "you return the clamming kit");
		local overweight = string.match(message, ".*for the bucket and its bottom breaks.*");
		local incident = string.match(message, ".*somthing jumps into your bucket.*"); --need an example text of this

		-- Update last attempt timestamp if any clamming action occurs
		-- show hxiclam once a clamming action occurs
		if (bucket or item or bucket_turnin or overweight or incident) then
			hxiclam.last_attempt = os.time();
			if (hxiclam.settings.first_attempt == 0) then
				hxiclam.settings.first_attempt = os.time();
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
			--Update last dig time and reset dig_timer
			hxiclam.settings.last_dig = os.time();
			
			if (hxiclam.settings.dig_timer_countdown) then
				hxiclam.settings.dig_timer = 10;
			else
				hxiclam.settings.dig_timer = 0;
			end

			-- Update bucket weight
			if (hxiclam.weights[item] ~= nil) then
				hxiclam.settings.bucket_weight = hxiclam.settings.bucket_weight + hxiclam.weights[item];
			end
			
			-- Update bucket item list
			item = item:gsub("%s+", "_");
			if (hxiclam.settings.bucket[item] == nil) then
				hxiclam.settings.bucket[item] = 1;
			elseif (hxiclam.settings.bucket[item] ~= nil) then
				hxiclam.settings.bucket[item] = hxiclam.settings.bucket[item] + 1;
			end

			-- Log the item
			if (hxiclam.settings.enable_logging[1]) then
				WriteLog('drop', item);
			end
		elseif (bucket_upgrade) then
			hxiclam.settings.bucket_capacity = bucket_upgrade;
		elseif (bucket_turnin) then
			if (hxiclam.settings.bucket ~= nil and hxiclam.settings.bucket ~= { }) then
				for k,v in pairs(hxiclam.settings.bucket) do
					hxiclam.settings.item_count = hxiclam.settings.item_count + v;
					if (hxiclam.settings.rewards[k] == nil) then
						hxiclam.settings.rewards[k] = v;
					elseif (hxiclam.settings.rewards[k] ~= nil) then
						hxiclam.settings.rewards[k] = hxiclam.settings.rewards[k] + v
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

		if (overweight or incident) then
			clear_bucket();
		end
	end
end);

windower.register_event('prerender', function()
	local last_attempt_secs = os.time() - hxiclam.last_attempt;

	if (last_attempt_secs > hxiclam.settings.display_timeout[1]) then
		hxiclam.settings.visible[1] = false;
	end

	--Hide the hxiclam object if not visible..
	if (not hxiclam.settings.visible[1]) then
		hxiclam_display:hide();
		return;
	end

	local elapsed_time = os.time() - math.floor(hxiclam.settings.first_attempt);
	local timer_display = hxiclam.settings.dig_timer;

	if (hxiclam.settings.dig_timer_countdown) then
		local dig_diff = (math.floor(hxiclam.settings.last_dig) + 10) - os.time();
		if (dig_diff < hxiclam.settings.dig_timer) then
			hxiclam.settings.dig_timer = dig_diff;
		end
		
		timer_display = hxiclam.settings.dig_timer;
		if (timer_display <= 0) then
			timer_display = 'Dig Ready';
		end
	else
		local dig_diff = os.time() - math.floor(hxiclam.settings.last_dig);
		if (dig_diff > hxiclam.settings.dig_timer) then
			hxiclam.settings.dig_timer = dig_diff;
		end
		
		timer_display = hxiclam.settings.dig_timer;
		if (timer_display >= 10) then
			timer_display = 'Dig Ready';
		end
	end

	local total_worth = 0;
	local bucket_total = 0;

	local output_text = 'Bucket Stats:';
	output_text = output_text .. '\nBucket Weight: ';
	--Need to determine if there is a way to change text colors for specific texts. Might need to use special characters that FFXI can interpret. Battlemod may be a good place to look
	if ((hxiclam.settings.bucket_capacity - hxiclam.settings.bucket_weight) <= hxiclam.settings.bucket_weight_crit_threshold[1]) then
		local color = hxiclam.settings.bucket_weight_crit_color;
		output_text = output_text .. ('%d/%d'):format(hxiclam.settings.bucket_weight, hxiclam.settings.bucket_capacity):text_color(color[1], color[2], color[3]);
	elseif ((hxiclam.settings.bucket_capacity - hxiclam.settings.bucket_weight) <= hxiclam.settings.bucket_weight_warn_threshold[1]) then
		local color = hxiclam.settings.bucket_weight_warn_color;
		output_text = output_text .. ('%d/%d'):format(hxiclam.settings.bucket_weight, hxiclam.settings.bucket_capacity):text_color(color[1], color[2], color[3]);
	else
		output_text = output_text .. ('%d/%d'):format(hxiclam.settings.bucket_weight, hxiclam.settings.bucket_capacity);
	end

	output_text = output_text .. '\nDig Timer: ';
	if (timer_display == 'Dig Ready') then
		local color = hxiclam.settings.dig_timer_ready_color;
		output_text = output_text .. timer_display:text_color(color[1], color[2], color[3]);
	else
		output_text = output_text .. tostring(timer_display);
	end

	local bucket_contents = '';
	for k,v in pairs(hxiclam.settings.bucket) do
		local itemTotal = 0;
		k = k:gsub("_", " ");
		if (hxiclam.pricing[k] ~= nil) then
			bucket_total = bucket_total + hxiclam.pricing[k] * v;
			itemTotal = v * hxiclam.pricing[k];
		end

		if (bucket_contents == '') then
			bucket_contents = k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
		else
			bucket_contents = bucket_contents .. '\n' .. k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
		end
	end

	if (hxiclam.settings.clamming.bucket_subtract[1]) then
		bucket_total = bucket_total - hxiclam.settings.clamming.bucket_cost[1];
		output_text = output_text .. '\nBucket Profit: ' .. format_int(bucket_total) .. 'g';
	else
		output_text = output_text .. '\nBucket Revenue: ' .. format_int(bucket_total) .. 'g';
	end
	output_text = output_text .. '\n--------------------------';

	output_text = output_text .. '\n' .. bucket_contents;

	if (hxiclam.settings.session_view > 0) then
		output_text = output_text .. '\n--------------------------';
		output_text = output_text .. '\n--------------------------';
		output_text = output_text .. '\nSession Stats:';
		output_text = output_text .. '\nBuckets Cost: ' .. format_int(hxiclam.settings.bucket_count * hxiclam.settings.clamming.bucket_cost[1]);
		output_text = output_text .. '\nItems Dug: ' .. tostring(hxiclam.settings.item_count);
		output_text = output_text .. '\n--------------------------';
		
		for k,v in pairs(hxiclam.settings.rewards) do
			local itemTotal = 0;
			k = k:gsub("_", " ");
			if (hxiclam.pricing[k] ~= nil) then
				total_worth = total_worth + hxiclam.pricing[k] * v;
				itemTotal = v * hxiclam.pricing[k];
			end

			if (hxiclam.settings.session_view > 1) then
				output_text = output_text .. '\n' .. k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
			end
		end
		if (hxiclam.settings.session_view > 1) then
			output_text = output_text .. '\n--------------------------';
		end

		if (hxiclam.settings.clamming.bucket_subtract[1]) then
			total_worth = total_worth - (hxiclam.settings.bucket_count * hxiclam.settings.clamming.bucket_cost[1]);
			-- only update gil_per_hour every 3 seconds
			if ((os.time() % 3) == 0) then
				hxiclam.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600);
			end
			output_text = output_text .. '\nTotal Profit: ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hxiclam.gil_per_hour) .. ' gph)';
		else
			-- only update gil_per_hour every 3 seconds
			if ((os.time() % 3) == 0) then
				hxiclam.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600);
			end
			output_text = output_text .. 'Total Revenue: ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hxiclam.gil_per_hour) .. ' gph)';
		end
	end
	hxiclam_display:text(output_text);

	if (not hxiclam_display:visible()) then
		hxiclam_display:show();
	end
end);
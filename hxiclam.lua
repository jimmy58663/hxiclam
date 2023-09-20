--[[
* Goal of this addon is to calculate weight and cost of items obtained through clamming.
*
* Used SlowedHaste HGather as a base for this addon: https://github.com/SlowedHaste/HGather
--]]

addon.name      = 'hxiclam';
addon.author    = 'jimmy58663';
addon.version   = '1.0';
addon.desc      = 'HorizonXI clamming tracker addon.';
addon.link      = 'https://github.com/jimmy58663/HXIClam';
addon.commands  = {'/hxiclam'};

require('common');
local chat      = require('chat');
local d3d       = require('d3d8');
local ffi       = require('ffi');
local fonts     = require('fonts');
local imgui     = require('imgui');
local prims     = require('primitives');
local scaling   = require('scaling');
local settings  = require('settings');
local data      = require('constants');

local C = ffi.C;
local d3d8dev = d3d.get_device();

-- Default Settings
local default_settings = T{
    visible = T{ true, },
    moon_display = T{ true, },
    display_timeout = T{ 600 },
    opacity = T{ 1.0, },
    padding = T{ 1.0, },
    scale = T{ 1.0, },
    item_index = ItemIndex,
	item_weight_index = ItemWeightIndex,
    font_scale = T{ 1.0 },
    x = T{ 100, },
    y = T{ 100, },

    -- Choco Digging Display Settings
    clamming = T{ 
        bucket_cost = T{ 500 },
        bucket_subtract = T{ true, },
    },
    reset_on_load = T{ false },
    first_attempt = 0,
    rewards = { },
	bucket_count = 0,
	item_count = 0,
	
	bucket = { },
	bucket_weight = 0,
	
	last_dig = 0,
	dig_timer = 0,
};

-- HXIClam Variables
local hxiclam = T{
    settings = settings.load(default_settings),

    -- HGather movement variables..
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

    last_attempt = ashita.time.clock()['ms'],
    pricing = T{ },
	weights = T{ },
    gil_per_hour = 0,
};

--[[
* Renders the HXIClam settings editor.
--]]
local function render_editor()
    if (not hxiclam.editor.is_open[1]) then
        return;
    end

    imgui.SetNextWindowSize({ 500, 600, });
    imgui.SetNextWindowSizeConstraints({ 500, 600, }, { FLT_MAX, FLT_MAX, });
    if (imgui.Begin('HXIClam##Config', hxiclam.editor.is_open)) then

        -- imgui.SameLine();
        if (imgui.Button('Save Settings')) then
            settings.save();
            print(chat.header(addon.name):append(chat.message('Settings saved.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reload Settings')) then
            settings.reload();
            print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reset Settings')) then
            settings.reset();
            print(chat.header(addon.name):append(chat.message('Settings reset to defaults.')));
        end
		imgui.SameLine();
        if (imgui.Button('Update Pricing')) then
            update_pricing();
            print(chat.header(addon.name):append(chat.message('Pricing updated.')));
        end
        if (imgui.Button('Clear Session')) then
            clear_rewards();
            print(chat.header(addon.name):append(chat.message('Cleared session.')));
        end
		imgui.SameLine();
        if (imgui.Button('Clear Bucket')) then
            clear_bucket();
            print(chat.header(addon.name):append(chat.message('Cleared bucket.')));
        end
		imgui.SameLine();
        if (imgui.Button('Clear All')) then
            clear_rewards();
			clear_bucket();
            print(chat.header(addon.name):append(chat.message('Cleared session and bucket.')));
        end
		imgui.SameLine();
		if (imgui.Button('Update Weights')) then
            update_weights();
            print(chat.header(addon.name):append(chat.message('Weights updated.')));
        end

        imgui.Separator();

        if (imgui.BeginTabBar('##hxiclam_tabbar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
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

function render_general_config(settings)
    imgui.Text('General Settings');
    imgui.BeginChild('settings_general', { 0, 250, }, true);
        if( imgui.Checkbox('Visible', hxiclam.settings.visible) ) then
            -- if the checkbox is interacted with, reset the last_attempt
            -- to force the window back open
            hgather.last_attempt = ashita.time.clock()['ms'];
        end
        imgui.ShowHelp('Toggles if HXIClam is visible or not.');
        imgui.SliderFloat('Opacity', hxiclam.settings.opacity, 0.125, 1.0, '%.3f');
        imgui.ShowHelp('The opacity of the HXIClam window.');
        imgui.SliderFloat('Font Scale', hxiclam.settings.font_scale, 0.1, 2.0, '%.3f');
        imgui.ShowHelp('The scaling of the font size.');
        imgui.InputInt('Display Timeout', hxiclam.settings.display_timeout);
        imgui.ShowHelp('How long should the display window stay open after the last dig.');

        local pos = { hxiclam.settings.x[1], hxiclam.settings.y[1] };
        if (imgui.InputInt2('Position', pos)) then
            hxiclam.settings.x[1] = pos[1];
            hxiclam.settings.y[1] = pos[2];
        end
        imgui.ShowHelp('The position of HXIClam on screen.');

        imgui.Checkbox('Moon Display', hxiclam.settings.moon_display);
        imgui.ShowHelp('Toggles if moon phase / percent is shown.');
        imgui.Checkbox('Reset Rewards On Load', hxiclam.settings.reset_on_load);
        imgui.ShowHelp('Toggles whether we reset rewards each time the addon is loaded.');
    imgui.EndChild();
    imgui.Text('Clamming Display Settings');
    imgui.BeginChild('clam_general', { 0, 110, }, true);
        imgui.Checkbox('Subtract Bucket Cost', hxiclam.settings.clamming.bucket_subtract);
        imgui.ShowHelp('Toggles if bucket costs are automatically subtracted from gil earned.');
    imgui.EndChild();
end

function render_item_price_config(settings)
    imgui.Text('Item Prices');
    imgui.BeginChild('settings_general', { 0, 470, }, true);

        imgui.InputInt('Bucket Cost', hxiclam.settings.clamming.bucket_cost);
        imgui.ShowHelp('Cost of a single bucket.');

        imgui.Separator();

        local temp_strings = T{ };
        temp_strings[1] = table.concat(hxiclam.settings.item_index, '\n');
        if(imgui.InputTextMultiline('\nItem Prices', temp_strings, 8192, {0, 420})) then
            hxiclam.settings.item_index = split(temp_strings[1], '\n');
            table.sort(hxiclam.settings.item_index);
        end
        imgui.ShowHelp('Individual items, lowercase, separated by : with price on right side.');
    imgui.EndChild();
end

function render_item_weight_config(settings)
    imgui.Text('Item Weights');
    imgui.BeginChild('settings_general', { 0, 470, }, true);

        local temp_strings = T{ };
        temp_strings[1] = table.concat(hxiclam.settings.item_weight_index, '\n');
        if(imgui.InputTextMultiline('\nItem Weights', temp_strings, 8192, {0, 420})) then
            hxiclam.settings.item_weight_index = split(temp_strings[1], '\n');
            table.sort(hxiclam.settings.item_weight_index);
        end
        imgui.ShowHelp('Individual items, lowercase, separated by : with weight on right side.');
    imgui.EndChild();
end

function split(inputstr, sep)
    if sep == nil then
        sep = '%s';
    end
    local t = {};
    for str in string.gmatch(inputstr, '([^'..sep..']+)') do
        table.insert(t, str);
    end
    return t;
end

function update_pricing() 
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

function update_weights() 
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

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
function format_int(number)
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

----------------------------------------------------------------------------------------------------
-- Format the output used in display window and report
----------------------------------------------------------------------------------------------------
function format_output()
    local elapsed_time = ashita.time.clock()['s'] - math.floor(hxiclam.settings.first_attempt / 1000.0);
	local dig_diff = ashita.time.clock()['s'] - math.floor(hxiclam.settings.last_dig / 1000.0);
	if (dig_diff > hxiclam.settings.dig_timer) then
		hxiclam.settings.dig_timer = dig_diff
	end
	
	local timer_display = hxiclam.settings.dig_timer
	if (timer_display >= 10) then
		timer_display = "Dig Ready"
	end

    local total_worth = 0;
	local bucket_total = 0;
    local moon_table = GetMoon();
    local moon_phase = moon_table.MoonPhase;
    local moon_percent = moon_table.MoonPhasePercent;

    local output_text = '';
    
	output_text = '~~~~~~ HXIClam Bucket ~~~~~~~';
	output_text = output_text .. '\nBucket Weight: ' .. hxiclam.settings.bucket_weight;
	output_text = output_text .. '\nDig Timer: ' .. timer_display;
	
	if (hxiclam.settings.clamming.bucket_subtract[1]) then
        bucket_total = bucket_total - hxiclam.settings.clamming.bucket_cost[1];
		output_text = output_text .. '\nBucket Profit: ' .. format_int(bucket_total) .. 'g';
    else
        output_text = output_text .. '\nBucket Revenue: ' .. format_int(bucket_total) .. 'g';
    end
	
	-- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~';

    for k,v in pairs(hxiclam.settings.bucket) do
        itemTotal = 0;
        if (hxiclam.pricing[k] ~= nil) then
            bucket_total = bucket_total + hxiclam.pricing[k] * v;
            itemTotal = v * hxiclam.pricing[k];
        end
              
        output_text = output_text .. '\n' .. k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
    end
	
	-- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n';
	
	
	
    output_text = output_text .. '\n~~~~~~ HXIClam Session ~~~~~~';
    output_text = output_text .. '\nBuckets Cost: ' .. format_int(hxiclam.settings.bucket_count * hxiclam.settings.clamming.bucket_cost[1]);
    output_text = output_text .. '\nItems Dug: ' .. hxiclam.settings.item_count;
    if (hxiclam.settings.moon_display[1]) then
        output_text = output_text .. '\nMoon: ' + moon_phase + ' ('+ moon_percent + '%%)';
    end

    -- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~';

    for k,v in pairs(hxiclam.settings.rewards) do
        itemTotal = 0;
        if (hxiclam.pricing[k] ~= nil) then
            total_worth = total_worth + hxiclam.pricing[k] * v;
            itemTotal = v * hxiclam.pricing[k];
        end
              
        output_text = output_text .. '\n' .. k .. ': ' .. 'x' .. format_int(v) .. ' (' .. format_int(itemTotal) .. 'g)';
    end

    -- imgui.Separator();
    output_text = output_text .. '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~';


    if (hxiclam.settings.clamming.bucket_subtract[1]) then
        total_worth = total_worth - (hxiclam.settings.bucket_count * hxiclam.settings.clamming.bucket_cost[1]);
        -- only update gil_per_hour every 3 seconds
        if ((ashita.time.clock()['s'] % 3) == 0) then
            hxiclam.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600); 
        end
        output_text = output_text .. '\nTotal Profit: ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hxiclam.gil_per_hour) .. ' gph)';
    else
        -- only update gil_per_hour every 3 seconds
        if ((ashita.time.clock()['s'] % 3) == 0) then
            hgather.gil_per_hour = math.floor((total_worth / elapsed_time) * 3600); 
        end
        output_text = output_text .. '\nTotal Revenue: ' .. format_int(total_worth) .. 'g' .. ' (' .. format_int(hxiclam.gil_per_hour) .. ' gph)';
    end
    return output_text;
end

function clear_rewards()
    hxiclam.last_attempt = ashita.time.clock()['ms'];
    hxiclam.settings.first_attempt = 0;
    hxiclam.settings.rewards = { };
    hxiclam.settings.item_count = 0;
	hxiclam.settings.bucket_count = 0;
end

function clear_bucket()
	hxiclam.settings.bucket = { };
	hxiclam.settings.bucket_weight = 0;
end
----------------------------------------------------------------------------------------------------
-- Helper functions borrowed from luashitacast
----------------------------------------------------------------------------------------------------
function GetTimestamp()
    local pVanaTime = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0);
    local pointer = ashita.memory.read_uint32(pVanaTime + 0x34);
    local rawTime = ashita.memory.read_uint32(pointer + 0x0C) + 92514960;
    local timestamp = {};
    timestamp.day = math.floor(rawTime / 3456);
    timestamp.hour = math.floor(rawTime / 144) % 24;
    timestamp.minute = math.floor((rawTime % 144) / 2.4);
    return timestamp;
end

function GetWeather()
    local pWeather = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0);
    local pointer = ashita.memory.read_uint32(pWeather + 0x02);
    return ashita.memory.read_uint8(pointer + 0);
end

function GetMoon()
    local timestamp = GetTimestamp();
    local moon_index = ((timestamp.day + 26) % 84) + 1;
    local moon_table = {};
    moon_table.MoonPhase = MoonPhase[moon_index];
    moon_table.MoonPhasePercent = MoonPhasePercent[moon_index];
    return moon_table;
end

--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/hxiclam', 'Toggles the HXIClam editor.' },
        { '/hxiclam edit', 'Toggles the HXIClam editor.' },
        { '/hxiclam save', 'Saves the current settings to disk.' },
        { '/hxiclam reload', 'Reloads the current settings from disk.' },
        { '/hxiclam report', 'Reports the current session to chat window.' },
        { '/hxiclam clear', 'Clears the HXIClam bucket and session stats.' },
		{ '/hxiclam clear bucket', 'Clears the HXIClam bucket stats.' },
		{ '/hxiclam clear session', 'Clears the HXIClam session stats.' },
        { '/hxiclam show', 'Shows the HXIClam information.' },
        { '/hxiclam hide', 'Hides the HXIClam information.' },
		{ '/hxiclam update', 'Updates the HXIClam item pricing and weight info.' },
		{ '/hxiclam update pricing', 'Updates the HXIClam item pricing info.' },
		{ '/hxiclam update weights', 'Updates the HXIClam item weight info.' },
    };

    -- Print the command list..
    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        hxiclam.settings = s;
    end

    -- Save the current settings..
    settings.save();
    update_pricing();
	update_weights();
end);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    update_pricing();
	update_weights();
    if ( hxiclam.settings.reset_on_load[1] ) then
        print('Reset bucket and session on reload.');
        clear_rewards();
		clear_bucket();
    end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    -- Save the current settings..
    settings.save();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/hxiclam')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /hxiclam - Toggles the hgather editor.
    -- Handle: /hxiclam edit - Toggles the hgather editor.
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
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        return;
    end

    -- Handle: /hxiclam report - Reports the current session to the chat window.
    if (#args >= 2 and args[2]:any('report')) then
        output_text = format_output();
        print(output_text);
        return;
    end

    -- Handle: /hxiclam clear - Clears the current session and bucket info.
	-- Handle: /hxiclam clear bucket - Clears the current bucket info.
	-- Handle: /hxiclam clear session - Clears the current session info.
    if (#args >= 2 and args[2]:any('clear')) then
        if (#args == 3 and args[3]:any('bucket')) then
			clear_bucket();
			print(chat.header(addon.name):append(chat.message('Cleared hxiclam bucket.')));
		elseif (#args == 3 and args[3]:any('session')) then
			clear_rewards();
			print(chat.header(addon.name):append(chat.message('Cleared hxiclam session.')));
		else
			clear_rewards();
			clear_bucket();
			print(chat.header(addon.name):append(chat.message('Cleared hxiclam bucket and session.')));
		end
        return;
    end

    -- Handle: /hxiclam show - Shows the hxiclam object.
    if (#args >= 2 and args[2]:any('show')) then
        -- reset last dig on show command to reset timeout counter
        hxiclam.last_attempt = ashita.time.clock()['ms'];
        hxiclam.settings.visible[1] = true;
        return;
    end

    -- Handle: /hxiclam hide - Hides the hxiclam object.
    if (#args >= 2 and args[2]:any('hide')) then
        hxiclam.settings.visible[1] = false;
        return;
    end
	
	-- Handle: /hxiclam update - Updates the current pricing and weight info for items.
	-- Handle: /hxiclam update pricing - Updates the current pricing info for items.
	-- Handle: /hxiclam update weights - Updates the current weight info for items.
    if (#args >= 2 and args[2]:any('update')) then
        if (#args == 3 and args[3]:any('pricing')) then
			update_pricing();
			print(chat.header(addon.name):append(chat.message('Pricing updated.')));
		elseif (#args == 3 and args[3]:any('weights')) then
			update_weights();
			print(chat.header(addon.name):append(chat.message('Weights updated.')));
		else
			update_pricing();
			update_weights();
			print(chat.header(addon.name):append(chat.message('Pricing and weights updated.')));
		end
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function (e)
    local last_attempt_secs = (ashita.time.clock()['ms'] - hxiclam.last_attempt) / 1000.0;
    local message = e.message;
    message = string.lower(message);
    message = string.strip_colors(message);

	local bucket = string.match(message, "obtained key item: clamming kit");
    local item = string.match(message, "you find a[n]? (.*) and toss it into your bucket.*");
	local bucket_turnin = string.match(message, "you return the clamming kit");
    local overweight = string.match(message, ".*for the bucket and its bottom breaks.*");
	local incident = string.match(message, ".*somthing jumps into your bucket.*"); --need an example text of this
	
	-- Update last attempt timestamp if any clamming action occurs
	if (bucket or item or bucket_turnin or overweight or incdient) then
		hxiclam.last_attempt = ashita.time.clock()['ms']
		if (hxiclam.settings.first_attempt == 0) then
			hxiclam.settings.first_attempt = ashita.time.clock()['ms'];
		end
		if (hxiclam.settings.visible[1] == false) then
            hxiclam.settings.visible[1] = true;
        end
	end
	
	-- show hxiclam once a bucket is obtained
	if (bucket) then
		hxiclam.settings.bucket_count = hxiclam.settings.bucket_count + 1;
	elseif (item) then
		--Update last dig time and reset dig_timer
		hxiclam.settings.last_dig = ashita.time.clock()['ms'];
		hxiclam.settings.dig_timer = 0;
		
		-- Update bucket item list
		if (hxiclam.settings.bucket[item] == nil) then
			hxiclam.settings.bucket[item] = 1;
		elseif (hxiclam.settings.bucket[item] ~= nil) then
			hxiclam.settings.bucket[item] = hxiclam.settings.bucket[item] + 1;
		end
		
		-- Update bucket weight
		if (hxiclam.weights[item] ~= nil) then
			hxiclam.settings.bucket_weight = hxiclam.settings.bucket_weight + hxiclam.weights[item];
		end
	elseif (bucket_turnin) then
		if (hxiclam.settings.bucket ~= nil and hxiclam.settings.bucket ~= { }) then
			for k,v in pairs(hxiclam.settings.bucket) do
				hxiclam.settings.item_count = hxiclam.settings.item_count + 1;
				if (hxiclam.settings.rewards[k] == nil) then
					hxiclam.settings.rewards[k] = 1;
				elseif (hxiclam.settings.rewards[k] ~= nil) then
					hxiclam.settings.rewards[k] = hxiclam.settings.rewards[k] + v
				end
			end
			clear_bucket();
		end
	end
	
	if (overweight or incident) then
		clear_bucket();
	end
end);

--[[
* event: d3d_beginscene
* desc : Event called when the Direct3D device is beginning a scene.
--]]
ashita.events.register('d3d_beginscene', 'beginscene_cb', function (isRenderingBackBuffer)
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    local last_attempt_secs = (ashita.time.clock()['ms'] - hxiclam.last_attempt) / 1000.0;
    render_editor();

    if (last_attempt_secs > hxiclam.settings.display_timeout[1]) then
        hxiclam.settings.visible[1] = false;
    end

    -- Hide the hxiclam object if not visible..
    if (not hxiclam.settings.visible[1]) then
        return;
    end

    -- Hide the hxiclam object if Ashita is currently hiding font objects..
    if (not AshitaCore:GetFontManager():GetVisible()) then
        return;
    end

    imgui.SetNextWindowBgAlpha(hxiclam.settings.opacity[1]);
    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
    if (imgui.Begin('HXIClam##Display', hxiclam.settings.visible[1], bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
	--if (imgui.Begin('HXIClam##Display', hxiclam.settings.visible[1], bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
		imgui.SetWindowFontScale(hxiclam.settings.font_scale[1]);
		output_text = format_output();
		imgui.Text(output_text);
    end
    imgui.End();

end);

--[[
* event: key
* desc : Event called when the addon is processing keyboard input. (WNDPROC)
--]]
ashita.events.register('key', 'key_callback', function (e)
    -- Key: VK_SHIFT
    if (e.wparam == 0x10) then
        hxiclam.move.shift_down = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10));
        return;
    end
end);

--[[
* event: mouse
* desc : Event called when the addon is processing mouse input. (WNDPROC)
--]]
ashita.events.register('mouse', 'mouse_cb', function (e)
    -- Tests if the given coords are within the equipmon area.
    local function hit_test(x, y)
        local e_x = hxiclam.settings.x[1];
        local e_y = hxiclam.settings.y[1];
        local e_w = ((32 * hxiclam.settings.scale[1]) * 4) + hxiclam.settings.padding[1] * 3;
        local e_h = ((32 * hxiclam.settings.scale[1]) * 4) + hxiclam.settings.padding[1] * 3;

        return ((e_x <= x) and (e_x + e_w) >= x) and ((e_y <= y) and (e_y + e_h) >= y);
    end

    -- Returns if the equipmon object is being dragged.
    local function is_dragging() return hxiclam.move.dragging; end

    -- Handle the various mouse messages..
    switch(e.message, {
        -- Event: Mouse Move
        [512] = (function ()
            hxiclam.settings.x[1] = e.x - hxiclam.move.drag_x;
            hxiclam.settings.y[1] = e.y - hxiclam.move.drag_y;

            e.blocked = true;
        end):cond(is_dragging),

        -- Event: Mouse Left Button Down
        [513] = (function ()
            if (hxiclam.move.shift_down) then
                hxiclam.move.dragging = true;
                hxiclam.move.drag_x = e.x - hxiclam.settings.x[1];
                hxiclam.move.drag_y = e.y - hxiclam.settings.y[1];

                e.blocked = true;
            end
        end):cond(hit_test:bindn(e.x, e.y)),

        -- Event: Mouse Left Button Up
        [514] = (function ()
            if (hxiclam.move.dragging) then
                hxiclam.move.dragging = false;

                e.blocked = true;
            end
        end):cond(is_dragging),

        -- Event: Mouse Wheel Scroll
        [522] = (function ()
            if (e.delta < 0) then
                hxiclam.settings.opacity[1] = hxiclam.settings.opacity[1] - 0.125;
            else
                hxiclam.settings.opacity[1] = hxiclam.settings.opacity[1] + 0.125;
            end
            hxiclam.settings.opacity[1] = hxiclam.settings.opacity[1]:clamp(0.125, 1);

            e.blocked = true;
        end):cond(hit_test:bindn(e.x, e.y)),
    });
end);
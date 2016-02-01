-- this script writes bytes 8 to 256 on the Legic MIM256
local clock = os.clock
function sleep(n)  -- seconds
   local t0 = clock()
   while clock() - t0 <= n do
   end
end

-- convert integer to hex
function num2hex(num)
   local hexstr = '0123456789abcdef'
   local s = ''
   while num > 0 do
      local mod = math.fmod(num, 16)
      s = string.sub(hexstr, mod+1, mod+1) .. s
      num = math.floor(num / 16)
   end
   if s == '' then s = '0' end
   return s
end

-- simple loop-write from 0x07 to 0xff
function main()
	local mycmd=""
        local startaddr=0
	local i
	core.clearCommandBuffer()
	for i = 8, 255 do
            if i <= 15 then 
		startaddr = "0x0" .. num2hex(i)
	    else
		startaddr = "0x" .. num2hex(i)
	    end
	    mycmd="hf legic write " .. startaddr .. " 0x01"
	    print(mycmd)
	    core.console( mycmd )
		
		-- got a 'cmd-buffer overflow' on my mac - so just wait a little
		-- works without that pause on my linux-box
		sleep(0.1)
	end
end

main()

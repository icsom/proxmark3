-- this script writes bytes 8 to 256 on the Legic MIM256
local clock = os.clock
function sleep(n)  -- seconds
   local t0 = clock()
   while clock() - t0 <= n do
   end
end

-- simple loop-write from 0x07 to 0xff
function main()
	local cmd = ''
	local i
	for i = 7, 255 do
	    cmd = ('hf legic write 0x%02x 0x01'):format(i)
	    print(cmd)
		core.clearCommandBuffer()
	    core.console(cmd)
		
		-- got a 'cmd-buffer overflow' on my mac - so just wait a little
		-- works without that pause on my linux-box
		sleep(0.1)
	end
end

main()

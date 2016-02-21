--[[
	script to create a clone-dump with new crc
  Author: mosci
  https://github.com/icsom/proxmark3/blob/master/client/scripts/Legic_clone.lua

	1. read tag-dump, xor byte 22..end with byte 0x06 of the inputfile
	2. write to outfile 
	3. set byte 0x05 to newcrc
	4. until byte 0x21 plain like in inputfile
	5. from 0x22..end xored with newcrc
	TODO 6. calculate new crc on each segment (needs to know the new MCD & MSN0..3)
--]]
local bxor=bit32.bxor
local utils = require('utils')
local getopt = require('getopt')

-- we need always 2 digits
function prepend_zero(s) 
	if (string.len(s)==1) then return "0" .. s
	else 
		if (string.len(s)==0) then return "00"
		else return s
		end
	end
end

-- helptext
function helptext()
	htext = [[

create a clone-dump of a dump from a Legic Prime Tag (MIM256 or MIM1024)
(created with 'hf legic save my_dump.hex') 
requiered arguments:
	-i <input file>
	-o <output file>
	-c <new-tag crc>
	e.g.: legic_clone -i my_dump.hex -o my_clone.hex -c f8
	hint: using the same CRC as in the <input file> will result in a plain dump]]
	print(htext)
end

--- Returns HEX representation of str
function str2hex(str)
    local hex = ''
    while #str > 0 do
        local hb = num2hex(string.byte(str, 1, 1))
        if #hb < 2 then hb = '0' .. hb end
        hex = hex .. hb
        str = string.sub(str, 2)
    end
    return hex
end

--- Returns HEX representation of num
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

-- Check availability of file
function file_check(file_name)
  local file_found=io.open(file_name, "r")      

  if file_found==nil then
    file_found=false
  else
    file_found=true
  end
  return file_found
end

-- xor-wrapper
function xorme(h,c,i)
	if(i>=23) then
		if(string.len(h)==2) then h="0x"..h; end
		if(string.len(c)==2) then c="0x"..c; end
		return prepend_zero(num2hex(bxor(h,c)))
	else
		return h
	end
end

-- main function
function main(args)
	-- some variables
	local i=0
	local bcnt=0
	local file_found=nil
	local segcnt
	local bytes = {}
	
	-- Arguments for the script
	-- Read the parameters
	for o, a in getopt.getopt(args, 'hc:i:o:') do
		if o == "o" then 
			outfile = a
			if (file_check(outfile)) then
				local answer = utils.confirm("\n\nthe output-file "..outfile.." alredy exists!\nthis will delete the previous content!\ncontinue?")
				if (answer==false) then return; end
			end
			i=i+1
		end		
		if o == "i" then
			infile = a 
			if (file_check(infile)==false) then
				print("input file: "..infile.." not found")
				return 0;
			end
			i=i+1
		end
		if o == "c" then 
			newcrc = a
			i=i+1
		end
		if o == "h" then helptext(); return; end
	end
	
	-- check if all parametes are supplied
	if ( i < 3 ) then 
		print("\nfailure ... three arguments are requiered!")
		helptext()
		return 0
	end 
	
	-- open files
	fhi,err = io.open(infile)
	if err then print("OOps ... faild to read from file ".. infile); return; end
	fho,err = io.open(outfile,"w")
	
	-- read line by line, split int into a table (bytes) and xor with original crc
	while true do
		line = fhi:read()
		if line == nil then break end
		-- print (line)
		for byte in line:gmatch("%w+") do 
			-- byte 0x00..0x21 are not xored
			if (bcnt<=21) then
				table.insert(bytes, byte)
			else
				--bytes from 0x22 are xored - make them plain
				table.insert(bytes, xorme(byte,oldcrc,(bcnt+1)))
			end
			if (bcnt==4) then oldcrc=byte; end
			bcnt=bcnt+1 
		end
	end
	
	
	-- rexor and write to file
	bcnt=0
	line=""
	for i = 1,#bytes do
		-- all byte lower than address 0x21 get not xored - but 0x04 (crc) gets replaced
		if( i <= 22 ) then
			-- replace crc
			if (i == 5 ) then 
				line=line.." "..string.sub(newcrc,-2)
				-- plain values at begin of a row
				elseif (bcnt == 0) then
					line=bytes[i]
					-- appended values of a row
				else
					line=line.." "..bytes[i]
			end
		-- start of xored values
		elseif (bcnt == 0) then 
			line=xorme(bytes[i],newcrc,i)
		elseif (bcnt <= 7) then 
			line=line.." "..xorme(bytes[i],newcrc,i)
		end
		if (bcnt == 7) then
			-- write line to new file
			fho:write(line.."\n")
			-- reset counter & line
			bcnt=-1
			line=""
		end
		bcnt=bcnt+1
	end
	
	-- close filehandles
	fhi:close()
	fho:close()
	
	-- information
	res = "\n\ncreated clone_dump from\n\t"..infile.." crc: "..oldcrc.."\ndump_file:"
	res = res .."\n\t"..outfile.." crc: "..string.sub(newcrc,-2)
	res = res .."\n\nyou will need to recalculate each segmentCRC"
	res = res .."\nafter writing this dump to a tag!"
	res = res .."\n\na segmentCRC gets calculated over MCD,MSN0..3,Segment-Header0..3"
	res = res .."\ne.g. (based on Segment00 of the data from "..infile..":"
	res = res .."\nhf legic crc8 "..bytes[1]..bytes[2]..bytes[3]..bytes[4]..bytes[23]..bytes[24]..bytes[25]..bytes[26]
	print(res)

end

main(args)
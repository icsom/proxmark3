--[[
	script to create a clone-dump with new crc
  Author: mosci
  https://github.com/icsom/proxmark3/blob/master/client/scripts/Legic_clone.lua

	1. read tag-dump, xor byte 22..end with byte 0x06 of the inputfile
	2. write to outfile 
	3. set byte 0x05 to newcrc
	4. until byte 0x21 plain like in inputfile
	5. from 0x22..end xored with newcrc
	TODO 6. calculate new crc on each segment (needs to know the new MCD & MSN0..2)
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
	-i <input file>		(file to read data from)
optional arguments :
	[-o <output file>] 	(requieres option -c to be given)
	[-c <new-tag crc>] 	(requieres option -o to be given)
	[-d]			(Display content of found Segments)
	[-s]			(Display summary at the end)
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

-- read input-file into array
function getInputBytes(infile)
	local line
	local bytes = {}

	local fhi,err = io.open(infile)
	if err then print("OOps ... faild to read from file ".. infile); return false; end

	while true do
		line = fhi:read()
		if line == nil then break end
		-- print (line)
		for byte in line:gmatch("%w+") do 
			table.insert(bytes, byte)
		end
	end
	
	fhi:close()

	print("\nread ".. #bytes .." bytes from ".. infile)
	return bytes
end

-- write to file
function writeOutputBytes(bytes, outfile)
	local line
	local bcnt=0
	local fho,err = io.open(outfile,"w")
	if err then print("OOps ... faild to open output-file ".. outfile); return false; end
	for i = 1, #bytes do
		if (bcnt == 0) then 
			line=bytes[i]
		elseif (bcnt <= 7) then 
			line=line.." "..bytes[i]
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
	fho:close()
	print("\nwrote ".. #bytes .." bytes to " .. outfile)
	return true
end

function xorBytes(inBytes,crc)
	local bytes = {}
	for i=1, #inBytes do
		bytes[i]=xorme(inBytes[i],crc,i)
	end
	if (#inBytes == #bytes) then
		-- replace crc
		bytes[5]=string.sub(crc,-2)
		return bytes
	else
		print("error: byte-count missmatch")
		return false
	end
end

function getSegmentData(bytes,start,index)
	local raw, len, valid, last, wrp, wrc, rd, crc
	local Segment={}
	Segment[0] = bytes[start].." "..bytes[start+1].." "..bytes[start+2].." "..bytes[start+3]
	-- flag = high nibble of byte 1
	Segment[1] = string.sub(bytes[start+1],0,1)
	-- valid = bit 6 of byte 1
	Segment[2]=tonumber(bit32.extract("0x"..bytes[start+1],6,1),16)
	-- last = bit 7 of byte 1
	Segment[3]=tonumber(bit32.extract("0x"..bytes[start+1],7,1),16)
	-- len = (byte 0)+(bit0-3 of byte 1)
	Segment[4]=tonumber(bytes[start],16)+tonumber(bit32.extract("0x"..bytes[start+1],0,3),16)
	-- wrp (write proteted) = byte 2
	Segment[5]=tonumber(bytes[start+2])
	-- wrc (write control) - bit 4-6 of byte 3
	Segment[6]=tonumber(bit32.extract("0x"..bytes[start+3],4,3),16)
	-- rd (read disabled) - bit 7 of byte 3
	Segment[7]=tonumber(bit32.extract("0x"..bytes[start+3],7,1),16)
	-- crc byte 4
	Segment[8]=bytes[start+4]
	-- segment index
	Segment[9]=index
  return Segment
end

function displaySegments(bytes)
	--display segment header(s)
	start=23
	index="00"
	--repeat until last-flag ist set to 1 or segment-index has reached 126
	repeat
		wrc=""
		wrp=""
		pld=""
		Seg = getSegmentData(bytes,start,index)
		printSegment(Seg)
		
		-- wrc
		if(Seg[6]>0) then
			print("WRC protected area:")
			-- length of wrc = wrc
			for i=1, Seg[6] do
				-- starts at (segment-start + segment-header + segment-crc)-1 
				wrc = wrc..bytes[(start+4+1+i)-1].." " 
			end
			print(wrc)
		elseif(Seg[5]>0) then
			print("Remaining write protected area:")
			-- length of wrp = (wrp-wrc)
			for i=1, (Seg[5]-Seg[6]) do
				-- starts at (segment-start + segment-header + segment-crc + wrc)-1 
				wrp = wrp..bytes[(start+4+1+Seg[6]+i)-1].." " 
			end
			print(wrp)
		end
		
		-- payload 
		print("Remaining segment payload:")
		--length of payload = segment-len - segment-header - segment-crc - wrp -wrc
		for i=1, (Seg[4]-4-1-Seg[5]-Seg[6]) do
			-- starts at (segment-start + segment-header + segment-crc + segment-wrp + segemnt-wrc)-1
			pld = pld..bytes[(start+4+1+Seg[5]+Seg[6]+i)-1].." " 
		end
		print(pld)
		
		start = start+Seg[4]
		index = prepend_zero(tonumber(Seg[9])+1)
		
	until (Seg[3] == 1 or tonumber(Seg[9]) == 126 )
end
-- print Segment values
function printSegment(SegmentData)
	res = "\nSegment "..SegmentData[9]..": "
	res = res..	"raw header="..SegmentData[0]..", "
	res = res..	"flag="..SegmentData[1].." (valid="..SegmentData[2].." last="..SegmentData[3].."), "
	res = res..	"len="..SegmentData[4]..", "
	res = res..	"WRP="..prepend_zero(SegmentData[5])..", "
	res = res..	"WRC="..prepend_zero(SegmentData[6])..", "
	res = res.. "RD="..SegmentData[7]..", "
	res = res.. "crc="..SegmentData[8]
	print(res)	
end

-- main function
function main(args)
	-- some variables
	local i=0
	local oldcrc, newcrc, infile, outfile
	local bytes = {}
	local segments = {}
	
	-- parse arguments for the script
	for o, a in getopt.getopt(args, 'hdsc:i::o:') do
		-- output file
		if o == "o" then 
			outfile = a
			ofs=true
			if (file_check(a)) then
				local answer = utils.confirm("\nthe output-file "..a.." alredy exists!\nthis will delete the previous content!\ncontinue?")
				if (answer==false) then 
					return
				end
			end
		end		
		-- input file
		if o == "i" then
			infile = a 
			if (file_check(infile)==false) then
				print("input file: "..infile.." not found")
				return
			else
				bytes = getInputBytes(infile)
				oldcrc=bytes[5]
				ifs=true
				if (bytes == false) then return; end
			end
			i=i+1
		end
		-- new crc
		if o == "c" then 
			newcrc = a
			ncs=true
		end
		--display segments switch
		if o == "d" then ds=true; end
		--display summary switch
		if o == "s" then ss=true; end
		-- help
		if o == "h" then helptext(); return; end
	end
	
	if (not ifs) then print("option '-i <input file> is required but missing"); return; end
	
	-- bytes to plain
	bytes=xorBytes(bytes, oldcrc)
	
	-- show segments (works only on plain bytes)
	if (ds) then
		print("+------------------------------------------- Segments -------------------------------------------+") 
		displaySegments(bytes); 
	end
	
  if (ofs and ncs) then
		-- xor bytes with new crc
		newBytes=xorBytes(bytes, newcrc)
		-- write output
		if (writeOutputBytes(newBytes, outfile)) then
			-- show summary if requested
			if (ss) then
				-- information
				res = "\n+-------------------------------------------- Summary -------------------------------------------+"
				res = res .."\ncreated clone_dump from\n\t"..infile.." crc: "..oldcrc.."\ndump_file:"
				res = res .."\n\t"..outfile.." crc: "..string.sub(newcrc,-2)
				res = res .."\nyou may load the new file with: hf legic load "..outfile
				res = res .."\n\nyou will need to recalculate each segmentCRC"
				res = res .."\nafter writing this dump to a tag!"
				res = res .."\n\na segmentCRC gets calculated over MCD,MSN0..3,Segment-Header0..3"
				res = res .."\ne.g. (based on Segment00 of the data from "..infile.."):"
				res = res .."\nhf legic crc8 "..bytes[1]..bytes[2]..bytes[3]..bytes[4]..bytes[23]..bytes[24]..bytes[25]..bytes[26]
				print(res)
			end
		end
	else
		if (ss) then
			-- show why the output-file was not written
			print("\nnew file not written - some arguments are missing ..")
			print("output file: ".. (ofs and outfile or "not given"))
			print("new crc: ".. (ncs and newcrc or "not given"))
		end
	end
	
end


main(args)
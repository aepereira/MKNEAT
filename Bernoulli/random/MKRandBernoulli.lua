--Script to get the Bernoulli p probability, by Monte Carlo simulation, of winning a Mortal Kombat
--match by pressing buttons randomly.
--
--Author: Arnaldo E. Pereira 2016
--
--For use with the BizHawk emulator (EmuHawk)
--ROM: Mortal Kombat (World) for Sega Genesis (REV00)
--
--NOTES:
--I chose to sim Sub-Zero, so I created 12 different savestates in BizHawk at the start of a fight:
--Two each (in a different map) against Kano, Liu Kang, Sonya, Johnny Cage, Scorpion, and Rayden.
--The script chooses randomly between them for each run.
--
--You can choose a different character to train and use more or fewer savesates, but make sure to put
--your BizHawk savestates in the same folder as this Lua script, and make the appropriate changes to
--loadrandstate().




OUTFILE = "random.csv"

--Number of matches to run for the simulation.
TRIALS = 1000 

RoundFlags = {}
RoundCheckCounter = 0


ButtonNames = 	{"Up",
		"Down",
		"Left",
		"Right",
		"A",
		"B",
		"C",
		"X",
		"Y",
		"Z"}

Outputs = #ButtonNames
outputs = {}


P1_RoundsWon = 0
P2_RoundsWon = 0
RoundCheckCounter = 0
matchesPlayed = 0
matchesWon = 0
prob = 0


--Make sure the savestates are named MK1.State to MK12.State.
--Put them in the same folder as the Lua script.

function loadrandstate()

	local randfile = "MK" .. math.random(12) .. ".State"
	savestate.load(randfile)

end

--Modified for the random case
function getroundstatus()

	--Keep these variables global
	RawTimeElapsed = 39208-(memory.read_u16_be(0xAC7E))
	TimeElapsed = 100*(RawTimeElapsed/39172)

	P1_Health = memory.read_u16_be(0xCAB8)
	P2_Health = memory.read_u16_be(0xCBB8)

end


function getroundflags()
	RoundFlags[1] = memory.read_u16_be(0xAB26)
	RoundFlags[2] = memory.read_u16_be(0xAB2A)
	RoundFlags[3] = memory.read_u16_be(0xAB30)
end


function endOfRound() --Returns true if flags indicate end of round

	getroundflags()

	if (RoundFlags[1] == 1) and (RoundFlags[2] == 1) and (RoundFlags[3] == 1) then
		return true
	else
		return false

	end
end


function startOfRound() --Returns true if flags indicate start of round

	getroundflags()

	if (RoundFlags[1] == 0) and (RoundFlags[2] == 0) and (RoundFlags[3] == 0) then
		return true
	else
		return false

	end
end


--Modified for random case.
function gameovercheck(is_timeup) --Checks if Game Over or P1 won match.

	if (P1_RoundsWon == 2 and endOfRound()) then
		matchesWon = matchesWon + 1
		matchesPlayed = matchesPlayed + 1
		return true
	
	elseif (P2_RoundsWon == 2 and endOfRound()) then

		matchesPlayed = matchesPlayed + 1
		return true 

	elseif is_timeup == true then

		matchesPlayed = matchesPlayed + 1
		return true 

	else
		return false

	end
 
end


--Checks if the current round is over. If so, set RoundsWon flags and check for Game Over.
--Modified for random case.
function roundovercheck()

	local timeup = false 

	--Only increment the counter once per round
	if RoundCheckCounter == 0 then

		if (P1_Health <= 0) then
			P2_RoundsWon = P2_RoundsWon + 1
			RoundCheckCounter = RoundCheckCounter + 1

		elseif (P2_Health <= 0) then
			P1_RoundsWon = P1_RoundsWon + 1
			RoundCheckCounter = RoundCheckCounter + 1

		end

		--Treat Time's Up as Game Over
		if TimeElapsed >= 100 then
			RoundCheckCounter = RoundCheckCounter + 1
			timeup = true

		end
	end

	
	--Reset at start of next round.
	if startOfRound() then
		RoundCheckCounter = 0
	end
	

	--Deal with Game Over

	if gameovercheck(timeup) then

		updateProb()
		initializeRun()
		
	end
end


function resetgamevars()

	P1_RoundsWon = 0
	P2_RoundsWon = 0
	RoundCheckCounter = 0

end


function clearJoypad()

	local controller = {}

	for b = 1,#ButtonNames do
		controller["P1 " .. ButtonNames[b]] = false
	end

	joypad.set(controller)
end


function initializeRun(...)

		local arg = {...}
		
		--Pass no arguments to wait the 60 frames. Skip this when loading a file.
		if #arg == 0 then

			--Wait 60 frames to make transition smoother for videos.
			for t=1,60 do

				emu.frameadvance()

			end
		end

		loadrandstate()
		resetgamevars()
		clearJoypad()
	
		evaluateCurrent()

end


--Modified for random case.
function evaluateCurrent()

	getroundstatus()
	randomoutput()
	roundovercheck()

end


function randomoutput()

	local controller = {}

	--Kludge to give outputs numerical indices according to the order in ButtonNames, 
	--so it behaves well with update_history(), while passing a string-indexed table 
	--to joypad.set().

	for o=1,Outputs do
		local button = "P1 " .. ButtonNames[o]
		if math.random() > 0.5 then
			controller[button] = true
			outputs[o] = true
		else
			controller[button] = false
			outputs[o] = false
		end
	end
	
	if controller["P1 Left"] and controller["P1 Right"] then
		controller["P1 Left"] = false
		outputs[3] = false

		controller["P1 Right"] = false
		outputs[4] = false
	end

	if outputs["P1 Up"] and outputs["P1 Down"] then
		controller["P1 Up"] = false
		outputs[1] = false

		controller["P1 Down"] = false
		outputs[2] = false
	end

	joypad.set(controller) 

end




--Monte Carlo simulation functions

function updateProb()

	prob = matchesWon / matchesPlayed

end


function simMonteCarlo()

	for m = 1,TRIALS do
		while matchesPlayed == (m - 1) do
			if emu.framecount()%5 == 0 then
				evaluateCurrent()
			end
			
			local backgroundColor = 0xD0FFFFFF
			gui.drawBox(0, 40, 320, 80, backgroundColor, backgroundColor)
			gui.drawText(5, 45, "Playing match " .. m .. " out of " .. TRIALS .. " (" .. math.floor(matchesPlayed/TRIALS*100) .. "%)", 0xFF000000, 11)
			gui.drawText(5, 60, "Bernoulli p (estimate): " .. prob, 0xFF000000, 11)

			emu.frameadvance()
		
		end
	end

end


function writeHeaders()

	local file = io.open(OUTFILE, "w")
	file:write("GENOME,PROB" .. "\n")
	file:close()

end


function writeToFile()

	local file = io.open(OUTFILE, "a")
	--Only one "genome" in the random case
	file:write("1," .. prob .. "\n")
	file:close()

end


--*****************************************************--

sim_finished = false
writeHeaders()
initializeRun()

--Main loop
while true do
	
	if sim_finished == false then
		simMonteCarlo()
		writeToFile()
	end

	--Will get here once the simulation is over
	sim_finished = true
	local backgroundColor = 0xD0FFFFFF
	gui.drawBox(0, 40, 320, 80, backgroundColor, backgroundColor)
	gui.drawText(5, 45, "Bernoulli p (final estimate): " .. prob, 0xFF000000, 11)
	gui.drawText(150, 60, "SIMULATION FINISHED", 0xFF000000, 11)

	emu.frameadvance()
end


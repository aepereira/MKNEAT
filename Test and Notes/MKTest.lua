--Script to test functions and behavior before running NEAT implementation for Mortal Kombat.
--Author: Arnaldo E. Pereira
--For use with the BizHawk emulator
--ROM: Mortal Kombat (World) for Sega Genesis (REV00)
--This test script presses buttons at random.
--Note: This code contains some functions that could be useful in tournament mode that are not
--in MKTest2 or MKMatchNEAT or MKMatchFS-NEAT


RoundFlags = {}
P1_Moves = {}
P2_Moves = {}
AtLeftEdge = false
AtRightEdge = false
roundFitness = 0
leftmost_x_observed = 2000 --arbitrary large number. All x's in game are <2000
rightmost_x_observed = 0 --arbitrary. All x values in game are > 0.

--For table of previous round states
history = {}
periods = 10 --Number of previous RoundStates to save in history. 

CurrentRoundStatus = {} --Will save and add to an array of n previous statuses


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

States = 13 --Number of items in CurrentRoundStatus. Kind of a kludge to set it manually, I know.

Inputs = (States + Outputs)*periods + States


function initialize_history()

	for i=1,periods do
		history[i] = {} --Each of the saved previous CurrentRoundStatus'es is a row.

		for j=1,(States + Outputs) do
			
			history[i][j] = 0

		end 

	end

end


function update_history() --run after getroundstatus(), evaluation, and outputs.

	local temphistory = {}

	for j=1,States do
	
		temphistory[j] = CurrentRoundStatus[j]
	end


	for k=(States+1),(States + Outputs) do

		temphistory[k] = outputs[k-States]

	end

	
	--Pop off the oldest the oldest entry in history and insert the new one at the beginning.
	table.remove(history)	
	table.insert(history,1,temphistory)


	--For testing only
	file = io.open("histories.txt","a")
	io.output(file)

	for i=1,periods do

		for j=1,(States + Outputs) do
			
			io.write(tostring(history[i][j]),",","  ")

		end

		io.write("\n","\n") 

	end

	io.write("\n","\n","*************************","\n","\n")
	io.close(file)

end


function getroundstatus()

	RawTimeElapsed = 39208-(memory.read_u16_be(0xAC7E))
	TimeElapsed = 100*(RawTimeElapsed/39172)
	TimeScore = 100-TimeElapsed

	P1_X = memory.read_u16_be(0xCB4A)
	P2_X = memory.read_u16_be(0xCC4A)
	X_Dist = P2_X - P1_X

	edgecheck()


	P1_Health = memory.read_u16_be(0xCAB8)
	P2_Health = memory.read_u16_be(0xCBB8)
	DeltaHealth = P1_Health - P2_Health


	P1_Moves[1] = memory.read_u16_be(0xCAFA)
	P1_Moves[2] = memory.read_u16_be(0xCAFE)


	P2_Moves[1] = memory.read_u16_be(0xCBFA)
	P2_Moves[2] = memory.read_u16_be(0xCBFE)

	CurrentRoundStatus[1] = TimeElapsed
	CurrentRoundStatus[2] = P1_X
	CurrentRoundStatus[3] = P2_X
	CurrentRoundStatus[4] = X_Dist
	CurrentRoundStatus[5] = AtLeftEdge
	CurrentRoundStatus[6] = AtRightEdge
	CurrentRoundStatus[7] = P1_Moves[1]
	CurrentRoundStatus[8] = P1_Moves[2]
	CurrentRoundStatus[9] = P2_Moves[1]
	CurrentRoundStatus[10] = P2_Moves[2]
	CurrentRoundStatus[11] = P1_Health
	CurrentRoundStatus[12] = P2_Health
	CurrentRoundStatus[13] = DeltaHealth

end


function getroundflags()
	RoundFlags[1] = memory.read_u16_be(0xAB26)
	RoundFlags[2] = memory.read_u16_be(0xAB2A)
	RoundFlags[3] = memory.read_u16_be(0xAB30)
end



function edgecheck()

	leftcheck()
	rightcheck()

end

function leftcheck()

--This algorithm uses parity to check if P1 is at the right edge of the map. 
--It can give false positives at first but should become accurate as play progresses 
--and the character moves around the map.
 

	local leftofP2 = true --arbitrary. Opposite in rightcheck().

	local leftcount = 0
	local rightcount = 0

	if P1_X < leftmost_x_observed then
		leftmost_x_observed = P1_X
	end


	--Kludge. Depends on history, which depends on order of ButtonNames

	if P1_X == leftmost_x_observed then

		for i=periods,1,-1 do

			if (history[i][2] == leftmost_x_observed) then

				for j=i,1,-1 do

					if history[j][16] == true then
					
						leftcount = leftcount + 1

					end

					if history[j][17] == true then
					
						rightcount = rightcount + 1

					end
					
					if history[j][4] <= 0 then
				
						leftofP2 = false
				
					end

				end


			end
		end


	
		if (leftofP2 == true) and (leftcount > rightcount) then

			AtLeftEdge = true

		else

			AtLeftEdge = false

		end



	else
		AtLeftEdge = false

	end 

end


function rightcheck()

--This algorithm uses parity to check if P1 is at the right edge of the map. 
--It can give false positives at first but should become accurate as play progresses 
--and the character moves around the map.
 

	local rightofP2 = false --arbitrary. Opposite in leftcheck().

	local leftcount = 0
	local rightcount = 0

	if P1_X > rightmost_x_observed then
		rightmost_x_observed = P1_X
	end


	--Kludge. Depends on history, which depends on order of ButtonNames

	if P1_X == rightmost_x_observed then

		for i=periods,1,-1 do

			if (history[i][2] == rightmost_x_observed) then

				for j=i,1,-1 do
				
					if history[j][16] == true then
					
						leftcount = leftcount + 1

					end

					if history[j][17] == true then
					
						rightcount = rightcount + 1

					end
					
					if history[j][4] <= 0 then
				
						rightofP2 = true
				
					end

				end


			end
		end


	
		if (rightofP2 == true) and (rightcount > leftcount) then

			AtRightEdge = true

		else

			AtRightEdge = false

		end



	else
		AtRightEdge = false

	end 

end


function inFight() --Returns true if in fighting mode

	getroundflags()

	if (RoundFlags[1] == 0) and (RoundFlags[2] == 0) and (RoundFlags[3] == 1) then
		return true
	else
		return false

	end
end


function finishHim() --Returns true is in "Finish him" mode

	getroundflags()

	if (RoundFlags[1] == 1) and (RoundFlags[2] == 0) and (RoundFlags[3] == 1) then
		return true
	else
		return false

	end
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


function continue() --Waits, hits Start, waits.

	for i=1,60,1 do
		emu.frameadvance()
	end

	joypad.set({Start=1},1)

	for i=1,60,1 do
		emu.frameadvance()
	end
end


--Checks if Game Over. Returns true if Game Over.
function gameovercheck()
	
--[[Trying something else

	--For round and tournament versions
	if P2_RoundsWon == 2 then
		GameOver = true
	elseif (TimeElapsed >= 100) and (P1_Health == P2_health) then
		GameOver = true

	--For round version only
	elseif P1_RoundsWon == 2 then
		GameOver = true
	end
--]]

	local ContinueTimer = memory.read_u16_be(0xB586)

	if ContinueTimer ~= 0 then
		return true
	else
		return false
	end 
	--Doesn't deal with the case (for round version) where P1 wins 2 rounds, but I'll deal later.
end


--Checks if the current round is over. If so, set RoundsWon flags and check for Game Over.
RoundCheckCounter = 0

function roundovercheck()

	--Only increment the counter once per round
	if (RoundCheckCounter == 0) and (inFight() or finishHim() or endOfRound()) then

		if (P1_Health <= 0) then
			P2_RoundsWon = P2_RoundsWon + 1
			roundFitness = getroundFitness(false)
			RoundCheckCounter = RoundCheckCounter + 1

		elseif (P2_Health <= 0) then
			P1_RoundsWon = P1_RoundsWon + 1
			roundFitness = getroundFitness(true)
			RoundCheckCounter = RoundCheckCounter + 1

		elseif (TimeElapsed >= 100) and (P1_Health < P2_health) then
			P2_RoundsWon = P2_RoundsWon + 1
			roundFitness = getroundFitness(false)
			RoundCheckCounter = RoundCheckCounter + 1

		elseif (TimeElapsed >= 100) and (P2_Health < P1_Health) then
			P1_RoundsWon = P1_RoundsWon + 1
			roundFitness = getroundFitness(true)
			RoundCheckCounter = RoundCheckCounter + 1

		end
	end
	
	--Increase matchFitness and reset at start of next round.
	if startOfRound() then
		matchFitness = matchFitness + roundFitness --Increase matchFitness
		RoundCheckCounter = 0
		roundFitness = 0
		initialize_history()
	end
	

	--Deal with Game Over.

	if gameovercheck() then

		--Reset RoundCheckCounter
		RoundCheckCounter = 0

		--Calculate total match fitness, then break loop and continue
		matchFitness = (matchFitness + roundFitness)*matchbonus()
		roundFitness = 0
		--Pass matchFitness to whatever I need to pass it to, then

		BreakCondition = true --Passes value to inner while loop.
		continue()--Hits start at Continue Screen.
	end
end


function resetgamevars()
	BreakCondition = false
	P1_RoundsWon = 0
	P2_RoundsWon = 0
	AtLeftEdge = false
	AtRightEdge = false
	roundFitness = 0
	matchFitness = 0
	leftmost_x_observed = 2000 
	rightmost_x_observed = 0
	--P1_MatchesWon = 0
	memory.write_u16_be(0xB586,0) --Reset Continue Timer memory address to 0.
end


--Function to run at Character Select screen. Currently set to pick Sub-Zero.
function selectsubzero()

	for i=1,120,1 do
		emu.frameadvance()
	end

	joypad.set({Right=1},1)

	for i=1,12,1 do
		emu.frameadvance()
	end

	joypad.set({Start=1},1)

	emu.frameadvance()
end


--Fitness

function getrtFitness()

	local health = P1_Health
	local deltahealth = DeltaHealth

	if deltahealth >= 0 then
		return 110 + (health/12)^2 + (deltahealth/12)^2
	else
		return 110 + (health/12)^2 - (deltahealth/12)^2
	end
end


function getroundFitness(P1_Win)

	local timeelapsed = TimeElapsed
	local timeremaining = 100 - timeelapsed
	local winbonus = 1000

	if P1_Win == true then
		return getrtFitness() + winbonus + (timeremaining/10)^2
	else
		return getrtFitness() + (timeelapsed/10)^2
	end

	
end


function matchbonus()

	if (P1_RoundsWon == 2) and (P2_RoundsWon == 0) then 
		return 1.5
	else
		return 1
	end
end


--A test function only. Borrowed from MarI/O with some changes.

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





--Main loop
while true do

	--Handle character selection. Currently set for Sub-Zero. Reset flags. 
	--Initialize history matrix.

	selectsubzero()
	resetgamevars()
	initialize_history()

	--test only
	local testvariable = 0
		

	--In-game (inner) loop

	while true do

		getroundflags()

		--test only
		if testvariable == 0 then
			getroundstatus()
			testvariable = 1
		end


		--Press Start whenever not fighting or in "Finish him" mode.
		if not (inFight() or finishHim()) then
			joypad.set({Start=1},1) 
		end


		--Test by trying random outputs every 5 frames, then updating history.
		if (inFight() or finishHim() or endOfRound()) and (emu.framecount()%5 == 0) then
			getroundstatus() --Update variables 
			randomoutput()
			update_history()

			--If round is over, calculate RoundFitness as part of roundovercheck()
			roundovercheck() 
		end 


		--Display variables
		gui.text(0,0,"P1 Health " .. P1_Health .. " P2 Health " .. P2_Health .. " Delta " .. DeltaHealth .. " Time " .. TimeScore)
		gui.text(0,30,"P1 X " .. P1_X .. " P2 X " .. P2_X .. " Dist " .. X_Dist)
		gui.text(0,60,"Left? " .. tostring(AtLeftEdge) .. " Right? " .. tostring(AtRightEdge))
		gui.text(0,90,"Flags " .. RoundFlags[1] .. " " .. RoundFlags[2] .. " " .. RoundFlags[3] .. "   In fight? " .. tostring(inFight()))
		gui.text(0,120,"P1 Rounds " .. P1_RoundsWon .. " P2 Rounds " .. P2_RoundsWon .. "  counter " .. RoundCheckCounter)

	--display rtFitness, last round fitness, last total fitness, max fitness
		gui.text(0,150,"rt Fitness " .. getrtFitness())
		gui.text(0,180,"Round Fitness " .. roundFitness)
		gui.text(0,210,"Match Fitness " .. matchFitness)


		--Break on Game Over.
		if BreakCondition == true then
			break
		else
			emu.frameadvance()
		end
	end

	emu.frameadvance()
end


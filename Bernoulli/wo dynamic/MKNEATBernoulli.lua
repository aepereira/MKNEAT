--Script to get the Bernoulli p probability, by Monte Carlo simulation, of winning a Mortal Kombat
--match. This script is meant to test the NEAT algorithm results.
--
--Author: Arnaldo E. Pereira 2016
--
--For use with the BizHawk emulator (EmuHawk)
--ROM: Mortal Kombat (World) for Sega Genesis (REV00)
--
--NOTES:
--I chose to train Sub-Zero, so I created 12 different savestates in BizHawk at the start of a fight:
--Two each (in a different map) against Kano, Liu Kang, Sonya, Johnny Cage, Scorpion, and Rayden.
--The script chooses randomly between them for each run.
--
--You can choose a different character to train and use more or fewer savesates, but make sure to put
--your BizHawk savestates in the same folder as this Lua script, and make the appropriate changes to
--loadrandstate().



OUTFILE = "MKNEATProb.csv"

--Generation of the NEAT algorithm to use for simulations.
GENERATION = 1000

--Number of matches to run for the Monte Carlo simulation of each genome.
TRIALS = 100

 
Filename = "MKNEAT.State"

RoundFlags = {}
P1_Moves = {}
P2_Moves = {}
AtLeftEdge = false
AtRightEdge = false
RoundCheckCounter = 0
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

InputSize = (States + Outputs)*periods + States
Inputs = InputSize + 1


P1_RoundsWon = 0
P2_RoundsWon = 0
RoundCheckCounter = 0
matchesPlayed = 0
matchesWon = 0
prob = 0


--NEAT Parameters
--Don't really need them, but keeping them so it won't screw up reading from file,
--since constructors use them.

MutateConnectionsChance = 0.25
PerturbChance = 0.90
CrossoverChance = 0.75
LinkMutationChance = 2.0
NodeMutationChance = 0.50
BiasMutationChance = 0.40
StepSize = 0.1
DisableMutationChance = 0.4
EnableMutationChance = 0.2

MaxNodes = 1000000



--Make sure the savestates are named MK1.State to MK12.State.
--Put them in the same folder as the Lua script.

function loadrandstate()

	local randfile = "MK" .. math.random(12) .. ".State"
	savestate.load(randfile)

end


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

end


function getroundstatus()

	--Keep these variables global
	RawTimeElapsed = 39208-(memory.read_u16_be(0xAC7E))
	TimeElapsed = 100*(RawTimeElapsed/39172)

	P1_X = memory.read_u16_be(0xCB4A)
	P2_X = memory.read_u16_be(0xCC4A)
	X_Dist = P2_X - P1_X

	P1_Health = memory.read_u16_be(0xCAB8)
	P2_Health = memory.read_u16_be(0xCBB8)
	DeltaHealth = P1_Health - P2_Health

	P1_Moves[1] = memory.read_u16_be(0xCAFA)
	P1_Moves[2] = memory.read_u16_be(0xCAFE)

	P2_Moves[1] = memory.read_u16_be(0xCBFA)
	P2_Moves[2] = memory.read_u16_be(0xCBFE)


	edgecheck()


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


--Modified for Bernoulli task.
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
--Modified for Bernoulli task
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
		initialize_history()
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
	AtLeftEdge = false
	AtRightEdge = false
	leftmost_x_observed = 2000 
	rightmost_x_observed = 0
	RoundCheckCounter = 0

end




--MODIFIED NEAT FUNCTIONS

		
function formatinput(x) --Function to deal with boolean inputs.

	if type(x) == "boolean" then

		if x == true then
			return 1.0
		else
			return 0.0
		end

	else

		return x
	end

end


function getInputs()

	local inputs = {}

	getroundflags()
	getroundstatus()

	for i=1,periods do

		for j=1,(States + Outputs) do

			inputs[#inputs+1] = formatinput(history[i][j])

		end

	end


	for s=1,States do

		inputs[#inputs+1] = formatinput(CurrentRoundStatus[s])

	end

	return inputs

end


function generateoutput(neurons) --Runs inside evaluateNetwork(network, inputs)

	local controller = {}

	--Kludge to give outputs numerical indices according to the order in ButtonNames, 
	--so it behaves well with update_history(), while passing a string-indexed table 
	--to joypad.set().

	for o=1,Outputs do
		local button = "P1 " .. ButtonNames[o]

		--Check if activated
		if neurons[MaxNodes+o].value > 0 then 

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
		initialize_history()

		pool.currentFrame = 0
		clearJoypad()
	
		local species = pool.species[pool.currentSpecies]
		local genome = species.genomes[pool.currentGenome]
		generateNetwork(genome)
		evaluateCurrent()

end


function evaluateNetwork(network, inputs)

	table.insert(inputs, 1)
	if #inputs ~= Inputs then
		console.writeline("Incorrect number of neural network inputs.")
		return {}
	end
	
	for i=1,Inputs do
		network.neurons[i].value = inputs[i]
	end
	
	for _,neuron in pairs(network.neurons) do

		local sum = 0

		for j = 1,#neuron.incoming do
			local incoming = neuron.incoming[j]
			
			local other = network.neurons[incoming.into]
			sum = sum + incoming.weight * other.value
		end
		
		if #neuron.incoming > 0 then
			neuron.value = sigmoid(sum)
		end
	end
	
	generateoutput(network.neurons)
	update_history()
	roundovercheck()

end


function evaluateCurrent()

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]

	inputs = getInputs()

	evaluateNetwork(genome.network, inputs)

end




--NEAT FUNCTIONS COPIED VERBATIM FROM SethBling's NEATEvolve Lua implementation (MARI/O)
--Functions not needed for this Monte Carlo simulation removed.


function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end


function newPool()
	local pool = {}
	pool.species = {}
	pool.generation = 0
	pool.innovation = Outputs
	pool.currentSpecies = 1
	pool.currentGenome = 1
	pool.currentFrame = 0
	pool.maxFitness = 0
	
	return pool
end


function newSpecies()
	local species = {}
	species.topFitness = 0
	species.staleness = 0
	species.genomes = {}
	species.averageFitness = 0
	
	return species
end


function newGenome()
	local genome = {}
	genome.genes = {}
	genome.fitness = 0
	genome.adjustedFitness = 0
	genome.network = {}
	genome.maxneuron = 0
	genome.globalRank = 0
	genome.mutationRates = {}
	genome.mutationRates["connections"] = MutateConnectionsChance
	genome.mutationRates["link"] = LinkMutationChance
	genome.mutationRates["bias"] = BiasMutationChance
	genome.mutationRates["node"] = NodeMutationChance
	genome.mutationRates["enable"] = EnableMutationChance
	genome.mutationRates["disable"] = DisableMutationChance
	genome.mutationRates["step"] = StepSize
	
	return genome
end


function newGene()
	local gene = {}
	gene.into = 0
	gene.out = 0
	gene.weight = 0.0
	gene.enabled = true
	gene.innovation = 0
	
	return gene
end


function newNeuron()
	local neuron = {}
	neuron.incoming = {}
	neuron.value = 0.0
	
	return neuron
end


function generateNetwork(genome)
	local network = {}
	network.neurons = {}
	
	for i=1,Inputs do
		network.neurons[i] = newNeuron()
	end
	
	for o=1,Outputs do
		network.neurons[MaxNodes+o] = newNeuron()
	end
	
	table.sort(genome.genes, function (a,b)
		return (a.out < b.out)
	end)
	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if gene.enabled then
			if network.neurons[gene.out] == nil then
				network.neurons[gene.out] = newNeuron()
			end
			local neuron = network.neurons[gene.out]
			table.insert(neuron.incoming, gene)
			if network.neurons[gene.into] == nil then
				network.neurons[gene.into] = newNeuron()
			end
		end
	end
	
	genome.network = network
end




--Modified for the Bernoulli task.
--Changes the global control variable sim_finished to true once all genomes have been simulated.
function nextGenome()

	pool.currentGenome = pool.currentGenome + 1
	if pool.currentGenome > #pool.species[pool.currentSpecies].genomes then
		pool.currentGenome = 1
		pool.currentSpecies = pool.currentSpecies+1
		if pool.currentSpecies > #pool.species then
			sim_finished = true
		end
	end
	
	if sim_finished == false then
		initializeRun()
	end
	
end


--Modified for the Bernoulli task.
function loadFile(filename)
        local file = io.open(filename, "r")
	pool = newPool()
	pool.generation = file:read("*number")
	pool.maxFitness = file:read("*number")
	local numSpecies = file:read("*number")

        for s=1,numSpecies do

		local species = newSpecies()
		table.insert(pool.species, species)
		species.topFitness = file:read("*number")
		species.staleness = file:read("*number")
		local numGenomes = file:read("*number")

		for g=1,numGenomes do

			local genome = newGenome()
			table.insert(species.genomes, genome)
			genome.fitness = file:read("*number")
			genome.maxneuron = file:read("*number")
			local line = file:read("*line")
			while line ~= "done" do
				genome.mutationRates[line] = file:read("*number")
				line = file:read("*line")
			end

			local numGenes = file:read("*number")

			for n=1,numGenes do

				local gene = newGene()
				table.insert(genome.genes, gene)
				local enabled
				gene.into, gene.out, gene.weight, gene.innovation, enabled = file:read("*number", "*number", "*number", "*number", "*number")

				if enabled == 0 then
					gene.enabled = false
				else
					gene.enabled = true
				end
				
			end
		end
	end

        file:close()

	--Start at the beginning
	pool.currentSpecies = 1
	pool.currentGenome = 1

	initializeRun("loading")

	pool.currentFrame = pool.currentFrame + 1
end




--Monte Carlo simulation functions
--Slightly different from random case.

function updateProb()

	prob = matchesWon / matchesPlayed

end


function simMonteCarloNEAT()

	while sim_finished == false do	

		for m = 1,TRIALS do
			while matchesPlayed == (m - 1) do

				if pool.currentFrame%5 == 0 then
					evaluateCurrent()
				end
			
			
				local backgroundColor = 0xD0FFFFFF
				gui.drawBox(0, 40, 320, 100, backgroundColor, backgroundColor)
				gui.drawText(5, 45, "Generation " .. pool.generation .. " species " .. pool.currentSpecies .. " genome " .. pool.currentGenome, 0xFF000000, 11)
				gui.drawText(5, 60, "Playing match " .. m .. " out of " .. TRIALS .. " (" .. math.floor(matchesPlayed/TRIALS*100) .. "%)", 0xFF000000, 11)
				gui.drawText(5, 80, "Bernoulli p (estimate): " .. prob, 0xFF000000, 11)

			
				pool.currentFrame = pool.currentFrame + 1
				emu.frameadvance()
		
			end
		end
		
		console.writeline("Generation " .. pool.generation .. " species " .. pool.currentSpecies .. " genome " .. pool.currentGenome .. " -- " .. "Bernoulli p (final) after " .. TRIALS .. " simulations: " .. prob .. "\n")

		writeAndNextGenome()

	end
end


function writeHeadersNEAT()

	local file = io.open(OUTFILE, "w")
	file:write("GENERATION,SPECIES,GENOME,PROB" .. "\n")
	file:close()

end


function writeAndNextGenome()

	local file = io.open(OUTFILE, "a")
	file:write(pool.generation .. "," .. pool.currentSpecies .. "," .. pool.currentGenome .. "," .. prob .. "\n")
	file:close()

	nextGenome()

	--Reset the Bernoulli vars for the next genome
	matchesPlayed = 0
	matchesWon = 0
	prob = 0

end




--*****************************************************--

--On first run

sim_finished = false
writeHeadersNEAT()

--Using filename convention from the NEAT training script. 
--Make sure the backup file for the generation pool you want to test is
--in the same folder as this script.
loadFile("backup." .. GENERATION .. "." .. Filename .. ".pool")



--Main loop
while true do	

	simMonteCarloNEAT()

	--Will get here once the simulation is over
	local backgroundColor = 0xD0FFFFFF
	gui.drawBox(0, 40, 320, 100, backgroundColor, backgroundColor)
	gui.drawText(120, 50, "SIMULATION FINISHED", 0xFF000000, 11)

	emu.frameadvance()
end


--Script that uses the NEAT algorithm by Stanley and Miikkulainen to train over repeated matches
--of Mortal Kombat. Lua NEAT functions adapted from the implementation by SethBling.
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




Filename = "MKDYNNEAT.State"

RoundFlags = {}
P1_Moves = {}
P2_Moves = {}
AtLeftEdge = false
AtRightEdge = false
roundFitness = 0
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


--NEAT Parameters
Population = 150
DeltaDisjoint = 2.0
DeltaWeights = 0.4
DeltaThreshold = 1.0

StaleSpecies = 15

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

	--[[For testing
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
	]]--

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

--[[Not used.
function inFight() --Returns true if in fighting mode

	getroundflags()

	if (RoundFlags[1] == 0) and (RoundFlags[2] == 0) and (RoundFlags[3] == 1) then
		return true
	else
		return false

	end
end
]]--


--[[Not used.
function finishHim() --Returns true is in "Finish him" mode

	getroundflags()

	if (RoundFlags[1] == 1) and (RoundFlags[2] == 0) and (RoundFlags[3] == 1) then
		return true
	else
		return false

	end
end
]]--


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


function gameovercheck(is_timeup) --Checks if Game Over or P1 won match.

	if (P1_RoundsWon == 2 and endOfRound()) or (P2_RoundsWon == 2 and endOfRound()) or is_timeup == true then

		return true

	else
		return false

	end
 
end


--Checks if the current round is over. If so, set RoundsWon flags and check for Game Over.

function roundovercheck()

	local timeup = false 

	--Only increment the counter once per round
	if RoundCheckCounter == 0 then

		if (P1_Health <= 0) then
			P2_RoundsWon = P2_RoundsWon + 1
			roundFitness = getroundFitness(false)
			RoundCheckCounter = RoundCheckCounter + 1

		elseif (P2_Health <= 0) then
			P1_RoundsWon = P1_RoundsWon + 1
			roundFitness = getroundFitness(true)
			RoundCheckCounter = RoundCheckCounter + 1

		end

		--Treat Time's Up as Game Over
		if TimeElapsed >= 100 then
			RoundCheckCounter = RoundCheckCounter + 1
			timeup = true

		end
	end

	
	--Increase matchFitness and reset at start of next round.
	if startOfRound() then
		matchFitness = matchFitness + roundFitness --Increase matchFitness
		RoundCheckCounter = 0
		roundFitness = 0
		initialize_history()
	end
	

	--Deal with Game Over (end of genome).

	if gameovercheck(timeup) then

		--Calculate total match fitness
		matchFitness = (matchFitness + roundFitness)*matchbonus()
		roundFitness = 0

		local species = pool.species[pool.currentSpecies]
		local genome = species.genomes[pool.currentGenome]


		if timeup == true then

			genome.fitness = -1
		else

			genome.fitness = matchFitness
		end

		if genome.fitness > pool.maxFitness then
			pool.maxFitness = genome.fitness
			forms.settext(maxFitnessLabel, "Pool Max Fitness: " .. math.floor(pool.maxFitness))
			writeFile("backup." .. pool.generation .. "." .. forms.gettext(saveLoadFile))

		end
		
		console.writeline("Gen " .. pool.generation .. " species " .. pool.currentSpecies .. " genome " .. pool.currentGenome .. " fitness: " .. genome.fitness)


		pool.currentSpecies = 1
		pool.currentGenome = 1

		while fitnessAlreadyMeasured() do 
			nextGenome() 
		end

		initializeRun()
		
	end
end


function resetgamevars()

	P1_RoundsWon = 0
	P2_RoundsWon = 0
	AtLeftEdge = false
	AtRightEdge = false
	roundFitness = 0
	matchFitness = 0
	leftmost_x_observed = 2000 
	rightmost_x_observed = 0
	RoundCheckCounter = 0

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


--Added dynamic thresholding
function sameSpecies(genome1, genome2)
	local num_species_target = 10
	local compat_mod = 0.3

	if pool.generation >= 1 then
		if #pool.species < num_species_target then
			DeltaThreshold = DeltaThreshold - compat_mod
		elseif #pool.species > num_species_target then
			DeltaThreshold = DeltaThreshold + compat_mod
		end
	end

	local dd = DeltaDisjoint*disjoint(genome1.genes, genome2.genes)
	local dw = DeltaWeights*weights(genome1.genes, genome2.genes) 
	return dd + dw < DeltaThreshold
end



--NEAT FUNCTIONS COPIED VERBATIM FROM SethBling's NEATEvolve Lua implementation (MARI/O)


function sigmoid(x)
	return 2/(1+math.exp(-4.9*x))-1
end


function newInnovation()
	pool.innovation = pool.innovation + 1
	return pool.innovation
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


function copyGenome(genome)
	local genome2 = newGenome()
	for g=1,#genome.genes do
		table.insert(genome2.genes, copyGene(genome.genes[g]))
	end
	genome2.maxneuron = genome.maxneuron
	genome2.mutationRates["connections"] = genome.mutationRates["connections"]
	genome2.mutationRates["link"] = genome.mutationRates["link"]
	genome2.mutationRates["bias"] = genome.mutationRates["bias"]
	genome2.mutationRates["node"] = genome.mutationRates["node"]
	genome2.mutationRates["enable"] = genome.mutationRates["enable"]
	genome2.mutationRates["disable"] = genome.mutationRates["disable"]
	
	return genome2
end


function basicGenome()
	local genome = newGenome()
	local innovation = 1

	genome.maxneuron = Inputs
	mutate(genome)
	
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


function copyGene(gene)
	local gene2 = newGene()
	gene2.into = gene.into
	gene2.out = gene.out
	gene2.weight = gene.weight
	gene2.enabled = gene.enabled
	gene2.innovation = gene.innovation
	
	return gene2
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


function crossover(g1, g2)
	-- Make sure g1 is the higher fitness genome
	if g2.fitness > g1.fitness then
		tempg = g1
		g1 = g2
		g2 = tempg
	end

	local child = newGenome()
	
	local innovations2 = {}
	for i=1,#g2.genes do
		local gene = g2.genes[i]
		innovations2[gene.innovation] = gene
	end
	
	for i=1,#g1.genes do
		local gene1 = g1.genes[i]
		local gene2 = innovations2[gene1.innovation]
		if gene2 ~= nil and math.random(2) == 1 and gene2.enabled then
			table.insert(child.genes, copyGene(gene2))
		else
			table.insert(child.genes, copyGene(gene1))
		end
	end
	
	child.maxneuron = math.max(g1.maxneuron,g2.maxneuron)
	
	for mutation,rate in pairs(g1.mutationRates) do
		child.mutationRates[mutation] = rate
	end
	
	return child
end


function randomNeuron(genes, nonInput)
	local neurons = {}
	if not nonInput then
		for i=1,Inputs do
			neurons[i] = true
		end
	end
	for o=1,Outputs do
		neurons[MaxNodes+o] = true
	end
	for i=1,#genes do
		if (not nonInput) or genes[i].into > Inputs then
			neurons[genes[i].into] = true
		end
		if (not nonInput) or genes[i].out > Inputs then
			neurons[genes[i].out] = true
		end
	end

	local count = 0
	for _,_ in pairs(neurons) do
		count = count + 1
	end
	local n = math.random(1, count)
	
	for k,v in pairs(neurons) do
		n = n-1
		if n == 0 then
			return k
		end
	end
	
	return 0
end


function containsLink(genes, link)
	for i=1,#genes do
		local gene = genes[i]
		if gene.into == link.into and gene.out == link.out then
			return true
		end
	end
end


function pointMutate(genome)
	local step = genome.mutationRates["step"]
	
	for i=1,#genome.genes do
		local gene = genome.genes[i]
		if math.random() < PerturbChance then
			gene.weight = gene.weight + math.random() * step*2 - step
		else
			gene.weight = math.random()*4-2
		end
	end
end


function linkMutate(genome, forceBias)
	local neuron1 = randomNeuron(genome.genes, false)
	local neuron2 = randomNeuron(genome.genes, true)
	 
	local newLink = newGene()
	if neuron1 <= Inputs and neuron2 <= Inputs then
		--Both input nodes
		return
	end
	if neuron2 <= Inputs then
		-- Swap output and input
		local temp = neuron1
		neuron1 = neuron2
		neuron2 = temp
	end

	newLink.into = neuron1
	newLink.out = neuron2
	if forceBias then
		newLink.into = Inputs
	end
	
	if containsLink(genome.genes, newLink) then
		return
	end
	newLink.innovation = newInnovation()
	newLink.weight = math.random()*4-2
	
	table.insert(genome.genes, newLink)
end


function nodeMutate(genome)
	if #genome.genes == 0 then
		return
	end

	genome.maxneuron = genome.maxneuron + 1

	local gene = genome.genes[math.random(1,#genome.genes)]
	if not gene.enabled then
		return
	end
	gene.enabled = false
	
	local gene1 = copyGene(gene)
	gene1.out = genome.maxneuron
	gene1.weight = 1.0
	gene1.innovation = newInnovation()
	gene1.enabled = true
	table.insert(genome.genes, gene1)
	
	local gene2 = copyGene(gene)
	gene2.into = genome.maxneuron
	gene2.innovation = newInnovation()
	gene2.enabled = true
	table.insert(genome.genes, gene2)
end


function enableDisableMutate(genome, enable)
	local candidates = {}
	for _,gene in pairs(genome.genes) do
		if gene.enabled == not enable then
			table.insert(candidates, gene)
		end
	end
	
	if #candidates == 0 then
		return
	end
	
	local gene = candidates[math.random(1,#candidates)]
	gene.enabled = not gene.enabled
end


function mutate(genome)
	for mutation,rate in pairs(genome.mutationRates) do
		if math.random(1,2) == 1 then
			genome.mutationRates[mutation] = 0.95*rate
		else
			genome.mutationRates[mutation] = 1.05263*rate
		end
	end

	if math.random() < genome.mutationRates["connections"] then
		pointMutate(genome)
	end
	
	local p = genome.mutationRates["link"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, false)
		end
		p = p - 1
	end

	p = genome.mutationRates["bias"]
	while p > 0 do
		if math.random() < p then
			linkMutate(genome, true)
		end
		p = p - 1
	end
	
	p = genome.mutationRates["node"]
	while p > 0 do
		if math.random() < p then
			nodeMutate(genome)
		end
		p = p - 1
	end
	
	p = genome.mutationRates["enable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutationRates["disable"]
	while p > 0 do
		if math.random() < p then
			enableDisableMutate(genome, false)
		end
		p = p - 1
	end
end


function disjoint(genes1, genes2)
	local i1 = {}
	for i = 1,#genes1 do
		local gene = genes1[i]
		i1[gene.innovation] = true
	end

	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = true
	end
	
	local disjointGenes = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if not i2[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end
	
	for i = 1,#genes2 do
		local gene = genes2[i]
		if not i1[gene.innovation] then
			disjointGenes = disjointGenes+1
		end
	end
	
	local n = math.max(#genes1, #genes2)
	
	return disjointGenes / n
end


function weights(genes1, genes2)
	local i2 = {}
	for i = 1,#genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = gene
	end

	local sum = 0
	local coincident = 0
	for i = 1,#genes1 do
		local gene = genes1[i]
		if i2[gene.innovation] ~= nil then
			local gene2 = i2[gene.innovation]
			sum = sum + math.abs(gene.weight - gene2.weight)
			coincident = coincident + 1
		end
	end
	
	return sum / coincident
end


function rankGlobally()
	local global = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		for g = 1,#species.genomes do
			table.insert(global, species.genomes[g])
		end
	end
	table.sort(global, function (a,b)
		return (a.fitness < b.fitness)
	end)
	
	for g=1,#global do
		global[g].globalRank = g
	end
end


function calculateAverageFitness(species)
	local total = 0
	
	for g=1,#species.genomes do
		local genome = species.genomes[g]
		total = total + genome.globalRank
	end
	
	species.averageFitness = total / #species.genomes
end


function totalAverageFitness()
	local total = 0
	for s = 1,#pool.species do
		local species = pool.species[s]
		total = total + species.averageFitness
	end

	return total
end


function cullSpecies(cutToOne)
	for s = 1,#pool.species do
		local species = pool.species[s]
		
		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)
		
		local remaining = math.ceil(#species.genomes/2)
		if cutToOne then
			remaining = 1
		end
		while #species.genomes > remaining do
			table.remove(species.genomes)
		end
	end
end


function breedChild(species)
	local child = {}
	if math.random() < CrossoverChance then
		g1 = species.genomes[math.random(1, #species.genomes)]
		g2 = species.genomes[math.random(1, #species.genomes)]
		child = crossover(g1, g2)
	else
		g = species.genomes[math.random(1, #species.genomes)]
		child = copyGenome(g)
	end
	
	mutate(child)
	
	return child
end


function removeStaleSpecies()
	local survived = {}

	for s = 1,#pool.species do
		local species = pool.species[s]
		
		table.sort(species.genomes, function (a,b)
			return (a.fitness > b.fitness)
		end)
		
		if species.genomes[1].fitness > species.topFitness then
			species.topFitness = species.genomes[1].fitness
			species.staleness = 0
		else
			species.staleness = species.staleness + 1
		end
		if species.staleness < StaleSpecies or species.topFitness >= pool.maxFitness then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end


function removeWeakSpecies()
	local survived = {}

	local sum = totalAverageFitness()
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population)
		if breed >= 1 then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end


function addToSpecies(child)
	local foundSpecies = false
	for s=1,#pool.species do
		local species = pool.species[s]
		if not foundSpecies and sameSpecies(child, species.genomes[1]) then
			table.insert(species.genomes, child)
			foundSpecies = true
		end
	end
	
	if not foundSpecies then
		local childSpecies = newSpecies()
		table.insert(childSpecies.genomes, child)
		table.insert(pool.species, childSpecies)
	end
end


function newGeneration()
	cullSpecies(false) -- Cull the bottom half of each species
	rankGlobally()
	removeStaleSpecies()
	rankGlobally()
	for s = 1,#pool.species do
		local species = pool.species[s]
		calculateAverageFitness(species)
	end
	removeWeakSpecies()
	local sum = totalAverageFitness()
	local children = {}
	for s = 1,#pool.species do
		local species = pool.species[s]
		breed = math.floor(species.averageFitness / sum * Population) - 1
		for i=1,breed do
			table.insert(children, breedChild(species))
		end
	end
	cullSpecies(true) -- Cull all but the top member of each species
	while #children + #pool.species < Population do
		local species = pool.species[math.random(1, #pool.species)]
		table.insert(children, breedChild(species))
	end
	for c=1,#children do
		local child = children[c]
		addToSpecies(child)
	end
	
	pool.generation = pool.generation + 1
	
	writeFile("backup." .. pool.generation .. "." .. forms.gettext(saveLoadFile))
end

	
function initializePool()

	pool = newPool()

	for i=1,Population do
		basic = basicGenome()
		addToSpecies(basic)
	end

	initializeRun()
end


function nextGenome()

	pool.currentGenome = pool.currentGenome + 1
	if pool.currentGenome > #pool.species[pool.currentSpecies].genomes then
		pool.currentGenome = 1
		pool.currentSpecies = pool.currentSpecies+1
		if pool.currentSpecies > #pool.species then
			newGeneration()
			pool.currentSpecies = 1
		end
	end

end


function fitnessAlreadyMeasured()

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	
	return genome.fitness ~= 0
end


function writeFile(filename)
        local file = io.open(filename, "w")
	file:write(pool.generation .. "\n")
	file:write(pool.maxFitness .. "\n")
	file:write(#pool.species .. "\n")
        for n,species in pairs(pool.species) do
		file:write(species.topFitness .. "\n")
		file:write(species.staleness .. "\n")
		file:write(#species.genomes .. "\n")
		for m,genome in pairs(species.genomes) do
			file:write(genome.fitness .. "\n")
			file:write(genome.maxneuron .. "\n")
			for mutation,rate in pairs(genome.mutationRates) do
				file:write(mutation .. "\n")
				file:write(rate .. "\n")
			end
			file:write("done\n")
			
			file:write(#genome.genes .. "\n")
			for l,gene in pairs(genome.genes) do
				file:write(gene.into .. " ")
				file:write(gene.out .. " ")
				file:write(gene.weight .. " ")
				file:write(gene.innovation .. " ")
				if(gene.enabled) then
					file:write("1\n")
				else
					file:write("0\n")
				end
			end
		end
        end
        file:close()
end


function savePool()
	local filename = forms.gettext(saveLoadFile)
	writeFile(filename)
end


function loadFile(filename)
        local file = io.open(filename, "r")
	pool = newPool()
	pool.generation = file:read("*number")
	pool.maxFitness = file:read("*number")

	--Changed GUI text only. AEP.
	forms.settext(maxFitnessLabel, "Pool Max Fitness: " .. math.floor(pool.maxFitness))
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
	
	while fitnessAlreadyMeasured() do
		nextGenome()
	end

	initializeRun("loading")

	pool.currentFrame = pool.currentFrame + 1
end
 

function loadPool()
	local filename = forms.gettext(saveLoadFile)
	loadFile(filename)
end


function playTop()
	local maxfitness = 0
	local maxs, maxg
	for s,species in pairs(pool.species) do
		for g,genome in pairs(species.genomes) do
			if genome.fitness > maxfitness then
				maxfitness = genome.fitness
				maxs = s
				maxg = g
			end
		end
	end
	
	pool.currentSpecies = maxs
	pool.currentGenome = maxg
	pool.maxFitness = maxfitness
	
	--Changed GUI text only. AEP.
	forms.settext(maxFitnessLabel, "Pool Max Fitness: " .. math.floor(pool.maxFitness))

	initializeRun("loading")

	pool.currentFrame = pool.currentFrame + 1

	return
end





--*****************************************************--

--On first run
if pool == nil then
	initializePool()
end

writeFile("temp.pool")


--BizHawk GUI box
function onExit()
	forms.destroy(form)
end


event.onexit(onExit)

form = forms.newform(200, 260, "Fitness")
maxFitnessLabel = forms.label(form, "Pool Max Fitness: " .. math.floor(pool.maxFitness), 5, 8)
restartButton = forms.button(form, "Restart", initializePool, 5, 77)
saveButton = forms.button(form, "Save", savePool, 5, 102)
loadButton = forms.button(form, "Load", loadPool, 80, 102)
saveLoadFile = forms.textbox(form, Filename .. ".pool", 170, 25, nil, 5, 148)
saveLoadLabel = forms.label(form, "Save/Load:", 5, 129)
playTopButton = forms.button(form, "Play Top", playTop, 5, 170)
hideBanner = forms.checkbox(form, "Hide Banner", 5, 190)


--Main loop
while true do

	local backgroundColor = 0xD0FFFFFF

	if not forms.ischecked(hideBanner) then
		gui.drawBox(0, 40, 320, 80, backgroundColor, backgroundColor)
	end

	local species = pool.species[pool.currentSpecies]
	local genome = species.genomes[pool.currentGenome]
	
	
	if pool.currentFrame%5 == 0 then
		evaluateCurrent()
	end


	--For GUI display only. Genome fitness is calculated once gameovercheck() returns true.
	local fitness = matchFitness

	if RoundCheckCounter == 0 then
		fitness = fitness + getrtFitness()
	end



	local measured = 0
	local total = 0

	for _,species in pairs(pool.species) do
		for _,genome in pairs(species.genomes) do
			total = total + 1
			if genome.fitness ~= 0 then
				measured = measured + 1
			end
		end
	end


	if not forms.ischecked(hideBanner) then

		gui.drawText(5, 45, "Generation " .. pool.generation .. " species " .. pool.currentSpecies .. " genome " .. pool.currentGenome .. " (" .. math.floor(measured/total*100) .. "%)", 0xFF000000, 11)
		gui.drawText(10, 60, "Fitness: " .. math.floor(fitness), 0xFF000000, 11)
		gui.drawText(170, 60, "Max Fitness: " .. math.floor(pool.maxFitness), 0xFF000000, 11)

	end

		
	pool.currentFrame = pool.currentFrame + 1

	emu.frameadvance()
end


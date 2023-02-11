#!/bin/julia

# Copyright (C) 2023 photomultiplier
# This program is licensed under the GNU General Public License.
# Detailed licensing information is available in the "LICENSE" file.

println("*** WELCOME TO PINsound ***")

# Legal information

println()
println("""
PINsound Copyright (C) 2023 photomultiplier
This program comes with ABSOLUTELY NO WARRANTY.
This is free software, and you are welcome to redistribute it
under certain conditions; see 'LICENSE' file for details.""")

#
# OPTIONS
#

const samples = 4096
const thr = 0.4
const bins = 50

#
# FUNCTIONS
#

function safeInput(message, T::Type, min = 0, max = nothing)
	local again = true

	local n = 0

	local under() = min == nothing ? false : n < min
	local over()  = max == nothing ? false : n > max

	while again || under() || over()
		println(message)
		n = try
			again = false
			parse(T, readline())
		catch e
			if isa(e, ArgumentError)
				again = true
				0
			else
				throw(e)
			end
		end
	end

	n
end

#
# LIBRARIES
#

println()
println("Loading libraries...")

import Pkg

Pkg.activate(".")
Pkg.instantiate()

using DataStructures
using StatsBase
using GLMakie
using PortAudio
using SampledSignals
using DataFrames
using CSV

#
# USER CONFIGURATION
#

# List available devices

println()
println("Available audio devices:")

for (i, d) in enumerate(PortAudio.devices())
	println("$i: $d")
end

# Select devices

din    = safeInput("Select input device:", Int, 1, size(PortAudio.devices())[1])
din_c  = safeInput("Select number of input channels:", Int, 1)
if din_c > 1
	din_mc = safeInput("Select channel to be used for input:", Int, 1, din_c)
else
	din_mc = 1
end
dout   = safeInput("Select output device:", Int, 1, size(PortAudio.devices())[1])
dout_c = safeInput("Select number of output channels:", Int, 1)

#
# INITIALIZATION
#

println()
println("Initializing...")

# Open the audio stream

audioStreamIn  = PortAudioStream(PortAudio.devices()[din],  din_c, 0)
audioStreamOut = PortAudioStream(PortAudio.devices()[dout], 0, dout_c)

simulatedClick = SampleBuf{eltype(audioStreamOut), 1}(vcat(zeros(2046), ones(4), zeros(2046)), audioStreamOut.sample_rate)

# Audio buffer

buf = SampleBuf{eltype(audioStreamIn), din_c}(din_c == 1 ? zeros(samples) : zeros(samples, din_c), audioStreamIn.sample_rate) # I'm using observables to make the plots interactive

# Events buffer

function newEvents(time, energy)
	DataFrame(time = time, energy = energy)
end

function resetEvents()
	newEvents(Vector{Float64}(), Vector{Float64}())
end

events = Observable(resetEvents())

# Status buffer

mutable struct Status
	sampleTime::Union{Float64, Nothing}
	dutyCycle::Union{Float64, Nothing}
end

function genStatusText(s::Status)
	sampleTimeString = s.sampleTime == nothing ? "..." : "$(round(s.sampleTime; digits = 3)) ms"
	dutyCycleString  = s.dutyCycle  == nothing ? "..." : "$(round(s.dutyCycle ; digits = 3)) %"
	"""
	Time for $samples samples: $sampleTimeString
	Duty cycle: $dutyCycleString"""
end

status = Observable(Status(nothing, nothing))

# Duty cycle buffer

dutyCycleCB = Observable(CircularBuffer{Float64}(50))

# Register atexit function

atexit() do
	println()
	println("Program ended!")

	println("Closing audio streams...")
	close(audioStreamIn)
	close(audioStreamOut)

	if size(events[])[1] > 0
		if size(events[])[1] >= 5
			println("Last five events:")
			println(events[][end-4:end,:])
		else
			println("Last event:")
			println(events[][end,:])
		end

		println("Save data (y/n)?")
		if !(readline() == "n")
			println("File name:")
			CSV.write(readline(), events[])
		end
	else
		println("No events were captured!")
	end

	println()
	println("All done, goodbye!")
end

# Initialize GLMakie window

# Figure

f = Figure()

# Axis for the waveform

axAudio_y = Observable(zeros(samples))

axAudio = Axis(
	f[1,1];
	title = "Last waveform", titlealign = :left, titlesize = 25,
	subtitle = "With energies above $thr ADC", subtitlesize = 10,
	xlabel = "Sample number", ylabel = "Energy (ADC)",
	limits = (1, samples, -0.5, 1)
)

lines!(axAudio, 1:samples, axAudio_y)
lines!(axAudio, [1, samples], [thr, thr])

# Axis for the histogram

axEnergies_edges = range(thr, 2, bins+1)
axEnergies_x = axEnergies_edges[1:end-1] .+ (axEnergies_edges[2] - axEnergies_edges[1])/2
axEnergies_y = @lift fit(Histogram, $events.energy, axEnergies_edges).weights

axEnergies = Axis(
	f[1, 2];
	title = "Histogram", titlealign = :left, titlesize = 25,
	subtitle = "Events above $thr ADC", subtitlesize = 10,
	xlabel = "Energy (ADC)", ylabel = "Number of events",
	yminorticksvisible = true, yminorgridvisible = true, yminorticks = IntervalsBetween(5),
	limits = @lift (axEnergies_x[1], axEnergies_x[end], 0, max(ceil(maximum($axEnergies_y)*0.12) * 10, 20))
)

stairs!(axEnergies, axEnergies_x, axEnergies_y; step = :center)

# Label for the status

Label(f[2,1], @lift genStatusText($status))

# Duty cycle

axDutyCycle_edges = range(50,100,16)
axDutyCycle_x = axDutyCycle_edges[1:end-1] .+ (axDutyCycle_edges[2] - axDutyCycle_edges[1])/2

axDutyCycle = Axis(
	f[2:3, 2];
	title = "Duty cycle", titlealign = :left, titlesize = 20,
	xlabel = "Duty cycle (%)", ylabel = "Number of frames",
	limits = (axDutyCycle_x[1], axDutyCycle_x[end], 0, 50)
)

stairs!(axDutyCycle, axDutyCycle_x, @lift fit(Histogram, $dutyCycleCB, axDutyCycle_edges).weights; step = :center)

# Buttons

run = true
click = false

buttongrid = GridLayout(f[3,1])

on(Button(buttongrid[1,1]; label = "Restart").clicks) do clicks
	global events[] = resetEvents()
end

on(Button(buttongrid[1,2]; label = "Click").clicks) do clicks
	global click = !click
end

on(Button(buttongrid[1,3]; label = "Quit").clicks) do clicks
	global run = false
end

# Layout

colsize!(f.layout, 1, Relative(1/2))
rowsize!(f.layout, 1, Relative(3/4))

# Display the figure

display(f)

# Function to analyse an audio window

function countPeaks(values)
	local energies = []
	local frames   = []

	local count = 0
	local above = false

	for (i, v) in enumerate(values)
		local vthr = v > thr

		if vthr
			if above
				if energies[end] < v
					energies[end] = v
				end
			else
				push!(energies, v)
				push!(frames,   i)
				count += 1
				above = true
			end
		end

		above = vthr
	end

	count, energies, frames
end

#
# MAIN LOOP
#

while run
	# Mark the time at the beginning of the loop

	start = time()

	# Read from the stream

	read!(audioStreamIn, buf)

	# Mark the time after reading

	readend = time()

	# Save the time difference

	status[].sampleTime = (readend - start) * 1000

	# Analyse the data

	peaks, newEnergies, newFrames = countPeaks(buf.data[:,din_mc])

	if peaks > 0
		# Click

		if click
			write(audioStreamOut, simulatedClick)
		end

		axAudio_y[] = buf.data[:,1]

		append!(events[], newEvents(newFrames ./ audioStreamIn.sample_rate .+ start, newEnergies))
		notify(events)

		status[].dutyCycle = (readend - start) / (time() - start) * 100
		push!(dutyCycleCB[], status[].dutyCycle)
		notify(dutyCycleCB)
	end

	notify(status)
end

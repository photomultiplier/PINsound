# PINsound

Julia program to read the sound of a PIN diode.

## Vocabulary

First, a quick note on vocabulary conventions for this document.

The program collects and analyzes data in a loop.
During each cycle, an **audio snippet** is recorder.
The program then looks for particles - there can be multiple for each snippet - and records each one as an **event**.
I'll refer to cycles with one or more events recorded as **eventful cycles**, and to the audio snippet of eventful cycles as **eventful audio snippets**.

## How to use

To use the program, clone the repository locally and run `julia PINsound.jl` inside.
When the program boots, after loading the libraries (which get downloaded automatically), it will scan for audio devices.

- Select the appropriate input device and its channels (if the device is set to more than one channel, you must then select which one to use).
- Select the appropriate output device and its channels (the program can optionally output a "click" on each eventful cycle).

After that, a GLMakie GUI will load.

## GUI

The GUI window is structured as follows:

|    Left column     |   Right column   |
| :----------------: | :--------------: |
| Last audio snippet | Events histogram |
| Status and buttons | Duty cycle graph |

- **Last audio snippet**: This section is a graph containing the last eventful audio snippet.
- **Events histogram**: This section is an histogram of all the events recorded in the current session.
- **Status**, **Duty cycle graph**: Information about the application (more information to follow).
- **Buttons**
  - `Restart`: Delete all data in the current session and start a new one.
  - `Click`: Enable audio feedback.
  - `Quit`: Quit the application.
    Before closing, the terminal will ask you if you want to save the current session.
    If yes, it will then ask you for a file name - remember to include the extension.
    The data will be saved in CSV format.

## Status information

The program shows two main statistics: acquisition time and duty cycle.

- Acquisition time is the time required to capture an audio snippet.
- Duty cycle is the amount of time the program spent recording audio in the last cycle - for example, a 75% duty cycle means that the program spent 75% of its time recording and 25% of the time analyzing the snippet.
  You want this to be as high as possible, as so not to skip any particles.
  This is only updated on eventful cycles.

This said, the **duty cycle graph** is just an histogram containing the duty cycle of the last 100 eventful cycles.

## Data saved

Data is stored internally as a [DataFrame](https://dataframes.juliadata.org).
Each row contains the time and energy of a particle.

| Quantity | Details             | Type      | Column |
| :------- | :------------------ | :-------- | :----- |
| Time     | Seconds since epoch | `Float64` | 1      |
| Energy   | Arbitrary units     | `Float64` | 2      |

## Options

At the beginning of the `PINsound.jl` are a set of options.
Here's what they do.

| Option  | Default | Explanation                                                                                                    |
| :------ | :------ | :------------------------------------------------------------------------------------------------------------- |
| samples | 4096    | The number of data points in each audio snippet. This doesn't affect sample rate, which depends on the device. |
| thr     | 0.4     | The energy threshold at which events are detected.                                                             |
| bins    | 50      | The number of bins for the histogram window.                                                                   |

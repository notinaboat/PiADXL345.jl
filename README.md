# PiADXL345.jl

Julia interface for [ADXL345](https://www.analog.com/en/products/adxl345.html)
Accelerometer on Raspberry Pi.

![ADXL345 Module](https://components101.com/sites/default/files/component_pin/ADXL345-Pinout.jpg)

In the example below the ADXL345 is connected to the Raspberry Pi's GPIO header
as follows: CS = GPIO4, SDO = GPIO17, SDA = GPIO27, SCL = GPIO18.

```julia
julia> using PiADXL345

julia> adxl = adxl_open(cs=4, sdo=17, sda=27, scl=18)
PiADXL345.ADXL345(0x04)

julia> v = take!(adxl)
3-element Array{Int64,1}:
  144
  123
 -181

julia> v = PiADXL345.pitch_and_roll(take!(adxl))
(pitch = 0.9572953530227399, roll = 55.38053437654027)

julia> versioninfo()

Julia Version 1.5.2
Commit 539f3ce* (2020-09-23 23:17 UTC)
Platform Info:
  OS: Linux (arm-linux-gnueabihf)
  CPU: ARMv6-compatible processor rev 7 (v6l)
  WORD_SIZE: 32
  LIBM: libm
  LLVM: libLLVM-9.0.1 (ORCJIT, arm1176jz-s)
```

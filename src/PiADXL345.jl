# References:
# [1] 3-Axis Digital Accelerometer ADXL345 - D07925-0-5/09(0)

module PiADXL345

export adxl_open


using BBSPI

using PiGPIOC
import PiGPIOC.gpioInitialise
import PiGPIOC.gpioDelay
import PiGPIOC.gpioSetMode
import PiGPIOC.gpioRead
import PiGPIOC.gpioWrite

struct Pin
    pin::UInt8
end
Base.setindex!(p::Pin, v) = gpioWrite(p.pin, v)
Base.getindex(p::Pin) = gpioRead(p.pin)

struct NPin
    pin::UInt8
end
Base.setindex!(p::NPin, v) = gpioWrite(p.pin, v == 0 ? 1 : 0)
Base.getindex(p::NPin) = gpioRead(p.pin) == 0 ? 1 : 0

BBSPI.delay(s::BBSPI.SPISlave) = gpioDelay(10)


struct ADXL345{T} <: AbstractChannel{Vector{UInt16}}
    spi::T
end


"""
    adxl_open(;cs=4, sdo=17, sda=27, scl=18)::ADXL345

Open ADXL345 conencted to GPIO pins `cs`, `sdo`, `sda` and `scl`.
"""
function adxl_open(;cs=4, sdo=17, sda=27, scl=18)

    res = gpioInitialise();
    @assert(res != PiGPIOC.PI_INIT_FAILED)

    gpioSetMode(cs, PiGPIOC.PI_OUTPUT)
    gpioSetMode(scl, PiGPIOC.PI_OUTPUT)
    gpioSetMode(sda, PiGPIOC.PI_OUTPUT)

    for p in sdo
        gpioSetMode(p, PiGPIOC.PI_INPUT)
    end

    spi = BBSPI.SPISlave(cs=NPin(cs),
                         clk=NPin(scl),
                         mosi=Pin(sda),
                         miso=[Pin(p) for p in sdo])

    adxl_open(spi)
end


function adxl_open(spi)

    spi.chip_select[] = 0
    spi.clock[] = 0

    @assert adxl_is_connected(spi)

    adxl_enable(spi)
    adxl_bw_rate_12hz5(spi)

    ADXL345(spi)
end


adxl_is_connected(spi) = all(adxl_read(spi, 0) .== 0xE5) # DEVID [1, p15]

adxl_enable(spi) = adxl_write(spi, 0x2D, 0b00001000) # POWER_CTL [1, p16]

adxl_bw_rate_12hz5(spi) = adxl_write(spi, 0x2C, 0b00000111) # BW_RATE [1, p16]


"""
    adxl_read(spi, address, n=1)

Read `n` bytes from `address`.
"""
function adxl_read(spi, address, n=1)
    n += 1
    cin=zeros(UInt8, n+1, BBSPI.output_width(spi))
    cout = [0b11000000 | address] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(spi, cout, cin)
    return view(cin, 2:n, :)
end


"""
    adxl_write(spi, address, v)

Write byte `v` to `address`.
"""
function adxl_write(spi, address, v)
    cout = UInt8[address, UInt8(v)] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(spi, cout)
    nothing
end


"""
    take!(::ADXL345)

Read [x,y,z] vector from ADXL345.
"""
function Base.take!(adxl::ADXL345)

    v = adxl_read(adxl.spi, 0x32, 6) # DATAX0... Register [1, p18]
    x = signed.((|).(v[1,:], (<<).(UInt16.(v[2,:]), 8)))
    y = signed.((|).(v[3,:], (<<).(UInt16.(v[4,:]), 8)))
    z = signed.((|).(v[5,:], (<<).(UInt16.(v[6,:]), 8)))
    vcat(permutedims.([x, y, z])...)
end


pitch_and_roll(v) = (pitch = atan(-v[1], hypot(v[2], v[3])) * 180 / π,
                     roll  = atan( v[2],             v[3])  * 180 / π)


function adxl_demo()
    #adxl = adxl_open(cs=4, sdo=17, sda=27, scl=18)
    adxl = adxl_open(cs=4, sdo=[17,17], sda=27, scl=18)

    while true
        t = time()
        for v in eachcol(take!(adxl))
            @show pitch_and_roll(v)
        end
        sleep(max(0, 0.08 - (time() - t)))
    end
end


end # module


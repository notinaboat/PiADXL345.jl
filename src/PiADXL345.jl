# References:
# [1] 3-Axis Digital Accelerometer ADXL345 - D07925-0-5/09(0)

module PiADXL345

export adxl_open


using BBSPI
using PiGPIOMEM

"""
GPIOPin with inverted logic (Low = `true`, High = `false`).
"""
struct ActiveLowPin
    pin::GPIOPin
end
Base.setindex!(p::ActiveLowPin, v) = p.pin[] = iszero(v) ? 1 : 0
Base.getindex(p::ActiveLowPin) = iszero(p.pin[])

"""
Bit-delay for bit-bangged SPI.
"""
BBSPI.delay(s::BBSPI.SPISlave) = PiGPIOMEM.spin(50)


struct ADXL345{T} <: AbstractChannel{Tuple{Float64,Float64,Float64}}
    spi::T
    buf::Vector{UInt8}
    ADXL345(spi::T) where T = new{T}(spi, zeros(UInt8, 10))
end


"""
    adxl_open(;cs=chip select output pin,
              sdo=master input pin,
              sda=master output pin,
              scl=clock output pin)::ADXL345

Open ADXL345 conencted to GPIO pins `cs`, `sdo`, `sda` and `scl`.

Methods must be defined for `setindex!(::PinType, v)` and `getindex(::PinType)`.
See `help?> SPISlave`.
"""
function adxl_open(;cs=nothing, scl=nothing, sda=nothing, sdo=nothing)

    adxl_open(BBSPI.SPISlave(cs=ActiveLowPin(cs),
                             clk=ActiveLowPin(scl),
                             mosi=sda,
                             miso=sdo))
end


function adxl_open(spi)

    spi.chip_select[] = 0
    spi.clock[] = 0

    adxl = ADXL345(spi)

    @assert adxl_is_connected(adxl)

    adxl_enable(adxl)
    adxl_bw_rate_12hz5(adxl)

    adxl
end


adxl_is_connected(adxl) = adxl_read(adxl, 0) == 0xE5 # DEVID [1, p15]

adxl_enable(adxl) = adxl_write(adxl, 0x2D, 0b00001000) # POWER_CTL [1, p16]

adxl_offset(adxl) = [adxl_read(adxl, 0x1E), # OFSX [1, p15]
                     adxl_read(adxl, 0x1F), # OFSY [1, p15]
                     adxl_read(adxl, 0x20)] # OFSZ [1, p15]

function adxl_set_offset(adxl, x, y, z)
    adxl_write(adxl, 0x1E, unsigned(Int8(x))) # OFSX [1, p15]
    adxl_write(adxl, 0x1F, unsigned(Int8(y))) # OFSY [1, p15]
    adxl_write(adxl, 0x20, unsigned(Int8(z))) # OFSZ [1, p15]
end

adxl_bw_rate_12hz5(adxl) = adxl_write(adxl, 0x2C, 0b00000111) # BW_RATE [1, p16]
adxl_bw_rate_25hz(adxl)  = adxl_write(adxl, 0x2C, 0b00001000) # BW_RATE [1, p16]
adxl_bw_rate_50hz(adxl)  = adxl_write(adxl, 0x2C, 0b00001001) # BW_RATE [1, p16]
adxl_bw_rate_100hz(adxl) = adxl_write(adxl, 0x2C, 0b00001010) # BW_RATE [1, p16]


"""
    adxl_read(adxl, address, n=1)

Read `n` bytes from `address`.
"""
function adxl_read(adxl, address, n)
    n += 1
    cout = UInt8[0b11000000 | address] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(adxl.spi, cout, view(adxl.buf, 1:n))
    return view(adxl.buf, 2:n)
end

adxl_read(adxl, address) = adxl_read(adxl, address, 1)[1]


"""
    adxl_write(adxl, address, v)

Write byte `v` to `address`.
"""
function adxl_write(adxl, address, v)
    cout = UInt8[address, v] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(adxl.spi, cout)
    nothing
end


"""
    take!(::ADXL345)

Read [x,y,z] vector from ADXL345.
"""
function Base.take!(adxl::ADXL345)

    v = adxl_read(adxl, 0x32, 6) # DATAX0... Register [1, p18]
    x = signed(v[1] | UInt16(v[2]) << 8)/256 # 0.0039g/LSB [1, Table 1, p3]
    y = signed(v[3] | UInt16(v[4]) << 8)/256
    z = signed(v[5] | UInt16(v[6]) << 8)/256
    (x, y, z)
end


pitch_and_roll(v) = (pitch = atan(-v[1], hypot(v[2], v[3])) * 180 / π,
                     roll  = atan( v[2],             v[3])  * 180 / π)


function adxl_demo()
    adxl = adxl_open(cs=GPIOPin(26; output=true),
                     scl=GPIOPin(21; output=true),
                     sda=GPIOPin(20; output=true),
                     sdo=GPIOPin(16))

    while true
        t = time()
        v = take!(adxl)
        pr = pitch_and_roll(v)
        print(round(pr.pitch; digits=3), " ",
              round(pr.roll; digits=3), "      \r")
        sleep(max(0, 0.08 - (time() - t)))
    end
end


end # module

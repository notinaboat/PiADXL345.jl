# References:
# [1] 3-Axis Digital Accelerometer ADXL345 - D07925-0-5/09(0)

module PiADXL345

export adxl_open


using BBSPI

using PiGPIOMEM

struct ActiveLowPin
    pin::GPIOPin
end
Base.setindex!(p::ActiveLowPin, v) = p.pin[] = iszero(v) ? 1 : 0
Base.getindex(p::ActiveLowPin) = iszero(p.pin[])

BBSPI.delay(s::BBSPI.SPISlave) = PiGPIOMEM.spin(50)


struct ADXL345{T} <: AbstractChannel{Vector{UInt16}}
    spi::T
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

    @assert adxl_is_connected(spi)

    adxl_enable(spi)
    adxl_bw_rate_12hz5(spi)

    ADXL345(spi)
end


adxl_is_connected(spi) = all(adxl_read(spi, 0) .== 0xE5) # DEVID [1, p15]

adxl_enable(spi) = adxl_write(spi, 0x2D, 0b00001000) # POWER_CTL [1, p16]

adxl_offset(spi) = [adxl_read(spi, 0x1E), # OFSX [1, p15]
                    adxl_read(spi, 0x1F), # OFSY [1, p15]
                    adxl_read(spi, 0x20)] # OFSZ [1, p15]

function adxl_set_offset(spi, x, y, z)
    adxl_write(spi, 0x1E, unsigned(Int8(x))) # OFSX [1, p15]
    adxl_write(spi, 0x1F, unsigned(Int8(y))) # OFSY [1, p15]
    adxl_write(spi, 0x20, unsigned(Int8(z))) # OFSZ [1, p15]
end

adxl_bw_rate_12hz5(spi) = adxl_write(spi, 0x2C, 0b00000111) # BW_RATE [1, p16]
adxl_bw_rate_25hz(spi)  = adxl_write(spi, 0x2C, 0b00001000) # BW_RATE [1, p16]
adxl_bw_rate_50hz(spi)  = adxl_write(spi, 0x2C, 0b00001001) # BW_RATE [1, p16]
adxl_bw_rate_100hz(spi) = adxl_write(spi, 0x2C, 0b00001010) # BW_RATE [1, p16]


"""
    adxl_read(spi, address, n=1)

Read `n` bytes from `address`.
"""
function adxl_read(spi, address, n=1)
    n += 1
    cin=zeros(UInt8, n+1, BBSPI.output_width(spi))
    cout = UInt8[0b11000000 | address] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(spi, cout, cin)
    return view(cin, 2:n, :)
end


"""
    adxl_write(spi, address, v)

Write byte `v` to `address`.
"""
function adxl_write(spi, address, v)
    cout = UInt8[address, v] # SPI header [1, p9 Figure 5]
    BBSPI.transfer(spi, cout)
    nothing
end


"""
    take!(::ADXL345)

Read [x,y,z] vector from ADXL345.
"""
function Base.take!(adxl::ADXL345)

    v = adxl_read(adxl.spi, 0x32, 6) # DATAX0... Register [1, p18]
    x = @. signed(v[1,:] | UInt16(v[2,:]) << 8)
    y = @. signed(v[3,:] | UInt16(v[4,:]) << 8)
    z = @. signed(v[5,:] | UInt16(v[6,:]) << 8)
    vcat(permutedims.([x/256, y/256, z/256])...) # 0.0039g/LSB [1, Table 1, p3]
end


pitch_and_roll(v) = (pitch = atan(-v[1], hypot(v[2], v[3])) * 180 / π,
                     roll  = atan( v[2],             v[3])  * 180 / π)


function adxl_demo()
    adxl = adxl_open(cs=GPIOPin(4; output=true),
                     scl=GPIOPin(18; output=true),
                     sda=GPIOPin(27; output=true),
                     sdo=GPIOPin(17))
    #adxl = adxl_open(cs=4, sdo=[17,17], sda=27, scl=18)

    while true
        t = time()
        for v in eachcol(take!(adxl))
            pr = pitch_and_roll(v)
            print(round(pr.pitch; digits=3), " ",
                  round(pr.roll; digits=3), "      \r")
        end
        sleep(max(0, 0.08 - (time() - t)))
    end
end


end # module


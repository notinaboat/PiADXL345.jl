# References:
# [1] 3-Axis Digital Accelerometer ADXL345 - D07925-0-5/09(0)

module PiADXL345

export adxl_open



using PiGPIOC
import PiGPIOC.gpioInitialise
import PiGPIOC.bbSPIOpen
import PiGPIOC.bbSPIXfer


struct ADXL345 <: AbstractChannel{Vector{UInt16}}
    cs::UInt8
end


"""
    adxl_open(;cs=4, sdo=17, sda=27, scl=18)::ADXL345

Open ADXL345 conencted to GPIO pins `cs`, `sdo`, `sda` and `scl`.
"""
function adxl_open(;cs=4, sdo=17, sda=27, scl=18)

    res = gpioInitialise();
    @assert(res != PiGPIOC.PI_INIT_FAILED)

    err = bbSPIOpen(cs,
                    sdo,       # MISO
                    sda,       # MOSI
                    scl,
                    10000,     # baud
                    (1 << 1) | # CPOL, Clock polarity and phase [1, p8]
                    (1 << 0))  # CPHA
    @assert err == 0

    @assert adxl_is_connected(cs)

    adxl_enable(cs)
    adxl_bw_rate_12hz5(cs)

    ADXL345(cs)
end


adxl_is_connected(cs) = adxl_read(cs, 0)[1] == 0xE5 # DEVID Register [1, p15]

adxl_enable(cs) = adxl_write(cs, 0x2D, 0b00001000) # POWER_CTL [1, p16]

adxl_bw_rate_12hz5(cs) = adxl_write(cs, 0x2C, 0b00000111) # BW_RATE [1, p16]


"""
    adxl_read(cs, address, n=1)

Read `n` bytes from `address`.
"""
function adxl_read(cs, address, n=1)
    n += 1
    cout = zeros(UInt8, n)
    cin = zeros(UInt8, n)
    cout[1] = 0b11000000 | address # SPI header [1, p9 Figure 5]
    bbSPIXfer(cs, cout, cin, n)
    return view(cin, 2:n)
end


"""
    adxl_write(cs, address, v)

Write byte `v` to `address`.
"""
function adxl_write(cs, address, v)
    cout = UInt8[address, UInt8(v)] # SPI header [1, p9 Figure 5]
    cin = zeros(UInt8, 2)
    bbSPIXfer(cs, cout, cin, 2)
    nothing
end


"""
    take!(::ADXL345)

Read [x,y,z] vector from ADXL345.
"""
function Base.take!(adxl::ADXL345)
    v = adxl_read(adxl.cs, 0x32, 6) # DATAX0... Register [1, p18]
    x = signed(UInt16(v[2]) << 8 | v[1])
    y = signed(UInt16(v[4]) << 8 | v[3])
    z = signed(UInt16(v[6]) << 8 | v[5])
    Int64[x, y, z]
end


pitch_and_roll(v) = [atan(-v[1], sqrt(v[2]^2 + v[3]^2)) * 180 / π,
                     atan(v[2], v[3]) * 180 / π]


function adxl_demo()
    adxl = adxl_open(cs=4, sdo=17, sda=27, scl=18)

    while true
        t = time()
        v = pitch_and_roll(take!(adxl))
        @show v
        sleep(max(0, 0.08 - (time() - t)))
    end
end


end # module


# Components


### Nav Module Circuit

This is intended to be a general overview of the NavModule.V2 designed by the former NAV-Team, Elin and Halvor. The module consists of several 
complex parts, and a fundamental understanding of each part is needed to understand the whole project. 


## Processor

The processor chosen was the ATSAME53J18A-MF. It being an ARM-based processor allows for quicker and more complex calculations, which is essential for the
Kalman-Filter operating as expected. It allows us to control all the sensors listed in this document.

It has several SERCOM connectors, allowing us to communicate data through the SPI, USART, I2C and more. Most relevant are the SPI and I2C, as they are
serial interfaces featured by ALL the major components that send and recieve data live, except for the SD-Card.


## IMU

Navigation Module V2 has the IMU ISM330DHCX, equipped with 3D accelerometer and 3D Gyroscope. Similar to the ATSAM device, it has an SPI and I2C serial interface,
making communication between them <em>"easy"</em>

An IMU is critical in our Navigation system, as the data it provides is essential for whatever math the Kalman-Filter does. Essentially, the IMU combines the power of their
accelerometer and gyroscope, with the accelerometer measures linear acceleration, while the gyroscope measures the rate of rotation around a given axis. 

## Magnetometer

An IMU can drift over time, and eventually give bad data. Therefore it is more than just good practice to combine several different sensor that work together to create the most 
accurate representation we can. A magnetometer is used to determine the direction relative to the earths magnetic north(i.e MAGNETometer). This can be used to correct any drift from
the IMU that accumulates over time.

## Pressure Sensor

MS5611-01BA03 is an Barometric Pressure Sensor, located in the V2 module. As the rocket rises above sea level, the air pressure around it will change. A Barometric Pressure Sensor
will keep track of the Air Pressure, and use it to estimate the rockets altitude over sea level.

## Micro SD-Card

We also have an SD-Card slot in the module, as we want to be able to store and reload the data that is collected throughout the launch. Both in case of an unexpected system restart,
as well as data to process on ground in preparation of the next rocket.

## FRAM

## LDO

## Battery Holder

## Power MUX

## Connectors

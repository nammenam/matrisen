# Pressure Sensor

The MS5611-01BA03 is a steel cap barometric sensor, with the ability to measure pressure and temperature. The main function of the barometer for us is to get the pressure in mbar, and use the barometric formula to estimate our height above see level. 

## Interface

The interface of the pressure sensor is quite simple. In the initialization stage of the application, we call 

```cpp
PSInit(Barometer* device);
```

The device should be a variable you have access to in the logical
abstraction layer of the app. In our case it is stored in appData in app.cpp, which handles our internal logic of the app, just one abstraction layer below main.cpp 

```cpp
PSupdate();
```

Handles all the internal processes of making the sensor read data, reading from the Analog to Digital Converter, and making sense of the data. After this function is called we can now access the data
made by the barometric sensor, which we do by reading variables stored in the barometer typedef. 

```cpp
device.pressureResult;
```

Which is in our case, again stored within appData, making us do: 

```cpp
appData.barometer.pressureResult;
```

## Implementation

### Initialization

As for all the SPI sensors, we set the SLAVE_SELECT to LOW when communicating with it, and set it HIGH again when we are done. We learned that lesson the hard way :)

The initialization of the device takes care of a few things. It triggers a reset, specified to be standard procedure by the datasheet. Thereafter, we read the PROM, which are registers storing factory calibrated
data. Specifically for these values: 

```cpp
typedef struct
{
    uint16_t sens;       // C1 Pressure sensitivity                             | SENS_t1
    uint16_t off;        // C2 Pressure offset                                  | OFF_t1
    uint16_t tcs;        // C3 Temperature coefficient of pressure sensitivity  | TCS
    uint16_t tco;        // C4 Temperature coefficient of pressuer offset       | TCO
    uint16_t t_ref;      // C5 Reference temperature                            | T_ref
    uint16_t tempsens;   // C6 Temperature coefficient of the temperature       | TEMPSENSE
} ms561101ba03_config_data_t;
```

Which are all used to properly calculate the live data with the correct offsets and coefficients. We loop through the registers and place it in a temporary list, and we then assign them to member variables of an instance
of a barometer struct. 

The last stage of the initialization is setting the sample rate, which we set to 256 for us. The rate is important when developing further, as it directly impacts which register you read data from, and the time it takes
for the ADC to do its thing, ranging by up to 9 milliseconds! 

### Make Barometer read data

Before we actually get our hands on any of the data, we need to tell the barometer we want it to read it from the environment before we pass it through the ADC. 

We ask it to start getting data separately for both temperature and pressure, with the pressure being called 'D1', and temperature being called 'D2'. It is important to note that this is where the OSR value you decided on
starts getting important. Depending on which OSR rate, we have different registers to read the analog data. Since we have OSR = 256, we read from the following registers. 

D1 = Pressure = 0x40
D2 = Temperature = 0x50

If you have a different sample rate, you can find the correct address on page 10 in the datasheet. 

### Converting data from analog to digital

The last step is to convert the data stored in D1 and D2 to noice, decimal, understandable and readable data. For us, we want the data in mbar and celsius, so we kept that in mind when making the function to convert the data. The barometer also has
an option for combining the temperature data to get the pressure data even more accurate. For us we want the pressure data to be as accurate as possible, so we are still experimenting on using this feature to our benefit. The procedure is mostly 
just math formulas using the PROM data we read and stored in the initialization stage. For further details in the initialization stage, just look at the corresponding function in our implementation. It can be copied as long as you give the analog data 
D1 and D2, as well as the PROM data. 



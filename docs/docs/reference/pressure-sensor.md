### Pressure Sensor

The pressure sensor, also known as a barometer, has a self explanatory name. It estimates its own altitude based off the pressure from earth atmosphere.  



//pt_run() serves as the entry point of the module, it initialises the device, gets the sensor
data, calculates pressure and temperature and gets data.
```cpp
void pt_run()
{
    PT_SS_Set();
    
    ms561101ba03_t device = {
        .osr  = OSR_4096,
    };
    
    ms561101ba03_init(&device);
    
    ms561101ba03_get_sensor_data(&device);
    
    temperature_get(&device);
    pressure_get(&device);
    
}
```
The functions pressure_get() and temperature_get() serve as the the main interface of retrieving the data. It should
be called after pt_run, possibly in a the main loop of command-center to regurarly retrieve data. Both
functions return doubles, with pressure_get() return the pressure in mbar, and temperature_get() returning
the data in celsius.
```cpp
```




## Challenges
Pressure sensor is its own module, separate from the imu. This making it the first sensor that we interact with outside of the imu, which for sure will bring other
conventions and a small extra layer of challenges.

Personnaly, I do not know how the pressure sensor will work in terms of being inside a rocket. As a person with 0 experience in physics, I imagine the pressure inside
a rocket going at x mph is different than idling anywhere in the atmosphere. Does this mean we have to calibrate it to specifically work on a rocket? 

Former team has left the pressure sensor module with bits and pieces of code commented out with no
further explanation. We have to figure out if the commented out code are important or just nonsense.




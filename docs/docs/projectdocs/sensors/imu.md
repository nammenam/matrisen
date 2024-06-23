# Inertial Measurement Unit (IMU)  

> 🛈  accelerometer & gyroscope


The IMU is a central piece in COMPASS, as it is responsible for collecting data on force, angular rate (Maybe Orientation?). 

The IMU works by detecting linear accelaration using on more accelerometers and rotational rate using one or more gyroscopes, as well as a
magnetometer like in our case.

In our system, the data reported by the IMU is fed into our CPU, which will then calculate altitude, velocity and position.


The current imu implementation files can be located at:

Navigaton/COMPASS-harmony-project/firmware/src/sensors/imu.cpp
Navigaton/COMPASS-harmony-project/firmware/src/sensors/imu.hpp


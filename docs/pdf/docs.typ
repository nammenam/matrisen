#show raw: set text(
    font: "SplineSansM Nerd Font",
    weight: "medium",
)

#show heading.where(
  level: 1
): it => [
  #set text(size: 24pt, font: "DM Sans", weight: "bold")
  #block(it)
]

#show heading.where(
  level: 2
): it => [
  #set text(size: 14pt, font: "DM Sans", weight: "bold")
  #block(emph(it))
]

#show heading.where(
  level: 3
): it => [
  #set text(size: 10pt, font: "DM Sans", weight: "bold")
  #block(emph(it))
]

#let mbf(input) = {$upright(bold(#input))$}

#set text(
  font: "inter",
  size: 9pt,
)


= Kon-tiki final technical report: COMPASS

= About the project
the goal of the project is to give us an acurate reading of the rockst state eg velocity, position, orientation, and acceleration.
this is so that when the time is right we can deploy the parachute and land the rocket safely without tearing it apart.
it wil also give us a better understanding of the rocket and how it behaves in the air. and more easily recover the rocket
We do this by using a combination of sensors and a microcontroller to process the data and send it to the ground station
as well as store it on the rocket for redundancy and flight data analysis.

= Summary
The project is a success, we have a working prototype that has been tested in the field and in the lab.
the major takeaway is that the system works well for altitude estimation and orientation. but x and y velocity and position
is prone to drift. The reason for this is the lack of absolute positioning and velocity sensors like GPS and airspeed sensors.
The orientation and altitude states have such sensors and are therefore more accurate. Despite this, the system does a good job
of giving a rough estimate of the velocity and position. With so called "dead reckoning" we can estimate the position and velocity
without the need of telecommunication that GPS needs.

== Testing
[kalman unit tests]\
[pressure sensor tests]\
[magnetometer calibration tests]\
[imu visualisation tests]\
[drone flight tests]


== Development
As the project was based on previous projects the specs were already set in stone.
and they did not change much during the development of the project.
however the last iteration swapped the magnetometer for a more accurate one.
but the overall design and specs stayed the same.

== Timeline

// #figure(
//   image( "timeline.png", width: 90%)
// )

= Modeling
The navigation system is based on a state-space representation of the system.
The state of the system is defined as the orientation, velocity, and altitude of the rocket.
The dynamics of the system are described by a set of differential equations.
The sensors are used to measure the state of the system, and the Kalman filter is used to estimate the state of the system.
To estimate the state of the rocket, we must first build a model of the rocket's dynamics and
the measurement models of the sensors.
The dynamics of the rocket can be described by a set of differential equations.
The state of the rocket is defined as a vector of variables that describe the orientation,
velocity, and altitude of the rocket.

The general form of a dynamical system can be stated as
$ 
  &accent(bold(x),dot) = bold(f)(bold(x),bold(u)) + bold(w)_d\
  &accent(bold(y),hat) = bold(h(x,u)) + bold(w)_n\
$
where $bold(x)$ is the state vector, $bold(u)$ is the control vector, $bold(w)_d$ is the system disturbance,
$bold(y)$ is the measurement vector, $bold(w)_n$ is the measurement noise, $bold(f)$ is the dynamics of the system.
For linear systems we can use linear algebra to express our system
$
  &accent(bold(x),dot) = bold(F x + B u ) + bold(w)_d\
  &accent(bold(y),hat) = bold(H x + D u + w)_n
$
we can also descreteize our system (which is what we must do in order 
to use our computer algorithms)
#set math.equation(numbering: "(1)")
$
  &bold(x)_(t+1) = bold(f)_d (bold(x)_t,bold(u)_t) + bold(w)_d\
  &accent(bold(y),hat)_(t) = bold(h)_d (bold(x)_t, bold(u)_t) + bold(w)_n\
  \
  &"in the linear case"\
  &bold(x)_(t+1)= bold(F)_d bold(x)_t + bold(B)_d bold(u)_t + bold(w)_d\
  &accent(bold(y),hat)_(t) = bold(H)_d bold(x)_t + bold(D)_d bold(u)_t + bold(w)_n
$
#set math.equation(numbering: none)

in our case the vector $bold(u)$ is $0$ since we have no controll over the
rocket as far as the navigation system is concerned.
The state vector $bold(x)$ is defined as
$
  bold(x) = &vec(
    "orientation" in RR^4,
    "velocity" in RR^3,
    "altitude" in RR,
  )
$

== Coordinate systems
Before we can define the state of the rocket, we must agree upon the coordinate systems.
There are a some popular ones such as the NED (North-East-Down) and ENU (East-North-Up).
These coordinate systems define the choice of basis vectors (the directions of the axes).


We use the ENU coordinate system where the x-axis points east, the y-axis points north,
and the z-axis points up.

== Orientation and quaternions

The orientation of the rocket is represented by a quaternion.
A quaternion can be thought of as an
extenstion of complex numbers. It can be used to represent rotations and orientations
in 3D space, depending on the context.
The quaternion is defined as 
$
bold(q) = a + b mbf(i) + c mbf(j) + d mbf(k)
$
where $a,b,c,d$ are real numbers and $mbf(i),mbf(j),mbf(k)$ are the imaginary units.
It can be efficiently represented on a computer as a 4D vector.
$
  bold(q) = &vec(
    a,
    b,
    c,
    d,
  )
$
Without diving too deep into the math, the quaternion can be used to represent a rotation
$
  accent(bold(v),hat) = bold(q) bold(v) bold(q)^(-1)
$
$accent(bold(v),hat)$ is the result of rotating $bold(v)$ by $bold(q)$.
where $bold(v)$ and $accent(bold(v),hat)$ is 3D vectors expressed as a quaternion with the 
scalar part being $0$.
$
  bold(v) = &vec(
    0,
    v_1,
    v_2,
    v_3,
  ) quad quad
  accent(bold(v),hat) = &vec(
    0,
    accent(v,hat)_1,
    accent(v,hat)_2,
    accent(v,hat)_3,
  )
$
In this example we have used the complex conjuate and the quaternion multiplication operations.
=== Quaternion conjugate
For a unit quaternion the inverse is equal to the conjugate $bold(q)^(-1) = accent(bold(q),-)$
$
  accent(bold(q),-) = &vec(
    a,
    -b,
    -c,
    -d,
  )
$

=== Quaterinion multiplication
$
  bold(q)_1 bold(q)_2 = &vec(
    a_1 a_2 - b_1 b_2 - c_1 c_2 - d_1 d_2,
    a_1 b_2 + b_1 a_2 + c_1 d_2 - d_1 c_2,
    a_1 c_2 - b_1 d_2 + c_1 a_2 + d_1 b_2,
    a_1 d_2 + b_1 c_2 - c_1 b_2 + d_1 a_2,
  )
$
This operation is in general not commutative. so the order of the
quaternions matter $bold(q)_1bold(q)_2 eq.not bold(q)_2bold(q)_1$. But it is associative meaning that $(bold(q)_1 bold(q)_2) bold(q)_3 = bold(q)_1 (bold(q)_2 bold(q)_3)$.

=== Quaterinion normalization
The magnitude of a quaternion is defined as
$
  abs(abs(bold(q))) = sqrt(bold(q)accent(bold(q),-)) = sqrt(accent(bold(q),-)bold(q)) = sqrt(a^2 + b^2 + c^2 + d^2)
$
we want to _normalize_ the quaternion so that it has a magnitude of $1$, and consequently
$
  bold(q)accent(bold(q),-) = abs(abs(bold(q)))^2 = 1
$
we can normalize the quaternion by dividing it by its magnitude
$
  bold(q)_u = bold(q) / abs(abs(bold(q)))
$

=== Quaterinion kinematics
The derivative of a quaternion is defined as
$
  accent(bold(q),dot) = 1/2 bold(q) bold(omega)
$
where $bold(omega)$ is the angular velocity of our system. By using a gyro sensor, we can
obtain $omega = &vec(0, omega_x, omega_y, omega_z)$
With this equation, we can
integrate the angular velocity to get the orientation of the rocket.
$
  bold(q)_(t+1) = bold(q)_t + 1/2 bold(q) bold(omega) dif t
$

== Velocity and altitude

The velocity of the rocket is represented as a 3D vector
$
  bold(v) = &vec(
    v_x,
    v_y,
    v_z,
  )
$
the velocity is obtained by integrating the acceleration of the rocket.
However, we want the velocity in respect to the world frame, and thus we 
cannot directly integrate each component of the acceleration in a decoupled manner.
What if the rocket is tilted say along the x-axis? In this case, the acceleration along the z-axis
will also have a component along the x-axis in the world frame. The rocket frame is rotated with respect to the world frame.
To combat this, we must find a mapping or a translation if you will, between the rocket frame and the world frame.
Lucky for us, we have the quaternion that can be used to rotate the acceleration vector to the world frame.
So the velocity is obtained by integrating the acceleration in the world frame.
$
  bold(v)_(t+1) = bold(v)_t + bold(q) bold(a) accent(bold(q),-) dif t
$
Finally, the altitude is a scalar donoting the height of the rocket above the sea level in meters.
We can simply integrate the velocity along the z-axis to get the altitude.
$
  z_(t+1) = z_t + v_z dif t
$

== Dynamics

As we have seen, the dynamics is governed by the following equations
$
  bold(f(x,u)) =  &vec(
    bold(q)_(t+1) = bold(q)_t + 1/2 bold(q) bold(omega) dif t,
    bold(v)_(t+1) = bold(v)_t + bold(q) bold(a) accent(bold(q),-) dif t,
    z_(t+1) = z_t + v_z dif t
  )
$
we can think of the input $bold(u)$ as beeing our $bold(omega)$ and $bold(a)$ from the sensors.

=== Orientation dynamics

Lets first consider the orientation part. This equation is in fact
a linear equation in the state variable $bold(q)$, However,
We want to express the equation in a matrix-vector multiplication form
$
  bold(q)_(t+1) = bold(F_q) bold(q)_t
$
Where $bold(F_q)$ is a matrix. We can achive this 
by expanding our quaternion kinematics equation to get
$
vec( q_1,q_2,q_3,q_4 )
+
vec(
    q_1 omega_0 - q_2 omega_x - q_3 omega_y - q_4 omega_z,
    q_1 omega_x + q_2 omega_0 + q_3 omega_z - q_4 omega_y,
    q_1 omega_y - q_2 omega_z + q_3 omega_0 + q_4 omega_x,
    q_1 omega_z + q_2 omega_y - q_3 omega_x + q_4 omega_0,
  )
  1/2 dif t
$
and we can see that this can be expressed as a matrix-vector multiplication $bold(F_q) bold(q)$
where the matrix $bold(F_q)$ is
$
  bold(F_q) = mat(
    1,-1/2omega_x dif t,-1/2 omega_y dif t,-1/2 omega_z dif t;
    1/2omega_x dif t, 1,1/2 omega_z dif t,-1/2 omega_y dif t;
    1/2omega_y dif t,-1/2 omega_z dif t,1, 1/2 omega_x dif t;
    1/2omega_z dif t,1/2 omega_y dif t,-1/2 omega_x dif t, 1;
  )
$
=== Velocity dynamics
As with the orientaion dynamics we want to express the equations by a matrix-vector product.
However the velocity dynamics is not linear since the quaternion components are coupled in a non-linear way.
We get expressions like $q_1^2$ and $q_1 q_2$ which are non-linear. In order to 
get the matrix we want we can linearize, by taking the first derivative of our
velocity equation we get the jacobian matrix 
$
  bold(F)_(v q) = mat(
    2(q_1a_x+q_3a_z-q_4a_y)dif t,2(q_2a_x+q_3a_y+q_4a_z)dif t,2(q_1a_z-q_3a_x+q_2a_y)dif t,2(q_4a_x-q_1a_y+q_2a_z)dif t;
    2(q_1a_y+q_4a_x-q_2a_z)dif t,2(q_3a_x-q_2a_y-q_1a_z)dif t,2(q_3a_y+q_2a_x+q_4a_z)dif t,2(q_3a_z-q_4a_y+q_1a_x)dif t;
    2(q_1a_z+q_2a_y-q_3a_x)dif t,2(q_4a_x-q_2a_z+q_1a_y)dif t,2(q_4a_y-q_3a_z-q_1a_x)dif t,2(q_4a_z+q_2a_x+q_3a_y)dif t;
  )
$
$
bold(F)_(v v) = mat(1,0,0;0,1,0;0,0,1)
$

=== Position dynamics
This one is simple, to express the position dynamics in a matrix-vector multiplication form
we can simply write
$
  bold(F)_a = mat( 0, 0,0,0,0,0, dif t, 1 ) \
  z_(t+1) = bold(F)_a vec( dots.v , v_z, z_t )
$
Putting it all together we get the dynamics matrix $bold(F)$
$
    &(diff bold(f)) / (diff bold(x)) = bold(F) = mat(
    bold(F)_q,bold(0), bold(0);
    bold(F)_(v q), bold(F)_(v v), bold(0);
    dots.h.c, bold(F)_a, dots.h.c
    )
$

== Measurement models

Systems have different degrees of observability. Some states are observable
from the sensors, while others are not. The orientation of the rocket can be measured
by sensors such as magnetometers, sun trackers and star trackers.
The altitude can be directly measured by barometers, and both altitude and 
velocity can be measured by GPS. Though GPS is not used in this system.
With the sensors we have, we still need a way to translate between the sensor readings and our state model.
That is what measurement models are for. They describe how the state of the system is related to the sensor readings.


=== Orientation measurement

To measure the orientation of the rocket, we use a magnetometer. The magnetometer measures the
magnetic field of the earth. The magnetic field of the earth is known and is going nowhere (anytime soon), so it
can be used as a reference. We need a reading of the magnetic field when the rocket is stationary, and the orientation 
is in it's initial state.
$
"reference" := bold(psi)_0
$
The translation that relates the magnetic field to the orientation of the rocket is
$
  accent(bold(psi),hat) = bold(q) bold(psi)_0 accent(bold(q),-)
$
In other terms, the system thinks the output of the magnetometer will be $accent(bold(psi),hat)$.\
Anytime we want to measure the orientation of the rocket, we take a reading of the magnetic field $bold(psi)$ and compare it to 
the prediction.
$
  accent(bold(psi),hat) = bold(q) bold(psi)_0 accent(bold(q),-)\
  epsilon = bold(psi) - accent(bold(psi),hat)
$
The error $epsilon$ is the difference between the measured orientation and the predicted orientation.
The error is then used to correct the orientation of the rocket. We will see how this is done in the Kalman filter section.

Similar to the jacobian for the velocity dynamics, we can linearize the orientation measurement model to get the jacobian matrix
$
  bold(H)_q = mat(
    2(q_1psi_x+q_3psi_z-q_4psi_y),2(q_2psi_x+q_3psi_y+q_4psi_z),2(q_1psi_z-q_3psi_x+q_2psi_y),2(q_4psi_x-q_1psi_y+q_2psi_z);
    2(q_1psi_y+q_4psi_x-q_2psi_z),2(q_3psi_x-q_2psi_y-q_1psi_z),2(q_3psi_y+q_2psi_x+q_4psi_z),2(q_3psi_z-q_4psi_y+q_1psi_x);
    2(q_1psi_z+q_2psi_y-q_3psi_x),2(q_4psi_x-q_2psi_z+q_1psi_y),2(q_4psi_y-q_3psi_z-q_1psi_x),2(q_4psi_z+q_2psi_x+q_3psi_y);
  )
$
=== Altitude measurement

The altitude can be measured by a barometer. The barometer measures the pressure of the air.
The pressure of the air decreases with altitude.
$
  h = h_0 + l_0 (p_0 / p)^(g_0 m_0 / r_0 l_0)
$
As we lack a GPS, we cannot measure the velocity of the rocket directly. The only way to update the velocity
is via the dynamics of the system. This is a common problem in navigation systems and is called the
observability problem. The velocity is not observable from the sensors, and we must rely on the dynamics of the system
$
    (diff bold(h)) / (diff bold(x)) = bold(H)= mat(bold(H)_q, bold(0); bold(0), h)
$

== State estimation with Kalman filter

With the state-space representation of the system and the linearized dynamics,
we can use a Kalman filter to estimate the state of the rocket.
For pure linear systems, the Kalman filter is optimal and can be used to estimate the state
of the system given noisy measurements.
However, the system is not purely linear, so we must use an extended Kalman filter which
is not optimal but does a good job of estimating the state of the system nonetheless.
The extended Kalman filter is identical to the Kalman filter except for the linearization step.
The Kalman filter functions kinda like a feedback controller. It takes the measurements
and the estimated state and corrects the estimated state based on the error between the measurements.
Recall the system dynamics $(1)$
$
  &bold(x)_(t+1)= bold(F) bold(x)_t + bold(B) bold(u)_t + bold(w)_d\
  &accent(bold(y),hat)_(t) = bold(H) bold(x)_t + bold(D) bold(u)_t + bold(w)_n\
$
We can add the feedback loop to the system dynamics to get the Kalman filter
$
  accent(bold(x),hat)_(t+1) = bold(F) bold(x)_t + bold(B) bold(u)_t + bold(K) (bold(y) - accent(bold(y),hat)) 
$
where $bold(y)$ is the actual measurement and $accent(bold(y),hat)$ is the predicted measurement from our measurement model.
Below is a very barebones illustration of the Kalman filter


The choice of the gain $K$ is not arbitrary, it is chosen to minimize the cost function
$
  J = E[bold(x) - bold(x)_hat]^T Q E[bold(x) - bold(x)_hat] + E[bold(y) - bold(y)_hat]^T R E[bold(y) - bold(y)_hat]
$
Recall the state-space representation of the system equation $(1)$
where we have system disturbances $bold(w)_d$ and measurement noise $bold(w)_n$.
Now a very important assumption that the Kalman filter bases its optimality on is that the noise is Gaussian.

which is the expected value of the error between the true state and the estimated state.
This i a quadratic cost function that is minimized by the Kalman filter.
By solving the Riccati equation, we can find the optimal Kalman gain $bold(K)$




= Hardware

The PCB is designed in KiCad and is a 4-layer board. The board is powered by a 3.3V LDO regulator.
In general, the PCB design is centered around the ARM Cortex M4 microcontroller and the sensors.
The sensors are connected to the microcontroller via a shared SPI bus, so the microcontroller
has to select the sensor it wants to communicate with by setting the chip select pin of the sensor.
The only exception is the
magnetometer which is connected via I2C directly to the ISM330DHCX which have an I2C bus and
DSP functionality. Most ICs have a decoupling capacitors as recommended by the manufacturer.

== ARM Cortex M4

The ARM Cortex M4 is a 32-bit microcontroller that is used to run the navigation system.
The processing power of the microcontroller is sufficient to run the navigation algorithms
and communicate with the sensors. The peripherals used by the microcontroller are the SPI, USART,
Timer, and SD card.
It also provides a interuppt vector table that we use for the state machine.
The sensor drivers is only a matter of reading and writing to the registers of the sensors with
SPI

== ISM330DHCX

[visualisation testing]

== Barometer

[Pressure testing]

== Magnetometer

[magnetometer calibration testing]

= Firmware

The codebase uses the harmony framework to interface with the peripherals of the microcontroller.
Harmony is a code generator that generates code based on the configuration of the peripherals.
It provides a high-level API to interface with the peripherals of the microcontroller.

The main loop of the firmware is a state machine that runs the navigation algorithms.
The state machine is implemented as a switch-case statement that switches between the different states of the system.
Some states are triggered by interrupts from the sensors, while others are triggered by a timer.
The state machine is responsible for reading the sensor data, running the navigation algorithms, 
and sending the data to the ground station.

== API

The API of the firmware is quite limited. The firmware is designed to be a standalone system that
runs the navigation algorithms and communicates with the sensors. The only way to interact with the firmware
is through the SERCOM USART interface. The firmware sends the data to the ground station in a binary format.
The data is sent in packets that contain the sensor data and the estimated state of the rocket.


// #include "statemachine.typ"

== Testing

The most useful tests are the SERCOM inteface in debug mode. By connecting the system to a computer
we can print useful information about the state of the system. The tests are run in the lab and in the field.
The project also comes with visualizations of the data that can be used to analyze the performance of the system.
and unit tests that can be run independently of the microcontroller.
sensor specific tests are also run to ensure that the sensors are working as expected.


// #include "pressuredata.typ"

= Integration

This sevtion is about how the system is integrated into the rocket.
How the system is powered and how it communicates with the ground station and other systems.
We innitially used FRAM but switched to usart for simplicity and higher data rates as the FRAM was slow.
It is connected directly to the recovery system and the RF module. The physical position of the system is
together with the rest of the electronics, ideally in the center of mass of the rocket. Shielding is also
preffered to limit sensor noise and interference.

= Possible improvements

air speed sensor
gps
better magnetometer
maybe a sun/star/earth tracker

= What did we learn?

Compare the system that was before to the system we have now.
What was improved
What was not improved
What was actively worse

= Literature and resources


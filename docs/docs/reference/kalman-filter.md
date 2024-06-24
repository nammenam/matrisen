### Kalman Filter

The Kalman filter is a state estimator that makes an estimate of some unobserved variable based on noisy measurements.
It is a recursive filter that is based on the assumption that the state of the system can be described by a linear 
stochastic difference equation. The Kalman filter is a powerful tool for combining information in the presence of uncertainty.
It is used in a wide range of applications including target tracking, guidance and navigation systems, radar data processing, and satellite orbit determination.

For our case we need to estimate the position of the rocket, based on the measurements from the IMU, pressure sensor and magnetometer.
In the case of system shutdown, we need to be able to estimate the position of the rocket, based on the last known position and the
last known velocity. This is where the Kalman filter comes in. It is a recursive filter, meaning that it can estimate the state of the system
based on the previous state and the current measurement.
The previous state is stored in an SD-card


in literature, the following notation is used:

Measurement Function (h()): This function maps the predicted state into the measurement space. It takes the predicted state estimate and converts 
it into a form that can be directly compared with the actual sensor measurement. 
Innovation: This is the difference between the actual sensor measurement and the predicted measurement 
(obtained from the measurement function h()). The innovation represents the discrepancy between what the 
system expected to measure, given its state estimate, and what it actually measured.


State Transition Function (f()): This function predicts the next state of the system based on the 
current state and control inputs, if any. It's the core of the prediction step in the EKF, 
where the current state estimate is propagated forward in time to predict the next state.    


The state transition function (f()) uses data from accelerometers and gyroscopes to predict 
the next state of the system in terms of position, velocity, and orientation.
The measurement function (h()) takes the predicted state and converts it into a form that can be
directly compared with the actual sensor measurements from the barometer and magnetometer.
The discrepancies (innovations) between these measurements and predictions are then used to update 
and refine the state estimate.


The prediction is 
S = H @ P_t @ H.T + R
K = P_t @ H @ np.linalg.inv(S)      # Kalman Gain
y = z - h(x_t)                      # Innovation
x_t = x_t + K @ y                   # Updated state estimate
P_t = (I - K @ H) @ P_t             # Updated covariance estimate

where:
S = Innovation covariance
H = Jacobian of the measurement function
F = Jacobian of the state transition function
P_t = Covariance matrix
R = Measurement noise covariance matrix
K = Kalman gain
y = Innovation
z = Measurement
h(x_t) = Predicted measurement
x_t = State estimate


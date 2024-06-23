# State Machine

> 🛈  the state machine is implemented in `app.cpp`

The state machine is the core of the COMPASS system. It is responsible for managing the different states 
of the rocket and for switching between them. The state machine is implemented as a finite state machine. 
The state machine has 4 states: `IDLE`, `LAUNCHPAD`, `FLIGHT` and `RECOVERY`. The state machine starts in 
the `IDLE` state. The state machine switches to the `LAUNCHPAD` state when the rocket is launched. 
The state machine switches to the `FLIGHT` state when the rocket reaches apogee. The state machine 
switches to the `RECOVERY` state when the rocket lands. The state machine switches back to the `IDLE` state when the rocket is recovered.

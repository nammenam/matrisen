***COMPASS***

is KON-TIKI's navigation system. Lorem ipsum dolor sit amet,
consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore
et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum
dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim
veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea
commodo consequat. Duis aute irure dolor in reprehenderit in voluptate
velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint
occaecat cupidatat non proident, sunt in culpa qui officia deserunt
mollit anim id est laborum. Lorem ipsum dolor sit amet, consectetur
adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore
magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco
laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor
in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa
qui

*Dynamics and state modeling*

The general form of a dynamical system can be stated as

$$
\begin{aligned}
 & \overset{\cdot}{\mathbf{x}} = \mathbf{f}(\mathbf{x},\mathbf{u}) + \mathbf{w}_{d} \\
 & \hat{\mathbf{y}} = \mathbf{h(x,u)} + \mathbf{w}_{n}
\end{aligned}
$$ 

for linear systems we can use linear algebra to express
our system 

$$
\begin{aligned}
 & \overset{\cdot}{\mathbf{x}} = \mathbf{Fx + Bu} + \mathbf{w}_{d} \\
 & \hat{\mathbf{y}} = \mathbf{Hx + Du + w}_{n}
\end{aligned}
$$ 

we can also descreteize our system (which is what we
must do in order to use our computer algorithms) 

$$
\begin{aligned}
 & \mathbf{x}_{t + 1} = \mathbf{f}_{d}\left( \mathbf{x}_{t},\mathbf{u}_{t} \right) + \mathbf{w}_{d} \\
 & {\hat{\mathbf{y}}}_{t + 1} = \mathbf{h}_{d}\left( \mathbf{x}_{t},\mathbf{u}_{t} \right) + \mathbf{w}_{n} \\
 \\
 & \text{in the linear case} \\
 & \mathbf{x}_{t + 1} = \mathbf{F}_{d}\mathbf{x}_{t} + \mathbf{B}_{d}\mathbf{u}_{t} + \mathbf{w}_{d} \\
 & {\hat{\mathbf{y}}}_{t + 1} = \mathbf{H}_{d}\mathbf{x}_{t} + \mathbf{D}_{d}\mathbf{u}_{t} + \mathbf{w}_{n}
\end{aligned}
$$ 

in our case the vector $\mathbf{u}$ is $0$ since we have no controll over the rocket as far as the navigation system is
concerned. The state vector and the state transition and measurement
functions is 

$$
\begin{aligned}
\mathbf{x} = & \begin{pmatrix}
\text{ orientation } \in {\mathbb{R}}^{4} \\
\text{ velocity } \in {\mathbb{R}}^{3} \\
\text{ altitude } \in {\mathbb{R}}
\end{pmatrix} \\
\mathbf{f(x,u)} = & \begin{pmatrix}
\int\frac{1}{2}\mathbf{q}\mathbf{\omega}dt \\
\int\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt \\
\int v_{z}dt
\end{pmatrix} \\
\mathbf{h(x)} = & \begin{pmatrix}
\mathbf{q}\mathbf{\psi}\overset{-}{\mathbf{q}} \\
0\text{ (no observability)} \\
p_{0}\left( \frac{t_{0}}{t_{0} + l_{0}\left( x_{\text{alt}} - h_{0} \right)} \right)^{g_{0}\frac{m_{0}}{r_{0}}l_{0}}
\end{pmatrix}
\end{aligned}
$$ 

the linearized system is the jacobian matrices

$$
\begin{array}{r}
\frac{\begin{aligned}
 & \left( \partial\mathbf{f} \right)
\end{aligned}}{\partial\mathbf{x}} = \mathbf{F} = \begin{pmatrix}
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & \mathbf{q}\overset{-}{\mathbf{q}} \\
\int\frac{\partial}{\partial q_{1}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{2}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{3}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{4}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & 0 & 0 & 0 & \mathbf{q}\overset{-}{\mathbf{q}} \\
\int\frac{\partial}{\partial q_{1}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{2}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{3}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & \int\frac{\partial}{\partial q_{4}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & 0 & 0 & 0 & \mathbf{q}\overset{-}{\mathbf{q}} \\
\int\frac{\partial}{\partial q_{1}}\mathbf{q}\mathbf{a}\overset{-}{\mathbf{q}}dt & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & dt & 0
\end{pmatrix} \\
\frac{\begin{aligned}
 & \left( \partial\mathbf{h} \right)
\end{aligned}}{\partial\mathbf{x}} = \mathbf{H} = \begin{pmatrix}
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0 \\
0 & 0 & 0 & 0 & 0 & 0 & 0 & 0
\end{pmatrix}
\end{array}
$$

*Quaternion*

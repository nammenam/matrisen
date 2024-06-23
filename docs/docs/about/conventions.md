# Coding Conventions for Our Project

## Table of Contents

- [Variables](#variables)
- [Loops](#loops)
- [If Statements](#if-statements)
- [Methods, Functions and Returns](#methods-functions-and-returns)

---

### Variables

Variable conventions are quite easy to adhere to, but can make a massive difference in how
how simple it is to understand code.

This is how we declare and use variables:

```cpp
//Normal variable in "normal" scope are camelCase
int thisIsLocalScope;

//It is very useful to separate between local scope variables and 
//member variables, and therefore we write member variables like this, 
//to easily point them out in a sea of calulations
float m_memberVariable;

//This is a constant
float PI = 3.14;

```

We also highly value descriptive variable names. In Portal Space, the "lifespan" of a member is shorther than
a normal company, as we move on after our studies. Therefore we must keep in mind that someone will take over our
codebase in relatively short time.

If that is not motivation enough for you, try to recall a time you looked back at your own code a month later, and all
meaning is lost. Too many times I have been annoyed over my own lazy variable naming conventions

Here are some examples:
```cpp
int num = list.length();
//We already know an integer is a number, what does the number represent? 
// Even though the declaration confirms it is the length of a list, 
//we do not  want to have to look at the declaration of the variable 
every time we interact with it. 

//We can also tell that the name of the list is lackluster. A list of what? ->
int numberOfEmployees= employees.length();


//A bool is often represented as a state of a process, and is used as a check 
//before proceeding with other code, make sure the name of the bool is clear
//in what it represents.

//Avoid prefixes, they make us think for too long
if (notDone)
{
  //When does this get called? 
  foo();
}

if (status)
{
  // What does 'true' status mean? Is it good or bad? Active or inactive?
  bar();
}

//A good example is this:

if (nav.isRunning())
{
  //Here we can clearly tell if we reach this point of the code when the CPU is running
  foo(); 
}

```

While we are on the topic of booleans, we have a convention of not using the explicit bool datatype, but rather an int. 
An integer is false if it equals 0, true if it is non-zero. Negative numbers are non-zero, and evaluated to true. This 
is for C++ and C specifically, and defer to documentation of other languages where you are not sure.

```cpp
bool isRunning; //Good name, bad datatype
int isRunning; //There we go!
```

---

### Loops 

Loops are quite essential in any codebase, there are not very many different ways to format it, but we 
prefer to keep the curly braces in line so we can clearly see the scope of the loop. This theme of the
curly braces are repeated throughout the codebase

```cpp
//Notice the spacing between the keywords 'for' and ';'
for (int i = 0; i < num; i++)
{
    //Code goes in here
}
```

---

### If-Statements 

Same as with loops, we like to keep the curly braces in line as to avoid scope confusion.

```cpp
//This
if (condition)
{
  foo();
}
else
{
  bar();
}

//Not this:
if (condition) {
  foo();
} else {
  bar();
}
```

A very important concept is to avoid indentation as much as possible. If you have several
layers of indentation, reconsider your code and try to exit out of loops early.

Suppose we have a function that checks if a user has access:
```cpp
void checkAccess(User user, Resource resource)
{
    if (user.isAuthenticated())
    {
        if (user.isActive())
        {
            if (user.hasRole(resource.requiredRole()))
            {
                if (!user.accessExpired(resource))
                {
                    // Grant access
                }
                else
                {
                    // Access expired
                }
            }
            else
            {
                // Role mismatch
            }
        }
        else
        {
            // User is not active
        }
    }
    else
    {
        // User is not authenticated
    }
}
```
As soon as we are a couple indentations too deep, we have way to many variables to keep track of, and 
the control flow is way more complex than it needs to be.


This is the code refactored, where we try to return early, and handle general cases early. This flattens the 
indentations, and makes the code easier to skim over and understand:
```cpp
void canAccess(User user, Resource resource)
{
    if (!user.isAuthenticated())
    {
        // User is not authenticated
        return;
    }

    if (!user.isActive())
    {
        // User is not active
        return;
    }

    if (!user.hasRole(resource.requiredRole()))
    {
        // Role mismatch
        return;
    }

    if (user.accessExpired(resource))
    {
        // Access expired
        return;
    }

    // Grant access
}
```
Immediately we can tell how much easier this is to read and understand in a few glances. It is also beneficial when
it comes to debugging, as the control flow is easier and we can tell which condition is not being met faster

---

### Methods, Functions and Returns
Methods and functions have pretty much the same conventions as conditions and loops. We try to keep the function/method
as flat as possible, with curly-braces in line and early returns to avoid complex control flow.

Additionally, we try to errorproof our code, or at the very last make it clear when we reach an error or not.

```cpp
int canAccess(User user, Resource resource)
{
    if (!user.isAuthenticated())
    {
        // User is not authenticated
        printf("User is not authenticated");
        return 0;
    }

    if (!user.isActive())
    {
        // User is not active
        printf("User is not active");
        return 0;
    }

    if (!user.hasRole(resource.requiredRole()))
    {
        // Role mismatch
        printf("User does not have required role");
        return 0;
    }

    if (user.accessExpired(resource))
    {
        // Access expired
        printf("User access has expired");
        return 0;
    }

    // Grant access
    return 1;
}
```

Above we had almost the exact same function as in the proper condition example, except we have added a few perks to make
it easier to work with.

- Returns a value that indicates if it has gone successfully
- Prints an error message so we can see what conditions fails first

The return 0 and return 1 are very useful, so we can call the function in a condition, and go from there. 

```cpp
if (!canAccess(arg1, arg2))
{
  //Means to handle the case of not accessing
}

//Continue code as expected when granted access...
```

Another alternative is to avoid explicitely printing the error message, and give the option instead. Imagine
<em>canAccess</em> is a method, and the class it is within has an <em>std::string m_CurrentErrorMessage</em>

Notice the correct naming convention of the method and the error message, that make them easy to work with.

We use the first condition as an example:
```cpp
if (!user.isAuthenticated())
    {
        // User is not authenticated
        setError("User is not authenticated");
        return 0;
    }
```

And then where we call the method, we can choose whether we print the error or not:

```cpp
if (!(client.canAccess(arg1, arg2)))
{
  printf("%s", client.getError.c_str());
  //Handle further
    
}

//Continue code as expected when granted access...
```

### Classes
There are many conventions that can be followed to make working with classes easier. This is
one of hundreds of ways to make classes easy to read and work with.

Below is a live class used in the current project, being the SDCard class, that handles pretty much everything
to do with the SDCard.

We use #pragma once over header guards, as they are less lines of code, looks prettier and is overall
less error prone.

In this case, we have a the class wrapped in a namespace, as to not mix common method names, like update
with other classes

We put public methods followed by public variables at the top. When inspecting a class that you are 
unfamiliar with, ordering the public methods and variables first immediately gives you the contents
of the class you can directly interact with

We have good reason for why some methods and variables are private and some public. The most obvious is 
to keep the class safe from outside interference. The other is the layer of abstraction. In this class we have
an event driven system. Because of the layout of the class, the callee of the class only needs to call the classes
constructor, and the update method at a certain interval. Those two methods take care of all the internal
usage of the class, and we dont need to call any other methods.

```cpp
#pragma once

#include <string>

namespace utils {

class SDCard {

  enum SDCARD_STATE {
    WAIT_SWITCH_PRESS = 0, // Waits for a switch to be pressed to activate SD_Card
    OPEN_FILE,
    WRITE_TO_FILE,
    CLOSE_FILE,
    IDLE,
    ERROR
  };

public:
  // Methods
  SDCard();
  int update();
  std::string getError() { return m_CurrentErrorString; }

public:
  // Variables

private:
  // Methods
  int init(); // Initializes SD_Card

  // Methods to be called upon certain states
  int waitSwitchPress();
  int mountDisk();
  int openFile();
  int writeToFile();
  int continueLog();
  int closeFile();
  int setIdle();
  int setError(std::string errorMessage);

  int logComplete() { return m_LogComplete; }

private:
  // Variables
  SDCARD_STATE m_CurrentState;
  std::string m_CurrentErrorString = "";

  int m_LogComplete;
};

} // namespace utils
```





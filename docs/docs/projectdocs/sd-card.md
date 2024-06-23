# SD-Card

The SD-Card module is intended to assist in writing data to the SD-Card on the physical Navigation Module circuit. The abstraction layer is one layer above the generated files of MPLAB X IDE MCC, and is boiled down to quite few functions to keep it light and simple to interact with. 

## Interface

As mentioned, interfacing with the SD-Card is quite simple. We will start by clarifying how we initially mount the SD-Card, which was a major roadblock from us when we started integrating the SD-Card procedures. In short, don't do it manually. MPLAB has the advantage of being able to automatically mount it for us, which we do in the early stages of SYS_Tasks(). We have theorised that MPLAB mounting for us, and us trying to do it manually may have been the reason we weren't able to do it, but this is speculation and beyond our scope to figure out right now. 

This is the section where we mount the SD-Card in app.cpp: 

```CPP
if (strcmp((const char *) eventData, SDCARD_MOUNT_NAME) == 0) 
            {
                appData.sdCardMountFlag = true;
            }
            break;

            /* If the event is unmount then check if SDCARD media has been unmount */
        case SYS_FS_EVENT_UNMOUNT:
            if (strcmp((const char *) eventData, SDCARD_MOUNT_NAME) == 0) 
            {
                appData.sdCardMountFlag = false;
            }
```

This a simple check on wether it is mounted or not within our state machine. If we cannot mount we go into our error state, if we do mount successfully we can set the mounted flag to high and proceed. 

The next step for us is to open the file we want to write to. In our machine, we only have one file that we want to write to at the moment, so we also do this in the initialization stage of our program. We can write and flush without opening or closing the file again, so this action does not need to be repeated. If we needed to write to several files, we would need to be careful with closing and opening the file, as well as if we want to overwrite, start from EOF and so on and so on. Luckily we dont need this. 

The following is our code for opening our file. We have our fileHandle stored in a struct in our app.cpp header file which is a member instance of app.cpp. 

As you can see the app also double checks if we are mounted at this stage. 
```CPP
       case APP_INIT:
        {

            if (appData.sdCardMountFlag == true) 
            {
                if (SYS_FS_CurrentDriveSet(SDCARD_MOUNT_NAME) == SYS_FS_RES_FAILURE) 
                {
                    appData.state = APP_ERROR;
                    break;
                } 
                if (sdFileOpen(&appData.fileHandle, SDCARD_FILE_NAME, 0,1) == -1) 
                {
                    appData.state = APP_ERROR;
                    break;
                }
                MCU_LED_Set();
                appData.state = APP_MONITOR;

            }
            else if (appData.sdCardMountFlag == false) { /* try again TODO: Add a timeout to this */ }
            break;
        }
```

This is where the juicy part comes in, where we can actually write to the file. Where and when we do this is voluntary, and we are yet to decide just how often we should write. In any case, we write to the file, and upon success, we immediately flush the file to save the data: 
```CPP
case APP_SAVE_STATE:
        {                
            //Writing the actual data to the file, one for KF data and one for "raw" data
            //TODO implement logic of when and what to write
            if (sdWrite(&appData.fileHandle, SDCARD_FILE_NAME, &appData.kf, sizeof(appData.kf)) == -1)
            {
                // TODO: Add error handling
                int error = SYS_FS_Error();
                char buf[9] = "       \r";
                sprintf(buf, "%d", error);
                Debug::uart_printf(buf, 9);
                appData.state = APP_ERROR;
                break;
            }
           
            if (sdFlush(&appData.fileHandle) == -1)
            {
                // TODO: Add error handling 
                appData.state = APP_ERROR;
                break;
            }

            appData.state = APP_MONITOR;
            break;
        }
```
Writing to the SD-Card is our own separate state within our machine, so we can easily adjust the paramaters for when we would like to write to the file. Please note that the data will not be SAVED if you do not flush the drive. We also learned that lesson the hard way :)

The last major thing is to be able to read from the file

[To be continued]

## Implementation

## Data

# App Helper
> This app is not sandboxed. As it can terminated other apps.

![lion-w256](assets/lion.png)


## How to Use
1. Add the app you want to be controlled.
2. Click "Run in Background".

That's all. 

App Helper watches when SystemPreferences.app quits. Then after two seconds, App Helper checks if AppIDSettings is still opened, if true, App Helper terminates the controlled apps and relaunches them. That will clear the settings apps that SystemPreferences.app leaves.

## Images
<a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by justicon - Flaticon</a>
<a href="https://www.flaticon.com/free-icons/lion" title="lion icons">Lion icons created by Freepik - Flaticon</a>
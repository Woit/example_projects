# example_projects

This repo contains two example projects which is described in [this file](/tasks_description.md)

## Prerequisites
It assumes that reviewers have installed 'wget' utility on their Mac OS. It can be checked and installed using this commands
```bash
which wget

# and if it not installed:
brew install wget
```

Also im using (and highly recommend) utility [xcodegen](https://github.com/yonaskolb/XcodeGen) for generating Xcode project file
It also can be installed via homebrew:
```bash
brew install xcodegen
```

## Task 2: Polis local server
For build and check this command-line app you need navigate to folder `/AstroSearch` and run command
```bash
./.build/debug/astro-search help
# or
./.build/debug/astro-search help start
```
Service can also be run from Xcode, but first it required to run xcodegen. Just jump to `/AstroSearch` folder and run 'xcodegen' in console. Then you can open .xcodeproj file in Xcode

Some api path examples (assuming that server is started with default parameters):
```
http://localhost:8080/api/updateDate
http://localhost:8080/api/numberOfObservingFacilities
http://localhost:8080/api/search?name=ei
http://localhost:8080/api/location?uuid=0ABECE98-B5A2-4F5A-ABA2-84799C0DBEF8
```
## Task 1: Monitoring service
_**The development of two services from first task is stopped, because I think that the description of the services A and B are confused. If it was assumed that the service B acts as a monitor service, then the calculation of the average response of the server-target A, as well as the maintenance of logs, is the responsibility of the service B, but not an A. Clarify it.**_

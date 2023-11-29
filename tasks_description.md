# Example Project Suggestions

In the case where a potential candidate for a position of a Server Side Swift developer does not have an opportunity to present to our team a project of sufficient size and complexity that demonstrates her experience of solving complex problems (preferably hosted on `GitHub`) we are giving the candidate the opportunity to demonstrate his knowledge by implementing one of the following possible tasks:

- One service monitors and analyses the performance of another service.
- Implementation of a service that uses open source astronomical observatory data to implement a set of well defined queries.


## General requirements for all example tasks

1. The solution of the example project should be hosted in a public `GitHub` repository. After completion of every meaningful step, the candidate should commit the current status of the project. This will help our team to evaluate the design decisions, as well as the ability to refactor and correct architectural mistakes.

2. The project should be developed as a Swift Package (or set of Swift packages) using Xcode v.15.

3. The project should be implemented as a `macOS` Command-Line Tool, using Apple's Swift Argument Parser, and logging should be implemented with any logging framework that conforms to Apple's Logging protocol. As a minimum the tool should accept the `-h` or `--help` command-line arguments, and if needed, also arguments to configure the input / output directories, paths to configuration files, URLs to external resources etc. All these values should not be hardcoded.

4. Services should be based on Apple's `SwiftNIO` framework using `HTTP` handlers.

5. The project should follow Apple's Swift Coding Guidelines.

6. For all non-trivial methods we expect Unit Tests.

7. The code should be documented using the `DocC` format, and Xcode should be able to build documentation that could be displayed in the Documentation Window of Xcode. A `DocC` compliant tutorial will be appreciated. 

8. Source code as well as documentation should be in English, although variable / constant names like `π` could be used if this contributes to the overall clarity.

9. Instructions (in a `Readme.md`) file describing how to run and test the projects are expected.

10. In case of questions do not hesitate to drop us an [email](mailto:hr@tuparev.com)


## Project 1: Monitoring & Analysing Service performance

This task requires the implementation of two independent services (`A` and `B`) that must run in parallel from Xcode (or from the terminal).

### Service `A`: 
Implements a single API (something like http://localhost:2345/ping). The response could be a simple string like `OK`, but the response time should be random (in the range of 20ms - 5s).

### Service `B`:
This service should repeatedly access service `A`'s single entry point, after waiting for a configurable delay. Service `A` should track the response time of `B` in such a way, that for the last `N` requests it can calculate the minimum, maximum and average response time. THe value `N` should be configurable at launch of service `A`. Every 5 minutes the service should produce and store in the file system a `JSON` file containing the current three statistical values (min, max, avrg). The files should be stored in a folder with the following hierarchy: `../<day>/<hour>/<iso8601-timestamp.json`. After 2 days the data for the oldest day should be automatically deleted.

In addition, the service should implement a single API entry point (e.g. http://localhost:3456/stats) that will return (in `JSON` format) the up-time of the service, and the average response time as well as min/max times for the entire life-time of the service.


## Project 2: Searching for Astronomical Observatories 

Our team is working on a new open source standard and database describing astronomical observatories (called `POLIS`). For our own purpose we are developing a simple Swift-based framework to access the data. This still is work in progress, but a simple version can be found on [GitHub](https://github.com/ASTRO-POLIS/swift-polis.git) (checkout the `dev` branch). Some [test data](https://test.polis.observer) are already on one of our servers.

Tasks:
- Create a service using the `swift-polis` framework that connects to the server hosting the test data and copy all data files to the local machine that are needed to provide the APIs describes below. This should be done in an `async` way, so that while copying, the service is still responsive.

- Implement the following simple APIs (e.g. `http://localhost:4321/api`)
	- `updateDate` - returns the last update date of the data set
	- `numberOfObservingFacilities` - returns the number of facilities in the current data set
	- `search?name=xxx` - returns the UUIDs of all facilities with a name containing the search criteria.
	- `location?uuid=UUID` - returns the longitude and latitude (as Double values) of a facility with a given UUID.






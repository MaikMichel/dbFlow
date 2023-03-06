# Changelog


## [Unreleased]

## [1.0.0 - 2022-09-13]
- Add Obfuscate passwords in apply.env
- Tuned logging peformance
- Add copyto command to setup.sg to generate an instance directory
- Add parameter -e to generate command, to generate env files olnly
- Remove export feature. This is now part of dbFlux
- Remove ansi2html because on Mac it's not working out of the box
- Some small improvements

## [0.10.0 - 2022-08-22]
- Add TEAMS_WEBHOOK_URL to post to on success
- Fixed some small bugs
- Add option -a / --apply to direct run apply after build
- Add option to redo a certain patch with the old logfile as starting point
- Add option to generate and process changelog


## [0.9.0 - 2022-01-17]
> Breaking Changes
- `build.sh` and `apply.sh` must be called with **named** arguments / options. No more use of positional arguments!
- `build.sh`  supports flag `-k` to keep folder inside depot
- `build.sh`  supports flag `-a` to ship all files and folders whether they are touched or not, but only touched files will be installed
- some small bugs are now fixed as well
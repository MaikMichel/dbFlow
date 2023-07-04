# Changelog

## [2.2.0 - 2023-07-01]
- New: Install APEX Apps to ID of folder, not to original

## [2.1.0 - 2023-06-11]
- New: Schema-Hooks with suffic ".table.sql" are now called for each touched table
- Some fixes

## [2.0.0 - 2023-05-23]
- Fix: some vars to reference as quoted content
- Fix: reading user input with -r option
- Fix: Interpretation when nothing to greo in redolog
- Fix: Changelog with start/end options, rather then with tags found
- Refactored: writing build.env and apply.env
- Refactored: path array to lib.sh
- Refactored: color codes
- Refactored: export schema functionality removed > this is part of dbFlux
- Refactored: parameter parsing should now be consistant in all scripts
- New: Add gentest.sh to put insert scripts in folders to validate execution
- New: create_00_workspace.sql will now remove it before creating
- New: Parameters passed to scripts are now alway options,
       no commands or arguments without options.
       **This will break your existing scripts!**
- New: Validate dbFlow version artifact was build to match version it is applied with
- New: Ask user to proceed on init mode when no DBFLOW_JENKINS var is set
- New: Seperate wizard from generation so project can be setup by environment vars

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
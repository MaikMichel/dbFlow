# Changelog

## [3.0.0 - 2024-06-30]
- New: When using release.sh you can set version to: major, minor or patch. dbFlow will calcualte the right version number for you
- New: During deployment, translated Applications are se offline too.
- New: Logs will be written to a new Environment var: LOG_PATH. From now on, the depot is not responsible for storing log data. So, when using LOG_PATH inside instance directories, logs should be written to ./${LOG_PATH}. And here (instance directory) it is ok to commit the files as well. This will keep a nice install log history.
- Fix: Setting Applications online occurs only to untouched Applications.
- New: When creating deployments and depot path is a git directory as well, the actual artefact is pushed to the remote too. So you can have a Jenkins or something like that listening to pushed on your depot repository.
- New: The version will be a tag in the target branch and will the tag will be moved to the master/main branch as well.
- New: The jobs folder will be executed after the dml folder and it's childs. So, you can consume data in the job files you have used in dml scripts before.
- New: The version of bash is written to the output.
- New: When a table file is marked as new in the target branch by git, it is executed allthough there could be table_ddl files, which alters the same table. This is new and in important change. So when releasing often to a test or uat branch and later just to a master/main branch, then new tables will be created by running just the create-table-script. Not the 10 changes which were created and deployed during the last sprints. See documentation for more infos.
- New: You have an option to use the old behavior (--forceddl)
- New: Now object-hooks will always be executed. Weather there were objects in the specific file or not.
- New: Environment Var: `REMIND_ME` When this var is set, it will be prompted, when building a deployment, just for you to remind you on something specific.
- Fix: Many small improvements


## [2.6.0 - 2024-02-15]
New: Input new  version for tagging when on main or master and no pipeline is running
New: Changes to depot are always pushed, when not in Pipeline
New: Enablement occurs explizit only on untouched applictaions
New: All Logs and Artifacts are written to log_path. No changes on apply to depot
New: Support translated Apps during deployment
New: validate tag existence and calculate next version by version label
Fix: echo out instead of printf when writing changelog

## [2.5.0 - 2024-01-23]
- New: During patch, scan explicitly for a subfolder
       inside `tables/tables_ddl` with the name of the target-branch
       This is when fixing a create table script in a release
       which was not released on production yet

## [2.4.0 - 2023-11-17]
- New: Add flag -a/--apply to build.sh
- New: Old flag -a/--shipall is renamed to -t/--transferall
- Fix: Missing privileges on sh files after copyto target
- Fix: Logpath is added to .gitignore
- Some fixes

## [2.3.0 - 2023-08-18]
- New: Create readme.md when generating project
- New: apply.sh can now run a stepwise installation using flag --stepwise
- New: setup.sh --apply will only generate apply.env file
- New: added new env var LOG_PATH which defines an additional path to write the logs to
- New: packages or types are grouped by Specifications, Bodies, SQL-Files
- Fix: Synonyms will be dropped in init mode as well

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
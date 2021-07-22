# dbFlow
Deployment framework for Oracle Database Applications


## Features you get

- create an Oracle Database / APEX Project per command line
- install dependent features (Logger, utPLSQL, ...)
- use a deployment flow, which automaticaly build and apply patches based on Git diffs
- configure your project dependencies

###  If you are using VSCode you should install > [dbFlow-vsce VSCode extension](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow)
With that in place you get the ability to:
- compile SQL or PLSQL based on folder structure
- execute tests based on folder structure
- minify and upload JavaScript to your APEX Application
- minify and upload CSS to your Application
- Export APEX Applications
- Export REST Modules
- Create and Upload binary files for reporting (AOP)


## Quick Preferred way of installation


> ![ScreenCast](doc/screen-rec-generate-project.gif)


1. create a git repositoy
2. add dbFlow as `.dbFlow` submodule to your project
3. run `.dbFlow/setup.sh generate <project_name>`
4. answer some question based on your requirements
5. after that just run `.dbFlow/setup.sh install`

### By executing the install command following objects are created

- On a multischema project 4 database users <project_name>_(depl, data, logic, app). Thereby the deployment (depl) user will be used as a proxy user
- On a singelschema project only one database user <project_name> is created
- when accepted some dependent features (Logger, utPLSQL, ...) are installed
- APEX Workspace is installed and a workspace admin name wsadmin (initial pwd is *wsadmin*)


## Prerequisites

First of all you need a database. If you set up the project from scratch, you will need the login data of an admin in between. If you use the APEX functionality, this database should have a current version of APEX installed.

- dbFlow is using bash. So on Windows make sure you are using Git-Bash
- dbFlow can be configured to use either SQLplus or SQLcl
- SQLcl is required to export APEX-Applications and ORDS-REST modules
- If you want to use schema-export you must have APEX installed, cause we are using apex_zip Package

## Todo

- [ ] Finalize documentation
- [ ] Create some tutorials
- [ ] Create son blogposts
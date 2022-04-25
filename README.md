![](https://img.shields.io/badge/Oracle_Database-19c-blue.svg)


# dbFlow
Deployment framework for Oracle Database Applications


## Features you get

- create an Oracle Database / APEX Project per command line
- install dependent features (Logger, utPLSQL, ...)
- use a fully customizable deployment flow based on Git diffs
- configure your project dependencies
- generate and process changelogs
- create nightlybuilds


## Works best with dbFLux [dbFlux](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow)
### With that in place you get the ability to
- compile SQL or PLSQL based on folder structure
- execute tests based on folder structure
- minify and upload JavaScript to your APEX Application
- minify and upload CSS to your Application
- Export APEX Applications
- Export REST Modules
- Create and Upload binary files for reporting (AOP)


## Quick Preferred way of installation

```bash
# create a folder for your project and change directory into
$ mkdir demo && cd demo

# init your project with git
$ git init

# clone dbFlow as submodule
$ git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow

# generate project structure
$ setup.sh generate <project_name>

# after processing the wizard steps, just install
$ setup.sh install

```

> ![ScreenCast](doc/screen-rec-generate-project.gif)


1. create a git repositoy
2. add dbFlow as `.dbFlow` submodule to your project
3. run `.dbFlow/setup.sh generate <project_name>`
4. answer some question based on your requirements
5. after that just run `.dbFlow/setup.sh install`

## Documentation
  [Just read the docs](https://maikmichel.github.io/dbFlow/)
## Frequently Asked Question

> Git creates wrong filenames and dbFlow can't copy / rsync them in a right manner

- This is a git problem and you can turn if of by using following option:
```bash
git config --global core.quotepath off
```

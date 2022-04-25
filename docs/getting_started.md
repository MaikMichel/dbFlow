# Getting startet

## Requirements

To use dbFlow, all you need is:

* [Git]
* [SQLPlus inkl. Oracle Client] or [SQLcl]
* bash
    - on Windows included as git-bash
    - on MacOS included as bash (old) or zsh (unstable)
    - on Linux it just should work

   [Git]: https://git-scm.com/downloads
   [SQLPlus inkl. Oracle Client]: https://www.oracle.com/database/technologies/instant-client/downloads.html
   [SQLcl]: https://www.oracle.com/de/tools/downloads/sqlcl-downloads.html


## Installation

Basically, installing dbFLow consists of nothing more than initializing a directory with git and then cloning the repository as a submodule from GitHub. If you are using an existing git directory / project, cloning the submodule is all you need to do.

> The cloning of dbFlow as a submodule has the advantage that you can source new features and bugfixes directly from Github. In addition, you always have the possibility to fall back on an older dbFLow version through branching.

!!! warning

    dbFlow **MUST** exist as a folder named ".dbFlow"

### Starting a new Project

```bash
# create a folder for your project and change directory into
$ mkdir demo && cd demo

# init your project with git
$ git init

# clone dbFlow as submodule
$ git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow

```


### Initialize an existing Project

```bash
# change into your project directory
$ cd demo

# clone dbFlow as submodule
$ git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow

```

> Sometimes it can happen that the bash files cannot be executed. If this is the case, explicit permissions must be granted here. (`chmod +x .dbFlow/*.sh`)


## Setting up a project

To configure a dbFlow project, set it up initially with the command `setup.sh generate <project_name>`. After that some informations about the project are expected. All entries are stored in the two files `build.env` and `apply.env`. `build.env` contains information about the project itself and `apply.env` contains information about the database connection and environment. The filename `apply.env` is stored in the file `.gitignore` and should not be versioned. Since this file contains environment related information, it is also exactly the one that changes per instance / environment. All settings in this file can be entered also from "outside", in order to fill these for example from a CI/CD Tool.

!!! info

    You can always execute a main shell script/command inside .dbFLow folder to show usage help.

### Generate Project

```bash
$ setup.sh generate <project_name>
```

| Question | Notes |
|----------|-------|
| Would you like to have a single, multi or flex scheme app (S/M/F) [M] | This is the first question. Here you define the project mode. Default is **M**ulti |
| When running release tests, what is your prefered branch name [build] | Later you have the possibility to run so called release tests (NightlyBuilds) . Here you determine the branch name for the tests. The default here is **build**. |
| Would you like to process changelogs during deployment [Y] | dbFlow offers the possibility to generate changlogs based on the commit messages. Here you activate this function. [changelog] |
| What is the schema name the changelog are processed with [schema_name] | WIf you want changelogs to be displayed within your application, you can specify the target schema here, with which the corresponding TemplateCode should be executed. [changelog] |
| Enter database connections [localhost:1521/xepdb1] | Place your connection string like: host:port/service |
| Enter username of admin user (admin, sys, ...) [sys] | This user is responsible for all scripts inside db/_setup folder |
| Enter password for sys [leave blank and you will be asked for] | Nothing more to clarify. Password is written to apply.env which is mentioned in .gitignore |
| Enter password for deployment_user (proxyuser: flex_depl) [leave blank and you will be asked for] | Nothing more to clarify. Password is written to apply.env which is mentioned in .gitignore |
| Enter path to depot [_depot] | This is a relative path which points to the depot (artifactory) and is also mentioned in .gitignore when it is not starting with ".." |
| Enter stage of this configuration mapped to branch (develop, test, master) [develop] | When importing the deployment, this setting assigns the database connection to the source branch |
| Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [Y] | Here you activate the initial installation of the different components/dependencies. These are placed in the db/_setup/features folder. There you can also place other features by yourself. If you don't need certain components, you can delete the corresponding file from the features folder (before running the actual installation)..
| Install with sql(cl) or sqlplus? [sqlplus] | Here you define which CLI dbFLow should use to execute the SQL scripts. |
| Enter application IDs (comma separated) you wish to use initialy (100,101,...) | Here you can already enter the application IDs that dbFlow should initially take care of |
| Enter restful Moduls (comma separated) you wish to use initialy (api,test,...) | Here you can already specify the REST modules that dbFlow should initially take care of |


  [changelog]: ../changelog/#configuration

After answering all the questions, your project structure is created with some SQL and bash files inside. You can now modifiy these files and / or put some files of your own into the corresponding folders.

### When you are ready, just install the project with dependencies into your database


```bash
$ setup.sh install
```
> This will run all SQL and bash files inside the db/_setup directory.
# Getting startet

## Requirements

To use **dbFlow**, all you need is:

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

Basically, installing **dbFLow** consists of nothing more than initializing a directory with git and then cloning the repository as a submodule from GitHub. If you are using an existing git directory / project, cloning the submodule is all you need to do.

> The cloning of **dbFlow** as a submodule has the advantage that you can source new features and bugfixes directly from Github. In addition, you always have the possibility to fall back on an older **dbFLow** version through branching.

!!! warning "Important!"

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

### Or with a One-Liner

```bash

# Without parameter current directory is used
curl -sS https://raw.githubusercontent.com/MaikMichel/dbFlow/master/install.sh | bash

# Add targetfolder as parameter
curl -sS https://raw.githubusercontent.com/MaikMichel/dbFlow/master/install.sh | bash -s <targetfolder>

```

### Clone an existing dbFlow project (multiple steps)
```bash

# create project folder and change into
mkdir your_project && cd your_project

# clone the repo itself
git clone https://path-to-your-db-flow-project-where-dbFlow-is-allready-installed.git .

# pull submodule(s) => .dbFlow
git submodule update --init --recursive

```

### Clone an existing dbFlow project (one steps)
```bash

# clone the repo recursive and change into it
git clone --recursive https://path-to-your-db-flow-project-where-dbFlow-is-allready-installed.git your_project && cd your_project

```

> Sometimes it can happen that the bash files cannot be executed. If this is the case, explicit permissions must be granted here. (`chmod +x .dbFlow/*.sh`)


## Setting up a project

To configure a **dbFlow** project, set it up initially with the command `.dbFlow/setup.sh --generate <project_name>`. After that some informations about the project are expected. All entries are stored in the two files `build.env` and `apply.env`. `build.env` contains information about the project itself and `apply.env` contains information about the database connection and environment. The filename `apply.env` is stored in the file `.gitignore` and should not be versioned. Since this file contains environment related information, it is also exactly the one that changes per instance / environment. All settings in this file can be entered also from "outside", in order to fill these for example from a CI/CD Tool.

!!! info

    You can always execute a bash script/command inside `.dbFLow` folder without arguments to show usage help.

### Generate Project

```bash
$ .dbFlow/setup.sh --generate <project_name>
```

You will be asked the following questions when creating the project:


| Question | Notes |
|----------|-------|
| Which **dbFLow** project type do you want to create? **==S==**ingle, **==M==**ulti or **==F==**lex [M] | This is the first question. Here you define the project mode. Default is **==M==**ulti . ( see: [project-types]) |
| When running release tests, what is your prefered branch name [build] | Later you have the possibility to run so called release tests (NightlyBuilds) . Here you determine the branch name for the tests. The default here is **build**. |
| Would you like to process changelogs during deployment [Y] | **dbFlow** offers the possibility to generate changlogs based on the commit messages. Here you activate this function. ( see: [changelog]) |
| What is the schema the changelog is processed with [schema_name] | If you want changelogs to be displayed within your application, you can specify the target schema here, with which the corresponding TemplateCode should be executed. ( see: [changelog]) |
| Enter database connections [localhost:1521/xepdb1] | Place your connection string like: host:port/service |
| Enter username of admin user (admin, sys, ...) [sys] | This user is responsible for all scripts inside `db/_setup` folder |
| Enter password for sys [leave blank and you will be asked for] | Nothing more to clarify. Password is written to apply.env which is mentioned in .gitignore. (Keep in mind that passwords are saved obfuscated) |
| Enter password for deployment_user (proxyuser: ?_depl) [leave blank and you will be asked for] | Nothing more to clarify. Password is written to apply.env which is mentioned in .gitignore. (Keep in mind that passwords are saved obfuscated) |
| Enter path to depot [_depot] | This is a relative path which points to the depot (artifactory) and is also mentioned in .gitignore (see: [depot])|
| Enter stage of this configuration mapped to branch (develop, test, master) [develop] | When importing the deployment, this setting assigns the database connection to the source branch |
| Do you wish to generate and install default tooling? (Logger, utPLSQL, teplsql, tapi) [Y] | Here you activate the initial installation of the different components/dependencies. These are placed in the `db/_setup/features` folder. There you can also place other features by yourself. If you don't need certain components, you can delete the corresponding file from the features folder (before running the actual installation)..
| Install with sql(cl) or sqlplus? [sqlplus] | Here you define which CLI **dbFLow** should use to execute the SQL scripts. |
| Enter path to place logfiles into after installation? | You can define a path where the log files will be stored as well. This is useful when you have instance repos and want to have a history of your deployments near by the instance itself. |
| Enter application IDs (comma separated) you wish to use initialy (100,101,...) | Here you can already enter the application IDs that **dbFlow** should initially take care of |
| Enter restful Moduls (comma separated) you wish to use initialy (api,test,...) | Here you can already specify the REST modules that **dbFlow** should initially take care of |


  [changelog]: ../changelog/#configuration
  [project-types]: ../concept/#project-types
  [depot]: ../concept/#depot

After answering all the questions, your project structure is created with some SQL and bash files inside. You can now modifiy these files and / or put some files of your own into the corresponding folders.

#### Without wizard

Sometimes you want to have this questions and answers filled directly from the environment. In this case it is enough to specify the --wizard flag.

```bash
$ .dbFlow/setup.sh --generate <project_name> --wizard
```

This is especially useful if you want to build such a project scripted via a CI/CD.

#### Just environment

This is especially important for instance directories. So if you assign a directory to a target stage, you can install the actual patch from depot and get the complete directory structure written to the current directory via this.

```bash
$ .dbFlow/setup.sh --generate <project_name> --envonly
```

### Copy Project

As an addition to the generation of a project with the `--envonly` option, one has the possibility to copy the configuration and the setup, so the foundation, into a new target directory.

```bash
$ .dbFlow/setup.sh --copyto <target-path>
```

This is useful when you want to make your target instance project ready. So after customizing the data connection in the `apply.env` in the target directory you can install all dependencies like schemas, features and workspaces in the target instance.

### Generating apply.env only

Mostly you will clone an existing dbFlow project and configure your environment to start working. In that case you just have to generate the apply.env file.

```bash
$ .dbFlow/setup.sh --apply
```

This will walk you through the wizard steps and outputs the file apply.env. So the fastest way to get into a dbFlow project would be the folloing snippet

```bash
# clone the repo recursive and change into it
$ git clone --recursive https://path-to-your-db-flow-project-where-dbFlow-is-allready-installed.git your_project && cd your_project && .dbFLow/setup.sh --apply
```

### Install Project

> When you fullfilled the steps in the previous section, you are ready to install the project with dependencies into your database

```bash
$ .dbFlow/setup.sh --install
```
> This will run all SQL and bash files inside the db/_setup directory.

For deployment or release purposes. This is the time to make all branches equal. So if you are on master and this your only branch, create a branch for each
deployment stage (develop, test, ...) or if you allready did that, just merge these changes into your branches.

!!! warning "Important!"

    The installation will abort if the users already exist in the DB as a schema. Furthermore, during the installation of the standard features, it will ask in each case, if they already exist, whether they should be overwritten.
    You have the option to flag this with a step *force* by using `.dbFlow/setup.sh --install --force`. In this case, all target schemas and features are deleted before the actual installation in each case.


During the installation **dbFlow** will execute every SQL or bash file in alphabetical order. The sequence of folder will be:

1. tablespaces
1. directories
1. users
1. features
1. workspaces
1. acls

[How to make a release]: ../release
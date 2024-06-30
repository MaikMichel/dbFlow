# Get Started with dbFLow

**dbFlow** is a deployment tool / framework for database driven applications in the oracle environment, mainly in the area of Oracle APEX. With **dbFlow** you can create and deploy multi-layered applications. **dbFlow** is powered by Git and can build a deployment / patch from different commit states, which can then be rolled out to different target instances.

## Prerequisite

- **dbFlow** is written completely in *==bash==* and requires an appropriate environment for this.
- **dbFlow** uses *==Git==* to build the different releases and therefore requires a corresponding installation.
- **dbFlow** uses either *==SQLplus==* or *==SQLcl==* to deploy the releases into the target database. Therefore one of the two tools must be available.

## Get dbFLow

**dbFlow** expects itself as a **`.dbFlow`** subdirectory in an existing main directory or Git repository. The best way to do this is to add **dbFlow** as a submodule in the repository.

### 1. Create a Git repositoy
```bash
  $: mkdir demo && cd demo && git init
```
### 2. Add **dbFlow** as `.dbFlow` submodule to your Project
```bash
  $: git submodule add https://github.com/MaikMichel/dbFlow.git .dbFlow
```

That's it. Now you have **dbFlow** successfully installed.


## Generate a **dbFlow** Project

### 3. Run `setup` to generate a Project
```bash
  $: .dbFlow/setup.sh --generate demo
```
### 4. Answer some question based on your requirements

!!! info

    If you call `.dbFlow/setup.sh` without arguments you will see the possible options as a help page.

> More infos on using setup.sh [Setup](../setup)

## Install the Project basement and dependencies

### 5. Review files, generated for you and make some adjustments

After you run the setup process, **dbFlow** has created a very specific directory structure called [SmartFS](../concept/#smartfs) and a few scripts. The scripts used for the installation can be found in the `db/_setup` folder. You can modify them according to your needs or add new ones.

!!! info

    **dbFlow** comes with 4 features enabled by default. These are OOS Logger, utPLSQL, tePLSQL and OM Tapigen. If you don't need these features, you can delete the scripts from the folder `db/_setup/features`.


### 6. Run `setup` to install the Project
```bash
  $: .dbFlow/setup.sh --install
```

## Done

That's it. You now have prepared your database and your filesystem. Now you can start developing your applications. I recommened to use VSCode and the Extension [dbFlux](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow). [dbFlux](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow) was created exactly for CI/CD in mind. Write files, execute files towards your development database connection, commit and push files to feed your pipelines, which were running dbFlow.


(dbFLux)

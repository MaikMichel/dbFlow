# Get Started with dbFLow

**dbFlow** is a deployment tool / framework for database driven applications in the oracle environment, mainly in the area of Oracle APEX. With **dbFlow** you can create and deploy multi-layered applications. **dbFLow** is powered by Git and can build a deployment / patch from different commit states, which can then be rolled out to different target instances.

## Prerequisite

- **dbFLow** is written completely in *==bash==* and requires an appropriate environment for this.
- **dbFlow** uses *==Git==* to build the different releases and therefore requires a corresponding installation.
- **dbFLow** uses either *==SQLplus==* or *==SQLcl==* to build the releases into the target database. Therefore one of the two tools must be available.

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

<!-- TODO: Link to Setup -->


## Install the Project basement and dependencies

### 5. Review files, generated for you and make some adjustments

**dbFlow** has created a very specific directory structure and a few scripts when you created the project. The scripts used for the installation can be found in the `db/_setup` folder. You can modify them according to your needs or add new ones.

!!! info

    **dbFlow** comes with 4 features by default. These are OOS Logger, utPLSQL, tePLSQL and OM Tapigen. If you don't need these features, you can delete the scripts from the folder `db/_setup/features`.

<!-- TODO: Link auf smartFS -->

## 6. Run `setup` to install the Project
```bash
  $: .dbFlow/setup.sh --install
```



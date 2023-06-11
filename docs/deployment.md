# Deployment

As already described in the [concept] dbFlow knows two types of releases. One is the initial release, which imports the complete product against empty schemas or clears them first, and the other is the patch release, which determines the delta of two commit levels and applies it on top to an existing installation.

   [concept]: ../concept/#2-phase-deployment

![](images/depot_and_flow.png)


A deployment can be divided into two steps. In the first step, the artifact is built. This is done by the script `.dbFlow/build.sh`. In the second step the artifact is applied to the target environment. This is done by calling the script `.dbFlow/apply.sh.`

- Step 1: **build** - This is where the artifact is created.
- Step 2: **apply** - This is where the artifact is deployed to the respective target environment.

!!! danger "Warning"

    Remember, during an init, the target schemas are cleared at the beginning. All objects will be dropped!


## build

The build.sh script is used to create the so-called build file or artifact. This is used to create the actual release based on the state of the files in the directory tree / Git repo.
As with any dbFlow script, you can display the possible parameters by omitting the parameters or explicitly with the ``--help`` parameter.

The build.sh script creates a tar ball with all relevant files and stores it in the depot. The location of the depot is determined in the file apply.env.


### init mode

In an **init**ial release, all files from the database directories are determined and imported in a specific order. The files from the directories ``\*/[ddl|dml]/patch/\*`` and ``\*/tables/tables_ddl`` are ignored.

By using the flag ``-i/--init`` an **init**ial release is created. Additionally you need the target version of the release. With the flag ``-v/--version`` you name the version of the release.
The release itself is created from the current branch. If you want to create a release from another branch, you have to switch there with Git first.


!!! info "Order of the directories"

    | Num    | Folder                 | Num | Folder              | Num | Folder         |
    |--------|------------------------|-----|---------------------|-----|----------------|
    |   1    | .hooks/pre             |  11 | contexts            | 21  | tests/packages |
    |   2    | sequences              |  12 | policies            | 22  | ddl/init       |
    |   3    | tables                 |  13 | sources/types       | 23  | dml/init       |
    |   4    | indexes/primaries      |  14 | sources/packages    | 24  | dml/base       |
    |   5    | indexes/uniques        |  15 | sources/functions   | 25  | .hooks/post    |
    |   6    | indexes/defaults       |  16 | sources/procedures  |     |                |
    |   7    | constraints/primaries  |  17 | views               |     |                |
    |   8    | constraints/foreigns   |  18 | mviews              |     |                |
    |   9    | constraints/checks     |  19 | sources/triggers    |     |                |
    |  10    | constraints/uniques    |  20 | jobs                |     |                |



```shell
$ .dbFlow/build.sh --init --version 1.0.0
```

> If you name the version with "install" then the release will be applied directly.


#### Additional arguments in init mode:

***keepFolder***

With the flag --k / --keepfolder the working directory, which is created in the depot to create the actual artifact, is not deleted. Especially in the beginning, when you don't have so much experience with dbFlow, this option is helpful. So after creating the artifact you can navigate to the corresponding directory and have a look at the created scripts and copied files.



### patch mode

In a **patch** release, all changed files are determined from the database directories and applied in a specific order. Which files are considered as modified is determined by Git. With the parameters ``-s/--start`` (defaults to ORIG_HEAD) and ``-e/--end`` (defaults to HEAD) one can set these parameters explicitly. Which files become part of the **patch** can be output by using the ``-l/--listfiles`` flag.

> Start should always be at least one commit prior to the end commit.

The files from the directories ``\*/[ddl|dml]/init/\*`` are ignored. Additionally there is the import switch, which says, that if the table to be changed exists in the ``table`` folder **AND** in the ``table_ddl`` folder, **ONLY** the files with the same name from the ``table_ddl`` folder are imported.

By using the flag ``-p/--patch`` a patch release is created. Additionally you need the target version of the release. With the flag ``-v/--version`` you name the version of the release.

!!! info "Order of the directories"

    .hooks/pre ddl/patch/pre_${branch} dml/patch/pre_${branch} ddl/patch/pre dml/patch/pre sequences tables tables/tables_ddl indexes/primaries indexes/uniques indexes/defaults constraints/primaries constraints/foreigns constraints/checks constraints/uniques contexts policies sources/types sources/packages sources/functions sources/procedures views mviews sources/triggers jobs tests/packages ddl/patch/post_${branch} dml/patch/post_${branch} ddl/patch/post dml/base dml/patch/post .hooks/post


```shell
$ .dbFlow/build.sh --patch --version 1.1.0
$ .dbFlow/build.sh --patch --version 1.2.0 --start 1.0.0
$ .dbFlow/build.sh --patch --version 1.3.0 --start 71563f65 --end ba12010a
$ .dbFlow/build.sh --patch --version 1.4.0 --start ORIG_HEAD --end HEAD
```

For example, by using stage branches, you can merge the current state of the develop branch into the test branch and build the release by implicitly using the Git variables HEAD and ORIG_HEAD.

```shell
# make shure you have all changes
@develop$ git pull

# goto branch mapped to test-Stage
@develop$ git checkout test

# again: make shure you have all changes
@test$ git pull

# merge all chages from develop
@test$ git merge develop

# build the relase artifact
@test$ .dbFlow/build.sh --patch --version 1.2.0
```

## release

You don't have to do these steps manually if you use the release.sh script. Here you can simply specify your target branch and the script does the appropriate steps to merge the respective branches itself.
By omitting the parameters you can also see what is needed.

> release.sh does the handling / merging of the branches for you and calls build.sh afterwards.

```shell
  .dbFlow/release.sh --target master --version 1.2.3
```

To do a release test, the release script can build three artifacts for you (flag ``-b/--build``). This functionality is for the so-called nightly builds. Here an initial release of the predecessor, a patch of the successor, and an initial release of the successor are built. Using a CI/CD server, such as Jenkins, you can then create these 3 artifacts and install them one after the other on the corresponding instance and of course test them.

```shell
.dbFlow/release.sh --source develop --target master -b
```

## apply

The apply.sh command applies a release to the respective configured database. The artifact is fetched from the depot and unpacked into the appropriate directory. Afterwards the installation scripts are executed. The variable STAGE, from the file apply.env, is used to determine the source directory of a release. The build script stores the artifacts in a directory in a depot that contains the current branch name. The naming of the variable STAGE is now used to get the artifact matching the stage / database connection.

> With this method there can be n instances, which all point to the same depot directory.

!!! info

    I recommend to create a corresponding instance directory for each database and to version it as well. This directory should also contain a .dbFlow - submodule. It is sufficient to copy the files apply.env and build.env into the directory and to adjust the database connection and the stage.

### init

!!! danger "Warning"

    Importing an init release leads to data loss!


By specifying the ``-i/--init`` flag, an init release is retrieved from the depot and then imported. If no password is stored in the apply.env (this is recommended), it will be requested at the very beginning. Because on init then content of all included schemas will be deleted you are asked to proceed. When you provide an environment variable called ``DBFLOW_JENKINS`` with any value the question is skipped.


```shell
$ .dbFlow/apply.sh --init --version 1.0.0
```

### patch

By specifying the ``-p/--patch`` flag, a patch release is searched for in the depot and then applied. If no password is stored in the apply.env (this is recommended), it will be requested at the very beginning.

```shell
$ .dbFlow/apply.sh --patch --version 1.1.0
```

After the installation of a release, the artifact, as well as all resulting log and installation files are stored in the depot under the directory (success or failure). Failure of course only if the installation was aborted due to an error.

Now it can happen that you want to continue the installation after an interruption at the same place. For this the parameter ``-r/--redolog`` is used. If you specify the log file of the previous installation, it will be analyzed and continued with the step that leads to an abort.


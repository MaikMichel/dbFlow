# Migrating

## Basic adjustments

If you want to migrate from an old version to a new version, you have to do the following steps

1. pull the current dbFlow version from github
2. Adjust the directory structure from top to bottom

!!! info "Important"

    This means that you have to make the changes in the master branch and merge them through the stage branches to the development branch. This way, there is no new delta to be imported for these adjustments in the next release.

    ```shell
      # after the changes
      $...@master: git commit -m "migrating dbFlow new structure"
      $...@master: git push

      # checkout user acceptence stage
      $...@master: git checkout uac
      $...@uac: git merge master
      $...@uac: git push

      # checkout user test stage
      $...@uac: git checkout test
      $...@test: git merge uac
      $...@test: git push

      # checkout user development stage
      $...@test: git checkout develop
      $...@develop: git merge test
      $...@develop: git push

    ```

## You need to look at

### Sequence in processing the folders in version 3.3.0

- This is the first release which will handle the content of the `base` folder before the `init` folder
> So you have to check the dependency on underlying files not to depent on files running inside `init` folder




### Following changes in directory structure from 0.9.8 - stable to 1.0.0

1. The folder `tables_ddl` becomes a subfolder of the folder `tables`.
2. The directories `dml/pre` and `dml/post`, and `ddl/pre` and `ddl/post` become:
    `dml/patch/pre` and `dml/patch/post`, and `ddl/patch/pre` and `ddl/patch/post`.
3. In old versions there was the folder `source`. This is treated as plural now and must be renamed to `sources`.


### Following changes in build.env from 0.9.8 - stable to 1.0.0 have to be done

1. You have to store project mode inside build.env
  ```shell
    # Following values are valid: SINGLE, MULTI or FLEX
    PROJECT_MODE=MULTI
  ```
2. When you want to use release.sh for nightlybuild, you have to name the build branch
  ```shell
    # Name of the branch, where release tests are build
    BUILD_BRANCH=build
  ```

3. When you are using the generate changelog feature you have to adjust the following vars
  ```shell
    # Generate a changelog with these settings
    # When template.sql file found in reports/changelog then it will be
    # executed on apply with the CHANGELOG_SCHEMA .
    # The changelog itself is structured using INTENT_PREFIXES to look
    # for in commits and to place them in corresponding INTENT_NAMES inside
    # the file itself. You can define a regexp in TICKET_MATCH to look for
    # keys to link directly to your ticketsystem using TICKET_URL
    CHANGELOG_SCHEMA=schema_name
    INTENT_PREFIXES=( Feat Fix )
    INTENT_NAMES=( Features Fixes )
    INTENT_ELSE="Others"
    TICKET_MATCH="[A-Z]\+-[0-9]\+"
    TICKET_URL="https://url-to-your-issue-tracker-like-jira/browse"    
  ```

### Following changes in directory structure from 3.2.0 - stable to 3.3.0

1. The Folder `dml/base` is now executed prior `dml/init`. Files inside base directory are meant to run each time they are touched. If there is data depending on other data, you should provide a prefix to the files. Because all file are run in order.
2. You have now the option to place synonyms in specific folders `synonyms/private` and `synoynms/public`. So you do not have to put them as ddl files anymore.

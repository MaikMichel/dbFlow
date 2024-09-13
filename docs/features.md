## Generating Changelogs

With dbFlow you have the possibility to create changelogs automatically. These are based on the commit messages of the commits that lead to a patch. The changelog file itself is kept as markdown. Additionally the changelog can be automatically processed (uploaded to the DB) during the deployment if there is a subdirectory named changelog in the reports-folder.

### Configuration

After creating the directory structure and environment files, the following variables were created in the build.env file.

```
CHANGELOG_SCHEMA=<schema_name>
INTENT_PREFIXES=( Feat Fix )
INTENT_NAMES=( Features Fixes )
INTENT_ELSE="Others"
TICKET_MATCH="[A-Z]\+-[0-9]\+"
TICKET_URL="https://[your-jira-url]/browse"
```

| Name            | Meaning                                               |
|-----------------|-------------------------------------------------------|
|CHANGELOG_SCHEMA | With this scheme the changelog is processed by the reports directory |
|INTENT_PREFIXES  | The commit messages are grouped with this array of prefixes |
|INTENT_NAMES     | This array holds the labels of the prefixes, which then appear as headings in the actual changelog |
|INTENT_ELSE      | All messages not handled by the prefixes appear here |
|TICKET_MATCH     | RegularExpression to get the ticket number from the commit message |
|TICKET_URL       | URL to which the ticket number is appended |


A template.sql file is stored in the ``reports/changelog`` directory by default. This file contains the code you have to change to upload this changelog as a clob to a target table.

For example like this:

```sql
  /***********************************************
    -------     TEMPLATE START            -------
    l_bin         >>> Content as blob of file
    l_file_name   >>> name of the file
                      changelog_init_1.2.3.md
  ************************************************/

  Declare
    l_version varchar2(100);
  Begin
    l_version := substr(l_file_name, instr(l_file_name, '_', 1, 2)+1);
    l_version := substr(l_version, 1, instr(l_version, '.', -1, 1)-1);

    -- START custom code
    begin
      insert into changelogs (chl_version, chl_date, chl_content)
       values (l_version, current_date, l_bin);
    exception
      when dup_val_on_index then
        update changelogs
           set chl_content = l_bin,
               chl_date    = current_date
         where chl_version = l_version;
    end;

    -- END custom code

    dbms_output.put_line(gc_green||' ... Version info uploaded: ' || l_version ||gc_reset);
  End;

  /***********************************************
    -------     TEMPLATE END              -------
  ************************************************/


```

### Example

```md
# Project XYZ - Changelog

## Version 1.2.3 (2022-04-08)

### Features

* Changelogs and Version infos are now displayed
* Emailfrom is included in ref_codes based on stage #XYZ-69 [View](https://your-own-jira-url-for-example.com/browse/XYZ-69)
* Managing total revenues per corporations #XYZ-71 [View](https://your-own-jira-url-for-example.com/browse/XYZ-71)
* Reporting Dashboard includes total revenues #XYZ-72 [View](https://your-own-jira-url-for-example.com/browse/XYZ-72)


### Others

* Add some unit tests
* Application processes outsourced to package
* Color Settings for VSCode
* Fix Refresh Facetted Search after transaction occured
* Refactored revenue_totals to be more testable
* Set missing max length
* Set plsql searchPath
* XYZ-50: Changed Buttontext on confirm Email [View](https://your-own-jira-url-for-example.com/browse/XYZ-50)
* XYZ-50: Update Email text of invitation [View](https://your-own-jira-url-for-example.com/browse/XYZ-50)
* XYZ-74: Aliases in own table [View](https://your-own-jira-url-for-example.com/browse/XYZ-74)
* XYZ-74: Nach Nachfrage aus bestehenden Supplier einen Alias machen [View](https://your-own-jira-url-for-example.com/browse/XYZ-74)
```

## Generating Release Notes

Unlike changelogs, release notes are not generated from commit messages. Instead, they can be created as Markdown files. The release notes are stored as report templates in the `reports/release_notes` folder. In `init` mode, **dbFlow** concatenates all files beginning with the prefix `release_log_` into a single file. In `patch` mode, only the modified files are merged. The files are sorted alphabetically.

### Configuration

First, the `reports/release_notes` directory must be created. Additionally, **dbFlow** expects a `template.sql` file. This file is executed when the release is applied and must follow this structure:

```sql
  /***********************************************
    -------     TEMPLATE START            -------
    l_bin         >>> file content as blob
    l_file_name   >>> filename
  ************************************************/


  Begin
    dbms_output.put_line(gc_green||'File: ' || l_file_name ||gc_reset);
    dbms_output.put_line(gc_green||'Blob: ' || dbms_lob.getlength(l_bin) ||gc_reset);
  End;

  /***********************************************
    -------     TEMPLATE END              -------
  ************************************************/

```
The easiest way to do this is to use VSCode with the [dbFlux](https://marketplace.visualstudio.com/items?itemName=MaikMichel.dbflow) plugin. Here you can then execute the command: `dbFlux: Add REPORT Type`.

The code between Begin and End can be adapted according to your own wishes. This means that the release notes can be inserted into a corresponding target table during import.

If the project mode is *MULTI* or *FLEX*, the variable `RELEASENOTES_SCHEMA` with the target schema must be defined in the `build.env` file. For example like this:

```bash
...
RELEASENOTES_SCHEMA=todo_app
...
```

You are now ready to write the actual release notes.

### Example

Let's assume you work in sprints. Then you could create the following files.

reports/release_notes/release_note_sprint_1.md
```md

## Version 1.2 (22.08.2024)

### Features

- Add due date to task record
- Add ability to check / uncheck tasks in classic report

### Fixes

- Fixed typo in modal dialog of task record
```

reports/release_notes/release_note_sprint_2.md
```md

## Version 1.3 (23.08.2024)

### Features

- Add function to assign a user to a task

### Fixes

- Fixed error when submitting by doubleclick
```

In the case of an initial release, both files are copied together and processed by the `template.sql` file. And for a patch release 1.3.0, only the modified file `reports/release_notes/release_note_sprint_2.md` is passed through `template.sql`.

> You can then determine how the header or footer looks in the possible target table for yourself by modifying the template.sql data.

> You will always find the summarized ReleaseNotes file in the log directory.


## Switching off the applications

During installation all known APEX applications will be set to unavailable. This is done by APEX's own API apex_util.set_application_status. The content of the file .dbFlow/maintence.html will be displayed as a message to the end user. But you have the option to use your own maintence.html file. dbFlow will first try to read the apex/maintence.html file. If it is found, the content will be displayed as a message. Otherwise the one that exists in the .dbFlow directory.

### Example

```html
<title>Site Maintenance</title>
<style>
  body { text-align: center; padding: 20px; }
  '||'@'||'media (min-width: 768px){
    body{ padding-top: 200px; }
  }
  h1 { font-size: 50px; }
  body { font: 20px Helvetica, sans-serif; color: #333; }
  article { display: block; text-align: left; max-width: 650px; margin: 0 auto; }
  a { color: #dc8100; text-decoration: none; }
  a:hover { color: #333; text-decoration: none; }
</style>

<article>
    <h1>We&rsquo;ll be back soon!</h1>
    <div>
        <p>Sorry for the inconvenience but we&rsquo;re performing some maintenance at the moment. We&rsquo;ll be back online shortly!</p>
        <p>&mdash; The Team</p>
    </div>
</article>
```

### REST modules

Additionally, all REST modules are also unpublished during an installation.

## MS Teams Notification

After a deployment **dbFlow** is able to send a message to a Microsoft Teams hook. All you have to do is to provide the hook link set the variable TEAMS_WEBHOOK_URL.

```bash
TEAMS_WEBHOOK_URL=https://url-to-your-incoming-teams-webhook
```

## Usage of environment variables

In addition to the installation mode (`MODE`) and the currently installed version (`VERSION`), you can use your own environment variables within the global hook SQL scripts from dbFlow 3.2 onwards.
To be able to use environment variables, these must exist and be made known to dbFlow. For this purpose, dbFlow reads the variable `VAR_LIST`. As of version 3.2, this is generated in the apply.env file or can be added manually.


```shell
...
# List of Environment Vars to inject into global hooks, separated by colons
VAR_LIST="STAGE:DEPOT_PATH"
```

While dbFlow prepares the call of the global hooks, these are defined by SQLplus/SQLcl.


> ```sql
> -- Example to show, how dbFlow prepars a var. You don't have to do this on your own
> define LOG_PATH="${LOG_PATH}" "UNDEFINED"
> ```

You can then use the variables in your hook scripts.

```sql
PROMPT ********************************************************************
PROMPT * VERSION:    ^VERSION
PROMPT * MODE:       ^MODE
PROMPT * STAGE:      ^STAGE
PROMPT * DEPOT_PATH: ^DEPOT_PATH
PROMPT ********************************************************************
```
The output would look something like this
> ```text
> ********************************************************************
> * VERSION:    1.2.3
> * MODE:       patch
> * STAGE:      develop
> * DEPOT_PATH: ./_logs
> ********************************************************************
> ```



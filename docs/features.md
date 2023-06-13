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
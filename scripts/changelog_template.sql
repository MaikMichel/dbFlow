  /***********************************************
    -------     TEMPLATE START            -------
    l_bin         >>> Content of the file as blob
    l_file_name   >>> Filename of the file to process
                      changelog_init_1.2.3.md
  ************************************************/

  Declare
    l_version varchar2(100);
  Begin
    l_version := substr(l_file_name, instr(l_file_name, '_', 1, 2)+1);
    l_version := substr(l_version, 1, instr(l_version, '.', -1, 1)-1);

    dbms_output.put_line(gc_yellow||' Uncomment and change table to upload your changelog!' ||gc_reset);
    -- begin
    --   insert into your_versions_table (yvt_version, yvt_date, yvt_changelog)
    --    values (l_version, current_date, l_bin);
    -- exception
    --   when dup_val_on_index then
    --     update your_versions_table
    --        set yvt_changelog = l_bin,
    --            yvt_date      = current_date
    --      where yvt_version = l_version;
    -- end;

    dbms_output.put_line(gc_green||' ... Version info uploaded: ' || l_version ||gc_reset);
  End;

  /***********************************************
    -------     TEMPLATE END              -------
  ************************************************/

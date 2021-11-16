create or replace package body dbflow$exp_schema is
  c_crlf constant varchar2(10) :=  chr(13)||chr(10);

  function clob_to_blob (p_clob in clob) return blob is
   v_blob      blob;
   v_varchar   raw (32767);
   v_start     binary_integer := 1;
   v_buffer    binary_integer := 32767;
  begin
    dbms_lob.createtemporary (v_blob, false);

    for i in 1 .. ceil (dbms_lob.getlength (p_clob) / v_buffer)
    loop
      v_varchar := utl_raw.cast_to_raw (dbms_lob.substr (p_clob, v_buffer, v_start));
      dbms_lob.append (v_blob, v_varchar);
      v_start := v_start + v_buffer;
    end loop;

    return v_blob;
  end clob_to_blob;

  function get_table(p_table_name   in varchar) return clob is
    v_script    clob;
    v_comments  clob;
  begin
    v_script := dbms_metadata.get_ddl('TABLE', upper(p_table_name));

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- uns interessiert hier nur der erst Teil, bis zum ersten ";"
    v_script := substr(v_script, 1, instr(v_script, ';', 1, 1));

    -- dann das ganze als lowercase
    v_script := lower(v_script);

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"', '');
    v_script := replace(v_script, lower(user)||'.', '');

    begin
    -- zusätzlich holen der Kommentare
      v_comments := dbms_metadata.get_dependent_ddl( 'COMMENT', p_table_name);

      -- username und doppelte Anführungsstriche brauchen wir auch nicht
      v_comments := replace(v_comments, '"', '');
      v_comments := replace(v_comments, user||'.', '');

      dbms_lob.append(v_script, chr(10)||chr(10)||v_comments);
    exception
      when others then
        null; -- ORA-31608: specified object of type COMMENT not found
    end;


    return v_script;
  end;

  function get_constraint(p_constraint_name   in varchar,
                          p_constraint_type   in varchar2) return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl(case
                                        when p_constraint_type = 'R' then
                                          'REF_CONSTRAINT'
                                        else
                                          'CONSTRAINT'
                                      end,
                                      upper(p_constraint_name)
                                      );

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- uns interessiert hier nur der erst Teil, bis zum ersten ";"
    v_script := substr(v_script, 1, instr(v_script, ';', 1, 1));

    -- dann das ganze als lowercase
    v_script := lower(v_script);

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"', '');
    v_script := replace(v_script, lower(user)||'.', '');

    return v_script;
  end;

  function get_index(p_index_name   in varchar) return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl('INDEX',
                                      upper(p_index_name)
                                      );
    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- uns interessiert hier nur der erst Teil, bis zum ersten ";"
    v_script := substr(v_script, 1, instr(v_script, ';', 1, 1));

    -- dann das ganze als lowercase
    v_script := lower(v_script);

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"', '');
    v_script := replace(v_script, lower(user)||'.', '');

    return v_script;
  end;

  function get_source(p_source_name in varchar2,
                      p_source_type in varchar2)
                      return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl(p_source_type,
                                      upper(p_source_name)
                                      );

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"'||user||'"."'||upper(p_source_name)||'"', lower(p_source_name));

    return v_script;
  end;

  function get_sequence(p_sequence_name in varchar2)
                      return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl('SEQUENCE',
                                      upper(p_sequence_name)
                                      );
    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"'||user||'"."'||upper(p_sequence_name)||'"', lower(p_sequence_name));

    return v_script;
  end;

  function get_view(p_view_name in varchar2)
                      return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl('VIEW',
                                      upper(p_view_name)
                                      );

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"'||user||'"."'||upper(p_view_name)||'"', lower(p_view_name));

    return v_script;
  end;

  function get_job(p_job_id in number)
                      return clob is
    pragma autonomous_transaction;
    v_script clob;
  begin
    dbms_job.user_export(p_job_id, v_script);

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '=>'||user||'.', '=>');
    commit;
    return v_script;
  end;



  function get_synonym(p_synonym_name in varchar2,
                       p_owner in varchar2)
                      return clob is
    v_script clob;
  begin
    v_script := dbms_metadata.get_ddl('SYNONYM', upper(p_synonym_name), p_owner);

    -- die erste Zeile ist immer leer
    v_script := substr(v_script, instr(v_script, c_crlf, 1, 1) + length(c_crlf));

    -- username und doppelte Anführungsstriche brauchen wir auch nicht
    v_script := replace(v_script, '"', '');
    v_script := replace(v_script, user||'.', '');

    return v_script;
  end;


  function get_zip(p_object in varchar2 default 'ALL')return blob is
    v_zip_file  blob;
    v_file      blob;
  begin
    dbms_output.put_line('Scanning for object: '||p_object);

    for cur in (select table_name, 'tables/'||lower(table_name)||'.sql' filename
                  from user_tables
                 where p_object = 'ALL' or upper(table_name) = upper(p_object))
    loop
      v_file := clob_to_blob(get_table(p_table_name   => cur.table_name));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    for cur in (select constraint_name, 'constraints/' ||
                        case
                          when constraint_type = 'P' then 'primaries'
                          when constraint_type = 'U' then 'uniques'
                          when constraint_type = 'R' then 'foreigns'
                          when constraint_type = 'C' then 'checks'
                        end || '/' ||lower(constraint_name)||'.sql' filename,
                        constraint_type
                  from user_constraints
                 where generated != 'GENERATED NAME'
                   and constraint_name not like 'BIN$%'
                   and (p_object = 'ALL' or upper(constraint_name) = upper(p_object) or upper(table_name) = upper(p_object)) )
    loop
      v_file := clob_to_blob(get_constraint(cur.constraint_name, cur.constraint_type));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                      ,p_file_name   => cur.filename
                      ,p_content     => v_file
          );
    end loop;


    for cur in (select i.index_name index_name, 'indexes/'||
                       case
                         when c.constraint_type = 'P' then 'primaries'
                         when i.uniqueness = 'UNIQUE' then 'uniques'
                         else 'defaults'
                       end ||'/' ||lower(i.index_name)||'.sql' filename
                  from user_indexes i left join user_constraints c on i.index_name = c.index_name
                 where index_type != 'LOB'
                   and (p_object = 'ALL' or upper(i.index_name) = upper(p_object) or upper(i.table_name) = upper(p_object)) )
    loop
      v_file := clob_to_blob(get_index(p_index_name   => cur.index_name));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    for cur in (select object_name,
                        case
                          when object_type = 'PACKAGE BODY' then 'PACKAGE_BODY'
                          when object_type = 'PACKAGE' then 'PACKAGE_SPEC'
                          else object_type
                        end source_type,
                        'sources/'||
                        case
                          when object_type in ('PACKAGE', 'PACKAGE BODY') then 'packages'
                          else lower(object_type)
                        end||'/'||lower(object_name)||'.'||
                        case
                          when object_type = 'PACKAGE BODY' then 'pkb'
                          when object_type = 'PACKAGE' then 'pks'
                          else 'sql'
                        end filename
                  from user_objects
                 where object_type in ('TYPE', 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 'TRIGGER')
                   and object_name not like 'TEST\_%' escape '\'
                   and object_name not like 'SYS\_PLSQL\_%' escape '\'
                   and object_name != 'DBFLOW$EXP_SCHEMA'
                   and (p_object = 'ALL' or upper(object_name) = upper(p_object)) )
    loop
      v_file := clob_to_blob(get_source(p_source_name => cur.object_name,
                                        p_source_type => cur.source_type));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;


    for cur in (select object_name,
                        case
                          when object_type = 'PACKAGE BODY' then 'PACKAGE_BODY'
                          when object_type = 'PACKAGE' then 'PACKAGE_SPEC'
                          else object_type
                        end source_type,
                        'tests/'||
                        case
                          when object_type in ('PACKAGE', 'PACKAGE BODY') then 'packages'
                          else lower(object_type)||'s' -- plural
                        end||'/'||lower(object_name)||'.'||
                        case
                          when object_type = 'PACKAGE BODY' then 'pkb'
                          when object_type = 'PACKAGE' then 'pks'
                          else 'sql'
                        end filename
                  from user_objects
                 where object_type in ('TYPE', 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 'TRIGGER')
                   and object_name like 'TEST\_%' escape '\'
                   and (p_object = 'ALL' or upper(object_name) = upper(p_object))  )
    loop
      v_file := clob_to_blob(get_source(p_source_name => cur.object_name,
                                        p_source_type => cur.source_type));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    for cur in (select sequence_name, 'sequences/'||lower(sequence_name)||'.sql' filename
                  from user_sequences
                 where sequence_name not like 'ISEQ%'
                   and (p_object = 'ALL' or upper(sequence_name) = upper(p_object)) )
    loop
      v_file := clob_to_blob(get_sequence(p_sequence_name   => cur.sequence_name));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    for cur in (select view_name, 'sources/views/'||lower(view_name)||'.sql' filename
                  from user_views
                 where (p_object = 'ALL' or upper(view_name) = upper(p_object)) )
    loop
      v_file := clob_to_blob(get_view(p_view_name   => cur.view_name));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    for cur in (select job, 'jobs/job_'||job||'.sql' filename
                  from user_jobs)
    loop
      v_file := clob_to_blob(get_job(p_job_id   => cur.job));

      apex_zip.add_file(p_zipped_blob => v_zip_file
                        ,p_file_name   => cur.filename
                        ,p_content     => v_file
          );
    end loop;

    -- for cur in (select synonym_name,  owner, 'synonyms/public/'||synonym_name||'.sql' filename
    --               from all_synonyms
    --             where owner in 'PUBLIC'
    --               and table_owner = user
    --             union
    --             select synonym_name,  user, 'synonyms/private/'||synonym_name||'.sql' filename
    --               from user_synonyms)
    -- loop
    --   v_file := clob_to_blob(get_synonym(p_synonym_name   => cur.synonym_name,
    --                                      p_owner => cur.owner));

    --   apex_zip.add_file(p_zipped_blob => v_zip_file
    --                     ,p_file_name   => cur.filename
    --                     ,p_content     => v_file
    --       );
    -- end loop;

    -- finish zip
    apex_zip.finish(p_zipped_blob => v_zip_file);

    return v_zip_file;
  end;

begin
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR',        true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY',               true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE',              true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES',   false);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS',          true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS',      true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS_AS_ALTER', true);
end;
/
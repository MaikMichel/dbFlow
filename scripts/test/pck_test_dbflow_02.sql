
    open l_actual for
      select dft_file
        from dbflow_test
       where dft_mode = p_mode
       order by dft_id;

    ut.expect( l_actual ).to_equal( l_expected);
  end;

  procedure check_scripts_init is
  begin
    check_scripts(p_mode => 'init');
  end;

  procedure check_scripts_patch is
  begin
    check_scripts(p_mode => 'patch');
  end;
end;
/

set pagesize 9999
set linesize 2000
set serveroutput on

set trim on


create or replace package test_dbflow as
  --%suite(Call all deployment scripts with dbFlow)

  --%test(Check number of scripts called by .dbFlow/apply.sh --init)
  procedure check_scripts_init;

  --%test(Check number of scripts called by .dbFlow/apply.sh --patch)
  procedure check_scripts_patch;

end;
/

create or replace package body test_dbflow as
  procedure check_scripts_init is
    l_check_init number := 0;
  begin
    select count(1)
      into l_check_init
      from dbflow_test
     where dft_mode = 'init';

    ut.expect(l_check_init).to_equal(0);
  end;

  procedure check_scripts_patch is
    l_check_patch number := 0;
  begin
    select count(1)
      into l_check_patch
      from dbflow_test
     where dft_mode = 'patch';
    ut.expect(l_check_patch).to_equal(0);
  end;
end;
/

set pagesize 9999
set linesize 2000
set serveroutput on

set trim on
exec ut.run('test_dbflow', a_color_console => true);

-- drop package test_dbflow;

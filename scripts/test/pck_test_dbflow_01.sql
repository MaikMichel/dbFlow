create or replace package test_dbflow as
  --%suite(Call all deployment scripts with dbFlow)

  --%test(Check number of scripts called by .dbFlow/apply.sh --init)
  procedure check_scripts_init;

  --%test(Check number of scripts called by .dbFlow/apply.sh --patch)
  procedure check_scripts_patch;

end;
/

create or replace package body test_dbflow as
  procedure check_scripts(p_mode in varchar2) is
    l_actual   sys_refcursor;
    l_expected sys_refcursor;
  begin
    open l_expected for

declare
    l_roles_arr    owa.vc_arr;
    l_patterns_arr owa.vc_arr;
begin
    l_roles_arr(1)    := 'DBFLOW_REST_COMPILE_API_ROLE';
    l_patterns_arr(1) := '/dbflow/deploy/*';

    --  Define privilige and assign it to the role
    ords.define_privilege(
      p_privilege_name => 'DBFLOW_REST_COMPILE_API_PRIV',
      p_roles          => l_roles_arr,
      p_patterns       => l_patterns_arr,
      p_label          => 'dbFlow REST compile',
      p_description    => 'Allow using dbFlow REST compile endpoint'
    );
    commit;
end;
/
begin
    -- Define role
    ords.create_role(
        p_role_name => 'DBFLOW_REST_COMPILE_API_ROLE'
    );
    commit;
end;
/
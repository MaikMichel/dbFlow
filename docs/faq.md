# Frequently Asked Questions or Tips

## How can I correct an existing error retrospectively?

Sometimes it happens that an error slips in. This can happen, for example, if you forget to test the current version of the initial deployment (``init``). As soon as this happens and an error appears here, the subsequent deployments cannot build their predecessor cleanly.
If something like this happens, then you have to merge the error correction from *"top to bottom"*, i.e. from the production branch (**master** or **main**) down to the develop branch. This ensures that at the next deployment, the predecessor (e.g. version on **test**) can be built cleanly.

<center>
  ![Merging Deployment vs. Correction](images/merge_deployment_vs_correction.png){ width="400"}
</center>

## ProxyUser - connection problems

Sometimes it can happen that **dbFlow** or *SQLplus* or *SQLcl* cannot connect to the database. The error: ``ORA-01017: invalid username/password; logon denied`` is displayed. Please check the credentials and the notation in `apply.env`. In `MULTI` and `FLEX` mode, **dbFlow** uses proxy authentication when the database folder schema differs from `DB_APP_USER` (`DB_APP_USER[schema_name]@database:port`). In `SINGLE` mode, **dbFlow** connects directly as `DB_APP_USER` without a proxy user, even when the folder schema has a different name.


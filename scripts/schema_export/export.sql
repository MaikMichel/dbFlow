set define '^'
set concat on
set concat .
set verify off
define OBJECT = '^1'

Prompt uploading export package
set feedback off
@@.dbFlow/scripts/schema_export/export_schema.pks
@@.dbFlow/scripts/schema_export/export_schema.pkb
set feedback on
set serveroutput on
Prompt exporting schema...
Prompt this may take a while...

script
// issue the SQL


var binds = {}
var ret = util.executeReturnList("select export_schema.get_zip('^OBJECT') content from dual",binds);
var usr = util.executeReturnOneCol("select lower(user) from dual");

// loop the results
for (var i = 0; i < ret.length; i++) {
  // debug IS nice
  //ctx.write( ret[i].ID  + "\t" + ret[i].FILE_NAME+ "\n");

  // GET the BLOB stream
  var blobStream =  ret[i].CONTENT.getBinaryStream(1);

  // GET the path/file handle TO WRITE TO
  var path = java.nio.file.FileSystems.getDefault().getPath('db/'+usr+'.exp.zip');

  // dump the file stream TO the file
  java.nio.file.Files.copy(blobStream,path);

}
/
set feedback off
drop package export_schema;
set feedback on


#!/usr/bin/env bash
DBFLOW_JENKINS="YES"
if [[ -z ${DBFLOW_JENKINS:-} ]]; then
  echo "AAAA"
else
  echo "BBBB"
fi
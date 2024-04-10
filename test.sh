
#!/usr/bin/env bash

function retry() {
  local cnt=0;
  while [[ $cnt -lt 10 ]]; do
    if [[ -f ".git/index.lock" ]]; then
      echo -n ".";
      sleep 0.5;
      ((cnt++));
    else
      "$@"; # do the command params
      return; # quit the function
    fi
  done

  echo ".git/index.lock exists and is locked!"
  exit 1;
}

retry echo "test A"
sleep 0.5;
retry echo "test B"
sleep 0.5;
retry echo "test C"
sleep 0.5;
retry echo "test D"
sleep 0.5;
retry echo "test E"
sleep 0.5;
retry echo "test F"
sleep 0.5;
retry echo "test G"
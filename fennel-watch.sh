#!/bin/bash

FENNEL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FENNEL=$FENNEL_DIR/fennel

compile () {
    IN_FILE=$1
    OUT_FILE="${IN_FILE%.fnl}.lua"
    echo -n $( date +%H:%M:%S ) "Compiling $IN_FILE -> $OUT_FILE ... "
    $FENNEL --compile $IN_FILE > $OUT_FILE
    RETURN_VAL=$?
    if [[ $RETURN_VAL -eq 0 ]]; then
        echo "done!"
    else
        echo "failed!"
        cat $OUT_FILE
    fi
}

inotifywait -m -e MODIFY --format %f . | while read FILE
do
    if [[ ${FILE: -4} == ".fnl" ]]; then
        compile $FILE
    else
        echo $( date +%H:%M:%S ) "Ignored" $FILE
    fi
done

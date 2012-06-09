#!/bin/sh

export DOXYGEN=/usr/bin/doxygen
export PG_DOXYFILE=/home/jaubrey/doxygen/pg_doxyfile
export WW2_DOXYFILE=/home/jaubrey/doxygen/ww2_doxyfile

echo ${DOXYGEN}

${DOXYGEN} ${PG_DOXYFILE}
${DOXYGEN} ${WW2_DOXYFILE}

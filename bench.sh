#!/bin/bash

#
# Kieker benchmark script with JoularJX energy measurement
#
# Usage: 
#   ./benchmark3.sh          (works on macOS and Linux)
#   sudo ./benchmark3.sh      (recommended on Linux for accurate energy measurement)
#
# Note: On Linux, sudo is recommended for JoularJX to access RAPL power sensors.
#       On macOS, JoularJX may prompt for password to access powermetrics.

# configure base dir
BASE_DIR=$(cd "$(dirname "$0")"; pwd)
MAIN_DIR="${BASE_DIR}/../.."

#
# source functionality
#

if [ ! -d "${BASE_DIR}" ] ; then
	echo "Base directory ${BASE_DIR} does not exist."
	exit 1
fi

if [ -f "${MAIN_DIR}/init.sh" ] ; then
	source "${MAIN_DIR}/init.sh"
else
	echo "Missing library: ${MAIN_DIR}/init.sh"
	exit 1
fi

if [ -z "$MOOBENCH_CONFIGURATIONS" ]
then
	MOOBENCH_CONFIGURATIONS="0 1 2 4 5"
	echo "Setting default configuration $MOOBENCH_CONFIGURATIONS (without TextLogStreamHandler)"
fi
echo "Running configurations: $MOOBENCH_CONFIGURATIONS"

#
# Setup
#

info "----------------------------------"
info "Setup..."
info "----------------------------------"

cd "${BASE_DIR}"

# load agent
getAgent

checkDirectory data-dir "${DATA_DIR}" create
checkFile log "${DATA_DIR}/kieker.log" clean
cleanupResults
mkdir -p $RESULTS_DIR
PARENT=`dirname "${RESULTS_DIR}"`
checkDirectory result-base "${PARENT}"

checkFile receiver "receiver/receiver.jar"

checkFile Agent "${AGENT_JAR}"

checkExecutable java "${JAVA_BIN}"
checkExecutable moobench "${MOOBENCH_BIN}"
checkFile R-script "${RSCRIPT_PATH}"

showParameter

TIME=`expr ${METHOD_TIME} \* ${TOTAL_NUM_OF_CALLS} / 1000000000 \* 4 \* ${RECURSION_DEPTH} \* ${NUM_OF_LOOPS} + ${SLEEP_TIME} \* 4 \* ${NUM_OF_LOOPS}  \* ${RECURSION_DEPTH} + 50 \* ${TOTAL_NUM_OF_CALLS} / 1000000000 \* 4 \* ${RECURSION_DEPTH} \* ${NUM_OF_LOOPS} `
info "Experiment will take circa ${TIME} seconds."

############################################
# JoularJX Energy Measurement Integration
############################################

JOULARJX_AGENT="${BASE_DIR}/joularjx-3.1.0.jar"

# Setup JoularJX output directory
JOULARJX_OUTPUT_DIR="${BASE_DIR}/joularjx-output"
mkdir -p "${JOULARJX_OUTPUT_DIR}" 2>/dev/null || true

# Add JoularJX javaagent if file exists (optional - script continues without it)
if [ -f "${JOULARJX_AGENT}" ]; then
	# JoularJX javaagent - basic setup
	# Note: JoularJX will create 'joularjx-results' directory in the working directory by default
	# 
	# Platform-specific notes:
	# - Linux: Requires sudo/root to access RAPL power sensors (/sys/class/powercap/)
	#          Run with: sudo ./benchmark3.sh
	# - macOS: May prompt for password to access powermetrics
	#          Can configure sudoers to avoid prompts
	# - Works on both platforms, but accurate energy measurement needs system access
	JOULARJX_ARGS="-javaagent:${JOULARJX_AGENT}"
	info "JoularJX agent found, energy measurement enabled"
	info "JoularJX results will be saved to: ${BASE_DIR}/joularjx-results/ (default location)"
	
	# Check if running with appropriate permissions (Linux)
	if [ "$(uname)" = "Linux" ] && [ "$(id -u)" -ne 0 ]; then
		warn "Running without sudo on Linux - JoularJX may have limited energy measurement accuracy"
		warn "For best results on Linux, run with: sudo ./benchmark3.sh"
	fi
else
	JOULARJX_ARGS=""
	warn "JoularJX agent not found at ${JOULARJX_AGENT}, continuing without energy measurement"
fi

# general server arguments - prepend JoularJX if available
if [ -n "${JOULARJX_ARGS}" ]; then
	JAVA_ARGS="${JOULARJX_ARGS} -Xms1G -Xmx2G"
else
	JAVA_ARGS="-Xms1G -Xmx2G"
fi

LTW_ARGS="-javaagent:${AGENT_JAR} -Dorg.aspectj.weaver.showWeaveInfo=true -Daj.weaving.verbose=true -Dkieker.monitoring.skipDefaultAOPConfiguration=true -Dorg.aspectj.weaver.loadtime.configuration=file://${AOP}"

KIEKER_ARGS="-Dlog4j.configuration=log4j.cfg -Dkieker.monitoring.name=KIEKER-BENCHMARK -Dkieker.monitoring.adaptiveMonitoring.enabled=false -Dkieker.monitoring.periodicSensorsExecutorPoolSize=0"

# JAVA_ARGS used to configure and setup a specific writer
declare -a WRITER_CONFIG
# Receiver setup if necessary
declare -a RECEIVER
# Title
declare -a TITLE

#
# Different writer setups
#
WRITER_CONFIG[0]=""
WRITER_CONFIG[1]="-Dkieker.monitoring.enabled=false -Dkieker.monitoring.writer=kieker.monitoring.writer.dump.DumpWriter"
WRITER_CONFIG[2]="-Dkieker.monitoring.enabled=true -Dkieker.monitoring.writer=kieker.monitoring.writer.dump.DumpWriter -Dkieker.monitoring.core.controller.WriterController.RecordQueueFQN=kieker.monitoring.writer.dump.DumpQueue"
WRITER_CONFIG[3]="-Dkieker.monitoring.enabled=true -Dkieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter -Dkieker.monitoring.writer.filesystem.FileWriter.logStreamHandler=kieker.monitoring.writer.filesystem.TextLogStreamHandler -Dkieker.monitoring.writer.filesystem.FileWriter.customStoragePath=${DATA_DIR}/"
WRITER_CONFIG[4]="-Dkieker.monitoring.enabled=true -Dkieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter -Dkieker.monitoring.writer.filesystem.FileWriter.logStreamHandler=kieker.monitoring.writer.filesystem.BinaryLogStreamHandler -Dkieker.monitoring.writer.filesystem.FileWriter.bufferSize=8192 -Dkieker.monitoring.writer.filesystem.FileWriter.customStoragePath=${DATA_DIR}/ -Dkieker.monitoring.writer.filesystem.FileWriter.maxLogFiles=100 -Dkieker.monitoring.core.controller.WriterController.QueuePutStrategy=kieker.monitoring.queue.putstrategy.YieldPutStrategy"
WRITER_CONFIG[5]="-Dkieker.monitoring.writer=kieker.monitoring.writer.tcp.SingleSocketTcpWriter -Dkieker.monitoring.writer.tcp.SingleSocketTcpWriter.port=2345 -Dkieker.monitoring.core.controller.WriterController.QueuePutStrategy=kieker.monitoring.queue.putstrategy.YieldPutStrategy"
RECEIVER[5]="java -jar receiver/receiver.jar 2345"

export KIEKER_SIGNATURES_INCLUDE="* moobench.application.MonitoredClass.*();* moobench.application.MonitoredClassSimple.*();* moobench.application.MonitoredClassThreaded.*();"

executeAllLoops

exit 0

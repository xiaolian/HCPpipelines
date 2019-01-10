#!/bin/bash

# ------------------------------------------------------------------------------
#  Show usage information for this script
# ------------------------------------------------------------------------------

usage()
{
	cat << EOF

${g_script_name}: Apply Hand Reclassifications of Noise and Signal components
from FIX using the ReclassifyAsNoise.txt and ReclassifyAsSignal.txt input files.

Generates HandNoise.txt and HandSignal.txt as output.
Script does NOT reapply the FIX cleanup.
For that, use the ReApplyFix scripts.

Usage: ${g_script_name} PARAMETER..."

PARAMETERs are: [ ] = optional; < > = user supplied value
  [--help] : show usage information and exit
   --path=<path to study folder> OR --study-folder=<path to study folder>
   --subject=<subject ID>
   --fmri-name=<fMRI name>
   --high-pass=<high-pass filter used in ICA+FIX>

EOF
}

# ------------------------------------------------------------------------------
#  Get the command line options for this script.
# ------------------------------------------------------------------------------
get_options()
{
	local arguments=($@)

	# initialize global output variables
	unset p_StudyFolder
	unset p_Subject
	unset p_fMRIName
	unset p_HighPass
	g_matlab_run_mode=0

	# parse arguments
	local num_args=${#arguments[@]}
	local argument
	local index=0

	while [ ${index} -lt ${num_args} ]; do
		argument=${arguments[index]}

		case ${argument} in
			--help)
				usage
				exit 1
				;;
			--path=*)
				p_StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--study-folder=*)
				p_StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--subject=*)
				p_Subject=${argument#*=}
				index=$(( index + 1 ))
				;;
			--fmri-name=*)
				p_fMRIName=${argument#*=}
				index=$(( index + 1 ))
				;;
			--high-pass=*)
				p_HighPass=${argument#*=}
				index=$(( index + 1 ))
				;;
			--matlab-run-mode=*)
				g_matlab_run_mode=${argument#*=}
				index=$(( index + 1 ))
				;;
			*)
				usage
				log_Err_Abort "unrecognized option: ${argument}"
				;;
		esac
	done

	local error_count=0

	# check required parameters
	if [ -z "${p_StudyFolder}" ]; then
		echo "ERROR: path to study folder (--path= or --study-folder=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "p_StudyFolder: ${p_StudyFolder}"
	fi

	if [ -z "${p_Subject}" ]; then
		echo "ERROR: subject ID required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "p_Subject: ${p_Subject}"
	fi

	if [ -z "${p_fMRIName}" ]; then
		echo "ERROR: fMRI name required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "p_fMRIName: ${p_fMRIName}"
	fi

	if [ -z "${p_HighPass}" ]; then
		echo "ERROR: high pass required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "p_HighPass: ${p_HighPass}"
	fi

	#--matlab-run-mode is now ignored, but still accepted, to make old scripts work without changes

	if [ ${error_count} -gt 0 ]; then
	    log_Err_Abort "For usage information, use --help"
	fi
}

# ------------------------------------------------------------------------------
#  Show Tool Versions
# ------------------------------------------------------------------------------

show_tool_versions()
{
	# Show HCP Pipelines Version
	log_Msg "Showing HCP Pipelines version"
	cat ${HCPPIPEDIR}/version.txt

	# Show FSL version
	log_Msg "Showing FSL version"
	fsl_version_get fsl_ver
	log_Msg "FSL version: ${fsl_ver}"
}

# ------------------------------------------------------------------------------
#  List lookup helper function for this script
# ------------------------------------------------------------------------------

#arguments: filename, output variable name
list_file_to_lookup()
{
    #bash arrays are 0-indexed, but since the components start at 1, we will just ignore the 0th position
    local file_contents=$(cat "$1")
    local component
    unset "${2}"
    for component in ${file_contents}
    do
        declare -g "${2}"["${component}"]=1
    done
}

# ------------------------------------------------------------------------------
#  Main processing of script.
# ------------------------------------------------------------------------------

main()
{
	get_options $@
	show_tool_versions

	# Naming Conventions
	AtlasFolder="${p_StudyFolder}/${p_Subject}/MNINonLinear"
	log_Msg "AtlasFolder: ${AtlasFolder}"

	ResultsFolder="${AtlasFolder}/Results/${p_fMRIName}"
	log_Msg "ResultsFolder: ${ResultsFolder}"

	ICAFolder="${ResultsFolder}/${p_fMRIName}_hp${p_HighPass}.ica/filtered_func_data.ica"
	log_Msg "ICAFolder: ${ICAFolder}"

	FIXFolder="${ResultsFolder}/${p_fMRIName}_hp${p_HighPass}.ica"
	log_Msg "FIXFolder: ${FIXFolder}"
	
	OriginalFixSignal="${FIXFolder}/Signal.txt"
	log_Msg "OriginalFixSignal: ${OriginalFixSignal}"

	OriginalFixNoise="${FIXFolder}/Noise.txt"
	log_Msg "OriginalFixNoise: ${OriginalFixNoise}"

	ReclassifyAsSignal="${ResultsFolder}/ReclassifyAsSignal.txt"
	log_Msg "ReclassifyAsSignal: ${ReclassifyAsSignal}"

	ReclassifyAsNoise="${ResultsFolder}/ReclassifyAsNoise.txt"
	log_Msg "ReclassifyAsNoise: ${ReclassifyAsNoise}"

	HandSignalName="${FIXFolder}/HandSignal.txt"
	log_Msg "HandSignalName: ${HandSignalName}"

	HandNoiseName="${FIXFolder}/HandNoise.txt"
	log_Msg "HandNoiseName: ${HandNoiseName}"

	TrainingLabelsName="${FIXFolder}/hand_labels_noise.txt"
	log_Msg "TrainingLabelsName: ${TrainingLabelsName}"

	# Retrieve number of ICAs
	NumICAs=`${FSLDIR}/bin/fslval ${ICAFolder}/melodic_oIC.nii.gz dim4`
	log_Msg "NumICAs: ${NumICAs}"

	echo "merging classifications start"

	list_file_to_lookup "${OriginalFixSignal}" orig_signal
	list_file_to_lookup "${OriginalFixNoise}" orig_noise

	list_file_to_lookup "${ReclassifyAsSignal}" reclass_signal
	list_file_to_lookup "${ReclassifyAsNoise}" reclass_noise

	fail=""
	hand_signal=""
	hand_noise=""
	training_labels=""
	for ((i = 1; i <= NumICAs; ++i))
	do
		if [[ ${reclass_signal[$i]} || (${orig_signal[$i]} && ! ${reclass_noise[$i]}) ]]
		then
			if [[ "$hand_signal" ]]
			then
				hand_signal+=" $i"
			else
				hand_signal="$i"
			fi
		else
			if [[ "$hand_noise" ]]
			then
				hand_noise+=" $i"
				training_labels+=", $i"
			else
				hand_noise="$i"
				training_labels+="$i"
			fi
		fi
		#error checking
		if [[ ${reclass_noise[$i]} && ${reclass_signal[$i]} ]]
		then
			echo "Duplicate Component Error with Manual Classification on ICA: $i"
			fail=1
		fi
		if [[ ! (${orig_noise[$i]} || ${orig_signal[$i]}) ]]
		then
			echo "Missing Component Error with Automatic Classification on ICA: $i"
			fail=1
		fi
		if [[ ${orig_noise[$i]} && ${orig_signal[$i]} ]]
		then
			echo "Duplicate Component Error with Automatic Classification on ICA: $i"
			fail=1
		fi
		#the hand check from the matlab version can't be tripped here without the above code being wrong
	done

	if [[ $fail ]]
	then
		log_Err_Abort "Sanity checks on input files failed"
	fi

	echo "$hand_signal" > "${HandSignalName}"
	echo "$hand_noise" > "${HandNoiseName}"
	echo "[$training_labels]" > "${TrainingLabelsName}"

	echo "merging classifications complete"
}

# ------------------------------------------------------------------------------
#  "Global" processing - everything above here should be in a function
# ------------------------------------------------------------------------------

set -e # If any command exits with non-zero value, this script exits

# Set global variables from environment variables
g_script_name=`basename ${0}`

# Verify that HCPPIPEDIR environment variable is set
if [ -z "${HCPPIPEDIR}" ]; then
	echo "${g_script_name}: ABORTING: HCPPIPEDIR environment variable must be set"
	exit 1
fi

# Load function libraries
source "${HCPPIPEDIR}/global/scripts/log.shlib" # Logging related functions
source "${HCPPIPEDIR}/global/scripts/fsl_version.shlib" # Function for getting FSL version
log_Msg "HCPPIPEDIR: ${HCPPIPEDIR}"

# Verify any other needed environment variables are set
log_Check_Env_Var FSLDIR

# Invoke the main to get things started
main $@



  


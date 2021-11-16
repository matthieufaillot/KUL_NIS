#!/bin/bash
# Bash shell script to prepare fMRI/DTI results for Brainlab Elements Server
#
# Requires Mrtrix3, Karawun
#
# @ Stefan Sunaert - UZ/KUL - stefan.sunaert@uzleuven.be
# 12/11/2021
version="0.3"

kul_main_dir=`dirname "$0"`
source $kul_main_dir/KUL_main_functions.sh
cwd=$(pwd)

# FUNCTIONS --------------

# function Usage
function Usage {

cat <<USAGE

`basename $0` is a script that prepares data for input into Brainlab Elements

Usage:

  `basename $0` <OPT_ARGS>

Example:

  `basename $0` -p JohnDoe 

Required arguments:

     -p:  participant name

Optional arguments:

     -t:  processing type
        type 1: (DEFAULT) prepare for tumor patient
        type 2: prepare for a DBS patient
     -v:  show output from commands

USAGE

	exit 1
}


# CHECK COMMAND LINE OPTIONS -------------
#
# Set defaults
silent=1 # default if option -v is not given
ncpu=15
type=1

# Set required options
p_flag=0

if [ "$#" -lt 1 ]; then
	Usage >&2
	exit 1

else

	while getopts "p:t:v" OPT; do

		case $OPT in
		p) #participant
			participant=$OPTARG
            p_flag=1
		;;
        t) #type
			type=$OPTARG
		;;
        v) #verbose
			silent=0
		;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			echo
			Usage >&2
			exit 1
		;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			echo
			Usage >&2
			exit 1
		;;
		esac

	done

fi

# check for required options
if [ $p_flag -eq 0 ] ; then
	echo
	echo "Option -p is required: give the BIDS name of the participant." >&2
	echo
	exit 2
fi

# MRTRIX and others verbose or not?
if [ $silent -eq 1 ] ; then
	export MRTRIX_QUIET=1
    str_silent=" > /dev/null 2>&1" 
    ants_verbose=0
fi


#----- functions

function KUL_karawun_get_tract {
    cp BIDS/derivatives/KUL_compute/sub-${participant}/FWT/sub-${participant}_TCKs_output/${tract_name_orig}_output/${tract_name_orig}_fin_BT_iFOD2.tck \
        Karawun/sub-${participant}/tck/${tract_name_final}.tck
    mrgrid BIDS/derivatives/KUL_compute/sub-${participant}/FWT/sub-${participant}_TCKs_output/${tract_name_orig}_output/${tract_name_orig}_fin_map_BT_iFOD2.nii.gz \
        regrid -template Karawun/sub-${participant}/T1w.nii.gz \
        - | mrcalc - ${tract_threshold} -gt ${tract_color} -mul \
        Karawun/sub-${participant}/labels/${tract_name_final}_center.nii.gz -force
}

function KUL_karawun_get_voi {
    mrgrid BIDS/derivatives/KUL_compute/sub-${participant}/FWT/sub-${participant}_VOIs/${tract_name_orig}_VOIs/${tract_name_orig}_incs1/${tract_name_orig}_incs1_map.nii.gz \
        regrid -template Karawun/sub-${participant}/T1w.nii.gz \
        - | mrcalc - ${voi_threshold} -gt ${voi_color} -mul \
        Karawun/sub-${participant}/labels/${voi_name_final}.nii.gz -force
}

#---- MAIN

mkdir -p Karawun/sub-${participant}/labels
mkdir -p Karawun/sub-${participant}/tck
mkdir -p Karawun/sub-${participant}/DICOM

mrcalc RESULTS/sub-${participant}/Anat/T1w.nii 100 -div Karawun/sub-${participant}/T1w.nii.gz -force

if [ $type -eq 1 ]; then

    tract_name_orig="OR_occlobe_LT"
    tract_name_final="Occiptal_Radition_Left"
    tract_color=2
    tract_threshold=20
    KUL_karawun_get_tract
    
    tract_name_orig="OR_occlobe_RT"
    tract_name_final="Occiptal_Radition_Right"
    tract_color=2
    tract_threshold=20
    KUL_karawun_get_tract

elif [ $type -eq 2 ]; then

    tract_name_orig="CSHP_LT"
    voi_name_final="DISTAL_STN_MOTOR_Left"
    voi_color=3
    voi_threshold=0.1
    KUL_karawun_get_voi

    tract_name_orig="CSHP_RT"
    voi_name_final="DISTAL_STN_MOTOR_Right"
    voi_color=3
    voi_threshold=0.1
    KUL_karawun_get_voi

    tract_name_orig="CSHP_LT"
    tract_name_final="CSHDP_Left"
    tract_color=2
    tract_threshold=20
    KUL_karawun_get_tract

    tract_name_orig="CSHP_RT"
    tract_name_final="CSHDP_Right"
    tract_color=2
    tract_threshold=20
    KUL_karawun_get_tract

    tract_name_orig="CST_LT"
    tract_name_final="CST_Left"
    tract_color=1
    tract_threshold=20
    KUL_karawun_get_tract

    tract_name_orig="CST_RT"
    tract_name_final="CST_Right"
    tract_color=1
    tract_threshold=20
    KUL_karawun_get_tract

fi

# give information
echo "See to it that the DICOM directory contains a single slice of the SmartBrain"
echo "Then copy into terminal: "
echo "conda activate KarawunEnv"
echo "importTractography -d Karawun/sub-${participant}/DICOM/*.dcm \
-o Karawun/sub-${participant}/sub-${participant}_for_elements \
-n Karawun/sub-${participant}/T1w.nii.gz \
-t Karawun/sub-${participant}/tck/*.tck \
-l Karawun/sub-${participant}/labels/*.gz"

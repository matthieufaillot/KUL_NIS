#!/bin/bash

# set -x

# Ahmed Radwan ahmed.radwan@kuleuven.be
# Stefan Sunaert  stefan.sunaert@kuleuven.be

# this script is in dev for S61759

# v 0.31 - dd 03/08/2020

# just an example if we still need to make it more quiet
# task="$(task_antsBET >/dev/null 2>&1)";


#####################################


## This version is made for single channel validation purposes 
# it is free of any tampering to add dice calucations or any 
# quality checks for validation purposes
# those were add in later versions of this script names confusingly
# so I just named this v1



v="0.32"
# change version when finished with dev to 1.0

# This script is meant to allow a decent recon-all/antsMALF output in the presence of a large brain lesion 
# It is not a final end-all solution but a rather crude and simplistic work around 
# The main idea is to replace the lesion with a hole and fill the hole with information from the normal hemisphere 
# maintains subject specificity and diseased hemisphere information but replaces lesion tissue with sham brain 
# should be followed by a loop calculating overlap between fake labels from sham brain with actual lesion 
#  To do: # 
# - This version shall be single channel based and will be used solely for validation
# - further dev in progress (25/02/2020)
# - improving brain extraction to improve segmentation - done
# - changing make images strategy - done
# - implementing Template use for large unilateral lesions - done
# - need to modify smoothed masks, so that the center is always 1 and smooth values are only at periphery
# - need to switch to hd-bet (if I can get it to run on MAC OS X)


# Description: (outdated)
# 1 - Denoise all inputs with ants in native space and save noise maps
# 2 - N4 bias field correction and save the bias image as bias1
# 3 - Affine reg T2/FLAIR to T1 
# 4 - Dual channel antsBET in native space, generate T2 brain, L_mask_bin, L_mask_binv and brain_mask_min_L
# 5 - Flip brains in native space + brain_mask_min_L and L_mask_binv and warp orig (antsRegSyN.sh -t a/s? to MNI)
# 6 - antsRegSyN.sh -t s flipped_T1 to orig_T1_in_MNI using brain_mask_min_L and fbrain_mask_min_L
# 7 - antsRegSyN.sh -t so output_step_6 to MNI using fbrain_mask_min_L
# 8 - make T1 and T2 hole and fill with patch from fT1 and fT2 (output_step_7) all in MNI space
# 9 - antsRegSyN.sh -t so output_step_8 to orig_T1 in MNI (using inverse warp from step_6 for the unflipped ims)
# 10 - dual channel antsAtroposN4.sh with -r [0.2,1,1,1] and -w 0.5 (atropos1)
# 11 - Warp output_step_9 to (maybe a bilateral healthy brain crude scenario or the original - lesion included - brain)
# 12 - dual channel antsAtroposN4.sh with -r [0.2,1,1,1] and -w 0.1 (atropos2) using brain_mask_min_L
# 13 - Apply warps from step 11 to out_step_10 
# 14 - replace lesion patch from Atropos2 maps with Atropos1 patches
# 15 - Run for loop for modalities to populate lesion patch with mean intensity values per tissue type
# 16 - Add noise and bias (should sprinkle in one more denoising and bias)
# 17 - run recon-all/antsJLF and calculate the lesion overlap with tissue types, make report, quit.

# will generate better RL and priors for the new MNI HRT1 template from FS (running it now 11/08/2019 @ 13:23)

# ----------------------------------- MAIN --------------------------------------------- 
# this script uses "preprocessing control", i.e. if some steps are already processed it will skip these

kul_lesion_dir=`dirname "$0"`
script=`basename "$0"`
# source $kul_main_dir/KUL_main_functions.sh
cwd=($(pwd))

# FUNCTIONS --------------

# function Usage
function Usage {

cat <<USAGE

`basename $0` preps structural images with lesions and runs recon-all.

Usage:

    `basename $0` -p subject <OPT_ARGS> -l <OPT_ARGS> -z <OPT_ARGS> -b 
  
    or
  
    `basename $0` -p subject <OPT_ARGS> -a <OPT_ARGS> -b <OPT_ARGS> -c <OPT_ARGS> -l <OPT_ARGS> -z <OPT_ARGS>  
  
Examples:

    `basename $0` -p pat001 -b -n 6 -l /fullpath/lesion_T1w.nii.gz -z T1 -o /fullpath/output
	

Purpose:

    The purpose of this workflow is to generate a lesion filled image, with healthy looking synthetic tissue in place of the lesion
    Essentially excising the lesion and grafting over the brain tissue defect in the MR image space

How to use:

    - You need to use the cook_template_4VBG script once for you study - if you have only 1 scanner
    - cook_template_4VBG requires two brains with unilateral lesions on opposing sides
    - it is meant to facilitate the grafting process and minimize intensity differences
    - You need a high resolution T1 WI and a lesion mask in the same space for VBG to run
    - If you end up with an empty image, it is possible you have mismatch between the T1 and lesion mask


Required arguments:

    -p:  BIDS participant name (anonymised name of the subject without the "sub-" prefix)
    -b:  if data is in BIDS
    -l:  full path and file name to lesion mask file per session
    -z:  space of the lesion mask used (only T1 supported in this version)
    -a:  Input precontrast T1WIs


Optional arguments:

    -s:  session (of the participant)
    -t:  Use the VBG template to derive the fill patch (if set to 1, template tissue is used alongside native tissue to make the lesion fill)
    -E:  Treat as an extra-axial lesion (skip VBG bulk, fill lesion patch with 0s, run FS and subsequent steps)
    -F:  Run Freesurfer recon-all, generate aparc+aseg + lesion and lesion report
    -P:  In case of pediatric patients - use pediatric template (NKI_under_10 in MNI)
    -m:  full path to intermediate output dir
    -o:  full path to output dir (if not set reverts to default output ./lesion_wf_output)
    -n:  number of cpu for parallelisation (default is 6)
    -v:  show output from mrtrix commands
    -h:  prints help menu

Notes: 

    - You can use -b and the script will find your BIDS files automatically
    - If your data is not in BIDS, then use -a without -b
    - This version is for validation only.



USAGE

    exit 1
}


# CHECK COMMAND LINE OPTIONS -------------
# 
# Set defaults
# this works for ANTsX scripts and FS
ncpu=8


# Set required options
p_flag=0
b_flag=0
s_flag=0
l_flag=0
l_spaceflag=0
t1_flag=0
t_flag=0
o_flag=0
m_flag=0
n_flag=0
F_flag=0
E_flag=0
P_flag=0

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "p:a:l:z:s:o:m:n:bvhtFEP" OPT; do

        case $OPT in
        p) #subject
            p_flag=1
            subj=$OPTARG
        ;;
        b) #BIDS or not ?
            bids_flag=1
        ;;
        a) #T1 WIs
            t1_flag=1
			t1_orig=$OPTARG
        ;;
        s) #session
            s_flag=1
            ses=$OPTARG
        ;;
        l) #lesion_mask
            l_flag=1
            L_mask=$OPTARG
		;;
	    z) #lesion_mask
	        l_spaceflag=1
	        L_mask_space=$OPTARG	
	    ;;
	    m) #intermediate output
			m_flag=1
			wf_dir=$OPTARG		
        ;;
	    o) #output
			o_flag=1
			out_dir=$OPTARG		
        ;;
        t) #template flag
			t_flag=1	
        ;;
        F) #FS recon-all flag
			F_flag=1	
        ;;
        E) #Extra-axial flag
			E_flag=1	
        ;;
        P) #Extra-axial flag
			P_flag=1	
        ;;
        n) #parallel
			n_flag=1
            ncpu=$OPTARG
        ;;
        v) #verbose
            silent=0
        ;;
        h) #help
            Usage >&2
            exit 0
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

# deal with ncpu and itk ncpu

# itk default ncpu for antsRegistration
itk_ncpu="export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${ncpu}"
export $itk_ncpu
silent=1

# check for required inputs and define your workflow accordingly

srch_Lmask_str=($(basename ${L_mask}))
srch_Lmask_dir=($(dirname ${L_mask}))
srch_Lmask_o=($(find ${srch_Lmask_dir} -type f | grep  ${srch_Lmask_str}))

if [[ $p_flag -eq 0 ]] || [[ $l_flag -eq 0 ]] || [[ $l_spaceflag -eq 0 ]]; then
	
    echo
    echo "Inputs -p -lesion -lesion_space must be set." >&2
    echo
    exit 2
	
else

    if [[ -z "${srch_Lmask_o}" ]]; then

        echo
        echo " Incorrect Lesion mask, please check the file path and name "
        echo
        exit 2

    else
	
	    echo "Inputs are -p  ${subj}  -lesion  ${L_mask}  -lesion_space  ${L_mask_space}"
        
    fi
	
fi

	
if [[ "$bids_flag" -eq 1 ]] && [[ "$s_flag" -eq 0 ]]; then
		
	# bids flag defined but not session flag
    search_sessions=($(find ${cwd}/BIDS/sub-${subj} -type d | grep anat));
	num_sessions=${#search_sessions[@]};
	ses_long="";
	
	if [[ "$num_sessions" -eq 1 ]]; then 
			
		echo " we have one session in the BIDS dir, this is good."
			
		# now we need to search for the images
		# then also find which modalities are available and set wf accordingly
			
		search_T1=($(find $search_sessions -type f | grep T1w.nii.gz));
		# search_T2=($(find $search_sessions -type f | grep T2w.nii.gz));
		# search_FLAIR=($(find $search_sessions -type f | grep FLAIR.nii.gz));
			
		if [[ $search_T1 ]]; then
				
			T1_orig=$search_T1
			echo " We found T1 WIs " $T1_orig
				
		else
				
			echo " no T1 WIs found in BIDS dir, exiting"
			exit 2
				
		fi
			
	else 
			
		echo " There is a problem with sessions in BIDS dir. "
		echo " Please double check your data structure &/or specify one session with -s if you have multiple ones. "
		exit 2
			
	fi
		
elif [[ "$bids_flag" -eq 1 ]] && [[ "$s_flag" -eq 1 ]]; then
		
	# this is fine
    ses_string="${cwd}/BIDS/sub-${subj}_ses-${ses}"
	search_sessions=($(find ${ses_string} -type d | grep anat));
	num_sessions=1;
	ses_long=_ses-0${num_sessions};
		
	if [[ "$num_sessions" -eq 1 ]]; then 
			
		echo " One session " $ses " specified in BIDS dir, good."
		# now we need to search for the images
		# here we also need to search for the images
		# then also find which modalities are available and set wf accordingly
		
		search_T1=($(find $search_sessions -type f | grep T1w.nii.gz));
		# search_T2=($(find $search_sessions -type f | grep T2w.nii.gz));
		# search_FLAIR=($(find $search_sessions -type f | grep flair.nii.gz));
		
		if [[ "$search_T1" ]]; then
			
			T1_orig=$search_T1;

			echo " We found T1 WIs " $T1_orig
			
		else
			
			echo " no T1 WIs found in BIDS dir, exiting "

			exit 2
			
		fi

    fi


elif [[ "$bids_flag" -eq 0 ]] && [[ "$s_flag" -eq 0 ]]; then

	# this is fine if T1 and T2 and/or flair are set
	# find which ones are set and define wf accordingly
    num_sessions=1;
    ses_long="";
		
	if [[ "$t1_flag" ]]; then
			
		T1_orig=$t1_orig

        echo " T1 images provided as ${t1_orig} "
		
    else

        echo " No T1 WIs specified, exiting. "

		exit 2
			
	fi
		
		
elif [[ "$bids_flag" -eq 0 ]] && [[ "$s_flag" -eq 1 ]]; then
			
	echo " Wrong optional arguments, we cant have sessions without BIDS, exiting."
    
	exit 2
		
fi

# set this manually for debugging
function_path=($(which KUL_VBG.sh | rev | cut -d"/" -f2- | rev))
mrtrix_path=($(which mrmath | rev | cut -d"/" -f3- | rev))

if [[  -z  ${function_path}  ]]; then

    echo "update function path to reflect funciton name line 388"
    exit 2

else

    echo " VBG lives in ${function_path} "

fi
#  the primary image is the noncontrast T1

prim=${T1_orig}

# this if loop will quit the script if the T1 is not found

if [[ -z "${T1_orig}" ]]; then

    echo
    echo " Incorrect T1 input, please check the file path and name "
    echo
    exit 2

else

    echo "Inputs are -p  ${subj}  -T1 ${T1_orig}  -lesion  ${L_mask}  -lesion_space  ${L_mask_space}"
    
fi


# REST OF SETTINGS ---

# timestamp
start_t=$(date +%s)

# Some parallelisation

if [[ "$n_flag" -eq 0 ]]; then

	ncpu=8

	echo " -n flag not set, using default 8 threads. "

else

	echo " -n flag set, using " ${ncpu} " threads."

fi

FSLPARALLEL=$ncpu; export FSLPARALLEL
OMP_NUM_THREADS=$ncpu; export OMP_NUM_THREADS

d=$(date "+%Y-%m-%d_%H-%M-%S");


# handle the dirs

cd $cwd

long_bids_subj="${search_sessions}"

echo $long_bids_subj

bids_subj=${long_bids_subj%anat}

echo $bids_subj

lesion_wf="${cwd}/lesion_wf"

# output

if [[ "$o_flag" -eq 1 ]]; then
	
    output_m="${out_dir}"

    output_d="${output_m}/sub-${subj}${ses_long}"

else

	output_d="${lesion_wf}/output_LWF/sub-${subj}${ses_long}"

fi

# intermediate folder

if [[ "$m_flag" -eq 1 ]]; then

	preproc_m="${wf_dir}"

    preproc="${preproc_m}/sub-${subj}${ses_long}"

else

	preproc="${lesion_wf}/proc_LWF/sub-${subj}${ses_long}"

fi

# echo $lesion_wf

ROIs="${output_d}/sub-${subj}${ses_long}/ROIs"
	
overlap="${output_d}/sub-${subj}${ses_long}/overlap"

# make your dirs

mkdir -p ${preproc_m} >/dev/null 2>&1

mkdir -p ${output_m} >/dev/null 2>&1

mkdir -p ${preproc} >/dev/null 2>&1

mkdir -p ${output_d} >/dev/null 2>&1

mkdir -p ${ROIs} >/dev/null 2>&1

mkdir -p ${overlap} >/dev/null 2>&1

# make your log file

prep_log="${preproc}/prep_log_${d}.txt";

if [[ ! -f ${prep_log} ]] ; then

    touch ${prep_log}

else

    echo "${prep_log} already created"

fi

echo "KUL_lesion_WF @ ${d} with parent pid $$ "

# --- MAIN ----------------
# Start with your Vars for Part 1

# naming strings

    str_pp="${preproc}/sub-${subj}${ses_long}"

    str_op="${output_d}/sub-${subj}${ses_long}"

    str_overlap="${overlap}/sub-${subj}${ses_long}"

# Template stuff

# check which template to use based on
# is this a pediatric or adult brain and whether we use donor tissue or not

if [[ "${P_flag}" -eq 1 ]] && [[ "${t_flag}" -eq 0 ]]; then

    echo "Working with default pediatric template and priors"

    MNI_T1="${function_path}/atlasses/Templates/NKI10u_T1.nii.gz"

    MNI_T1_brain="${function_path}/atlasses/Templates/NKI10u_brain.nii.gz"

    MNI_brain_mask="${function_path}/atlasses/Templates/NKI10u_brain_mask.nii.gz"

    new_priors="${function_path}/atlasses/Templates/priors/NKI10U_Prior_%d.nii.gz"

elif [[ "${P_flag}" -eq 1 ]] && [[ "${t_flag}" -eq 1 ]]; then

    echo "Working with cooked template template and priors"

    MNI_T1="${function_path}/atlasses/Templates/VBG_T1_temp_ped.nii.gz"

    MNI_T1_brain="${function_path}/atlasses/Templates/VBG_T1_temp_ped_brain.nii.gz"

    MNI_brain_mask="${function_path}/atlasses/Templates/NKI10u_brain_mask.nii.gz"

    new_priors="${function_path}/atlasses/Templates/priors/VBG_ped_T_Prior_%d.nii.gz"

elif [[ "${P_flag}" -eq 0 ]] && [[ "${t_flag}" -eq 1 ]]; then

    echo "Working with cooked adult template and priors"

    MNI_T1="${function_path}/atlasses/Templates/VBG_T1_temp.nii.gz"

    MNI_T1_brain="${function_path}/atlasses/Templates/VBG_T1_temp_brain.nii.gz"

    MNI_brain_mask="${function_path}/atlasses/Templates/HR_T1_MNI_brain_mask.nii.gz"

    new_priors="${function_path}/atlasses/Templates/priors/VBG_adult_T_Prior_%d.nii.gz"

elif [[ "${P_flag}" -eq 0 ]] && [[ "${t_flag}" -eq 0 ]]; then

    echo "Working with default adult template and priors"

    MNI_T1="${function_path}/atlasses/Templates/HR_T1_MNI.nii.gz"

    MNI_T1_brain="${function_path}/atlasses/Templates/HR_T1_MNI_brain.nii.gz"

    MNI_brain_mask="${function_path}/atlasses/Templates/HR_T1_MNI_brain_mask.nii.gz"

    new_priors="${function_path}/atlasses/Templates/priors/HRT1_Prior_%d.nii.gz"

fi

    # should be changed to VBG templates

    MNI2_in_T1="${str_pp}_T1_brain_inMNI2_InverseWarped.nii.gz"

    MNI2_in_T1_hm="${str_pp}_T1_brain_inMNI2_InverseWarped_HistMatch.nii.gz"

    MNI_r="${function_path}/atlasses/Templates/Rt_hemi_mask.nii.gz"

    MNI_l="${function_path}/atlasses/Templates/Lt_hemi_mask.nii.gz"

    MNI_lw="${str_pp}_MNI_L_insubjT1_inMNI1.nii.gz"

    MNI_lwr="${str_pp}_MNI_L_insubjT1_inMNI1r.nii.gz"

    MNI_rwr="${str_pp}_MNI_R_insubjT1_inMNI1r.nii.gz"

    L_hemi_mask="${str_pp}_L_hemi_mask_bin.nii.gz"

    H_hemi_mask="${str_pp}_H_hemi_mask_bin.nii.gz"

    L_hemi_mask_binv="${str_pp}_L_hemi_mask_binv.nii.gz"

    H_hemi_mask_binv="${str_pp}_H_hemi_mask_binv.nii.gz"

    # CSF+GMC+GMB+WM  and the rest

    tmp_s2T1_nCSFGMC="${str_pp}_tmp_s2T1_nCSFGMC.nii.gz"

    tmp_s2T1_nCSFGMCB="${str_pp}_tmp_s2T1_nCSFGMCB.nii.gz"

    tmp_s2T1_nCSFGMCBWM="${str_pp}_tmp_s2T1_nCSFGMCBWM.nii.gz"

    tmp_s2T1_nCSFGMCBWMr="${str_pp}_tmp_s2T1_nCSFGMCBWMr.nii.gz"

    tmp_s2T1_CSFGMCBWM="${str_pp}_tmp_s2T1_CSFGMCBWM.nii.gz"

    MNI2_in_T1_scaled="${str_pp}_MNI_brain_IW_scaled.nii.gz"

    tissues=("CSF" "GMC" "GMBG" "WM");

    priors_str="${new_priors::${#new_priors}-9}*.nii.gz"

    priors_array=($(ls ${priors_str}))

    if [[ -z ${priors_array} ]]; then 

        echo " priors are not found!"
        exit 2
    
    else

    
        echo "priors are ${priors_array}"

    fi
    
    # arrays

    declare -a Atropos1_posts

    declare -a Atropos2_posts

    # need also to declare tpm arrays

    declare -a atropos1_tpms_Lfill

    declare -a atropos2_tpms_filled

    declare -a atropos2_tpms_filled_GLC

    declare -a atropos2_tpms_filled_GLCbinv

    declare -a atropos2_tpms_punched

    declare -a NP_arr_rs

    declare -a NP_arr_rs_bin

    declare -a NP_arr_rs_binv

    declare -a Atropos2_posts_bin

    declare -a Atropos1_posts_bin

    declare -a T1_ntiss_At2masked

    declare -a nMNI2_inT1_ntiss_sc2T1MNI1

    declare -a MNI2_inT1_ntiss

    declare -a Atropos2_Int_finder

    declare -a R_nTiss_Norm_mean

    declare -a R_nTiss_Int_map_norm

    declare -a Atropos1b_ntiss_map

    declare -a A1_nTiss_Norm_mean

    declare -a A1_nTiss_Int_scaled

    declare -a A1_nTiss_Int_scaled_fill

    declare -a R_nTiss_map_filled


# input variables

    # lesion stuff

    Lmask_o=$L_mask

    L_mask_reori="${str_pp}_L_mask_reori.nii.gz"

    L_O_binv="${str_pp}_L_mask_reori_binv.nii.gz"

    Lmask_bin="${str_pp}_L_mask_orig_bin.nii.gz"

    Lmask_in_T1="${str_pp}_L_mask_in_T1.nii.gz"

    Lmask_in_T1_bin="${str_pp}_L_mask_in_T1_bin.nii.gz"

    Lmask_in_T1_binv="${str_pp}_L_mask_in_T1_binv.nii.gz"

    Lmask_bin_s3="${str_pp}_Lmask_in_T1_bins3.nii.gz"

    Lmask_binv_s3="${str_pp}_Lmask_in_T1_binvs3.nii.gz"

    brain_mask_minL="${str_pp}_antsBET_BrainMask_min_L.nii.gz"

    brain_mask_minL_inMNI1="${str_pp}_brainmask_minL_inMNI1.nii.gz"

    brain_mask_minL_inMNI2="${str_pp}_brainmask_minL_inMNI2.nii.gz"

    brain_mask_minL_atropos2="${str_pp}_brainmask_minL_atropos2.nii.gz"

    Lmask_bin_inMNI1="${str_pp}_Lmask_bin_inMNI1.nii.gz"

    Lmask_binv_inMNI1="${str_pp}_Lmask_binv_inMNI1.nii.gz"

    Lmask_bin_inMNI1_s3="${str_pp}_Lmask_bin_s3_inMNI1.nii.gz"

    Lmask_bin_inMNI1_dilx2="${str_pp}_Lmask_bin_inMNI1_dilmx2.nii.gz"

    Lmask_binv_inMNI1_dilx2="${str_pp}_Lmask_binv_inMNI1_dilmx2.nii.gz"

    Lmask_binv_inMNI1_s3="${str_pp}_Lmask_binv_s3_inMNI1.nii.gz"

    Lmask_bin_inMNI2_s3="${str_pp}_Lmask_bin_s3_inMNI2.nii.gz"

    Lmask_binv_inMNI2_s3="${str_pp}_Lmask_binv_s3_inMNI2.nii.gz"

    Lmask_bin_inMNI2="${str_pp}_Lmask_bin_inMNI2.nii.gz"

    fbrain_mask_minL_inMNI1="${str_pp}_fbrainmask_minL_inMNI1.nii.gz"

    L_fill_T1="${str_pp}_T1_Lfill_inMNI2.nii.gz"

    nat_T1_filled1="${str_pp}_T1inMNI2_fill1.nii.gz"

    stitched_T1_temp="${str_pp}_stitched_T1_brain_temp.nii.gz"

    stitched_T1_nat="${str_pp}_stitched_T1_brain_nat.nii.gz"

    stitched_T1_nat_innat="${str_pp}_stitched_T1_brain_nat_bk2nat.nii.gz"

    stitched_T1_temp_innat="${str_pp}_stitched_T1_brain_temp_bk2nat.nii.gz"

    stitched_T1="${str_pp}_stitched_T1_brain.nii.gz"

    T1_bk2nat1_str="${str_pp}_T1_brain_bk2anat1_"

    Temp_L_hemi="${str_pp}_Temp_L_hemi_filler.nii.gz"

    Temp_L_fill_T1="${str_pp}_Temp_L_fill_T1.nii.gz"

    Temp_T1_bilfilled1="${str_pp}_T1_brain_Temp_bil_Lmask_filled1.nii.gz"

    Temp_bil_Lmask_fill1="${str_pp}_Temp_bil_Lmask_fill1.nii.gz"

    Temp_T1_filled1="${str_pp}_Temp_T1inMNI2_filled1.nii.gz"

    T1_filled_bk2nat1="${str_pp}_T1_brain_bk2anat1_InverseWarped.nii.gz"

    filled_segm_im="${str_pp}_atropos1_Segmentation_2nat.nii.gz"

    real_segm_im="${str_pp}_atropos2_Segmentation_2nat.nii.gz"

    Lfill_segm_im="${str_pp}_Lfill_segmentation_im.nii.gz"

    atropos2_segm_im_filled="${str_pp}_filled_atropos2_segmentation_im.nii.gz"

    atropos2_segm_im_filled_nat="${str_pp}_filled_atropos2_segmentation_im.nii.gz"

    lesion_left_overlap="${str_overlap}_L_lt_overlap.nii.gz"

    lesion_right_overlap="${str_overlap}_L_rt_overlap.nii.gz"

    smoothed_binLmask15="${str_pp}_smoothedLmaskbin15.nii.gz"

    smoothed_binvLmask15="${str_pp}_smoothedLmaskbinv15.nii.gz"

    # last lesion related vars (hopefully)

    L_mask_reori_scaled="${str_pp}_L_mask_reori_scaled99.nii.gz"

    bmc_minL_conn="${str_pp}_brain_mask_cleaned_minL_conn.nii.gz"

    bmc_minL_true="${str_pp}_brain_mask_cleaned_minL.nii.gz"

    L_mask_reori_ero1="${str_pp}_L_mask_reori_ero1.nii.gz"

    bmc_minL_ero1="${str_pp}_brain_mask_cleaned_minL_ero1.nii.gz"

    L_mask_reori_ero2="${str_pp}_L_mask_reori_ero2.nii.gz"

    bmc_minL_ero2="${str_pp}_brain_mask_cleaned_minL_ero2.nii.gz"

    # img vars for part 1 and 2

    T1_reori_mat="${str_pp}_T1_reori2std_matrix.mat"

    T1_reori_mat_inv="${str_pp}_T1_reori2std_matrix_inv.mat"

    T1_N4BFC="${str_pp}_T1_dn_bfc.nii.gz"

    T1_N4BFC_inMNI1="${str_pp}_T1_dn_bfc_INMNI1.nii.gz"

    T1_brain="${str_pp}_antsBET_BrainExtractionBrain.nii.gz"

    brain_mask="${str_pp}_antsBET_BrainExtractionMask.nii.gz"

    T1_inMNI_aff_str="${str_pp}_T1_inMNI_aff"

    T1_inMNI_aff="${str_pp}_T1_inMNI_aff_Warped.nii.gz"

    KULBETp="${str_pp}_atropos4BET"

    rough_mask="${str_pp}_rough_mask.nii.gz"

    rough_mask_minL="${str_pp}_rough_mask_minL.nii.gz"

    clean_mask_nat_binv="${str_pp}_clean_brain_mask_nat_binv.nii.gz"

    T1_brain_clean="${str_pp}_Brain_clean.nii.gz"

    MNI_bm_BET_innat="${str_pp}_MNI_BM_inNat.nii.gz"

    clean_mask_nat="${str_pp}_Brain_clean_mask.nii.gz"

    clean_BM_mgz="${str_pp}_Brain_clean_mask.mgz"

    hdbet_str="${str_pp}_Brain_clean"

    BET_mask_s2="${str_pp}_antsBET_Mask_s2.nii.gz"

    BET_mask_binvs2="${str_pp}_antsBET_Mask_binv_s2.nii.gz"

    T1_skull="${str_pp}_T1_skull.nii.gz"

    T1_brMNI1_str="${str_pp}_T1_brain_inMNI1_"

    T1_brain_inMNI1="${str_pp}_T1_brain_inMNI1_Warped.nii.gz"

    T1_noise_inMNI1="${str_pp}_T1_noise_inMNI1.nii.gz"

    fT1_noise_inMNI1="${str_pp}_fT1_noise_inMNI1.nii.gz"

    T1_noise_H_hemi="${str_pp}_T1_noise_Hhemi_inMNI1.nii.gz"
    
    stitched_noise_MNI1="${str_pp}_T1_stitched_noise_inMNI1.nii.gz"

    stitched_noise_nat="${str_pp}_T1_stitched_noise_nat.nii.gz"

    T1_brMNI2_str="${str_pp}_T1_brain_inMNI2_"
    
    T1_brain_inMNI2="${str_pp}_T1_brain_inMNI2_Warped.nii.gz"

    fT1brain_inMNI1="${str_pp}_fT1_brain_inMNI1_Warped.nii.gz"

    fT1_brMNI2_str="${str_pp}_fT1_brain_inMNI2_"

    fT1brain_inMNI2="${str_pp}_fT1_brain_inMNI2_Warped.nii.gz"

    brain_mask_inMNI1="${str_pp}_brain_mask_inMNI1.nii.gz"

    # MNI_brain_mask_in_nat="${str_pp}_MNI_brain_mask_in_nat.nii.gz"

    T1_sti2fil_str="${str_pp}_stitchT12filled_brain_"

    T1fill2MNI1minL_str="${str_pp}_filledT12MNI1_brain_"

    T1_sti2fill_brain="${str_pp}_stitchT12filled_brain_Warped.nii.gz"

    T1fill2MNI1minL_brain="${str_pp}_filledT12MNI1_brain_Warped.nii.gz"

    stiT1_synthT1_diff="${str_pp}_stitchT1synthT1_diff_map.nii.gz"

    filledT1_synthT1_diff="${str_pp}_filledT1synthT1_diff_map.nii.gz"

    T1_fin_Lfill="${str_pp}_T1_finL_fill.nii.gz"

    T1_fin_filled="${str_pp}_T1_finL_filled.nii.gz"

    T1_nat_filled_out="${str_op}_T1_stdOri_filled.nii.gz"

    T1_nat_fout_wskull="${str_op}_T1_stdOri_filld_wskull.nii.gz"

    T1_nat_fout_wN_skull="${str_op}_T1_stdORI_filld_wN_skull.nii.gz"

    # vars for final output in input space
    
    T1_4_FS="${str_op}_T1_nat_filled.nii.gz"

    T1_Brain_4_FS="${str_op}_T1_nat_filled_brain.nii.gz"

    T1_BM_4_FS="${str_op}_T1_nat_filled_mask.nii.gz"

    # img vars for part 2

    T1_H_hemi="${str_pp}_T1_H_hemi.nii.gz"

    fT1_H_hemi="${str_pp}_fT1_H_hemi.nii.gz"

    # img vars for make ims loops

    MNI2_in_T1_linsc_norm="${str_pp}_MNI2_inT1_linsc_norm.nii.gz"
    
    atropos1_brain_norm="${str_pp}_Atropos1_brain_norm.nii.gz"

    T1b_inMNI1_pN_sc2st2f="${str_pp}_T1b_inMNI1_pN_sc2_st2fill.nii.gz"
    
    T1b_inMNI1_punched="${str_pp}_T1brain_inMNI1_punched.nii.gz"
    
    T1b_inMNI1_p_norm="${str_pp}_T1brain_inMNI1_punched_norm.nii.gz"

    #

# workflow markers for processing control

search_wf_mark1=($(find ${preproc} -type f | grep "${brain_mask_inMNI1}"));

srch_preprocp1=($(find ${preproc} -type f | grep "${T1_N4BFC}"));

srch_antsBET=($(find ${preproc} -type f | grep "${T1_brain_clean}"));

T1brain2MNI1=($(find ${preproc} -type f | grep "${T1_brain_inMNI1}"));

T1brain2MNI2=($(find ${preproc} -type f | grep "${T1_brain_inMNI2}"));

fT1_brain_2MNI2=($(find ${preproc} -type f | grep "${fT1brain_inMNI2}"));

sch_brnmsk_minL=($(find ${preproc} -type f | grep "${brain_mask_minL}"));

search_wf_mark2=($(find ${preproc} -type f | grep "${fbrain_mask_minL_inMNI1}"));

srch_Lmask_pt2=($(find ${preproc} -type f | grep "_atropos1_Segmentation.nii.gz")); # same as Atropos1 marker for now

stitch2fill_mark=($(find ${preproc} -type f | grep "${T1_sti2fil_str}Warped.nii.gz"));

fill2MNI1mniL_mark=($(find ${preproc} -type f | grep "${T1fill2MNI1minL_str}Warped.nii.gz"));

Atropos1_wf_mark=($(find ${preproc} -type f | grep "_atropos1_Segmentation.nii.gz"));

srch_bk2anat1_mark=($(find ${preproc} -type f | grep "${T1_filled_bk2nat1}"));

Atropos2_wf_mark=($(find ${preproc} -type f | grep "_atropos2_Segmentation.nii.gz"));

srch_postAtropos2=($(find ${preproc} -type f | grep "_atropos2_SegmentationPosterior2_clean_bk2nat1.nii.gz"));

srch_make_images=($(find ${preproc} -type f | grep "${T1_BM_4_FS}")); # search make images will run at the end if the BM for FS is not found

# Misc subfuctions

# execute function (maybe add if loop for if silent=0)

function task_exec {

    echo "  " >> ${prep_log} 
    
    echo ${task_in} >> ${prep_log} 

    echo " Started @ $(date "+%Y-%m-%d_%H-%M-%S")" >> ${prep_log} 

    eval ${task_in} >> ${prep_log} 2>&1 &

    echo " pid = $! basicPID = $$ " >> ${prep_log}

    wait ${pid}

    sleep 5

    if [ $? -eq 0 ]; then
        echo Success >> ${prep_log}
    else
        echo Fail >> ${prep_log}

        exit 1
    fi

    echo " Finished @  $(date "+%Y-%m-%d_%H-%M-%S")" >> ${prep_log} 

    echo "  " >> ${prep_log} 

    unset task_in

}

# functions for denoising and N4BFC

function KUL_denoise_im {

    task_in="DenoiseImage -d 3 -s 1 -n ${dn_model} -i ${input} -o [${output},${noise}] ${mask} -v 1"

    task_exec

}

function KUL_N4BFC {

    task_in="N4BiasFieldCorrection -d 3 -s 3 -i ${input} -o [${output},${bias}] ${mask} -v 1"

    task_exec

}

# functions for basic antsRegSyN calls

# not using SyNQuick anymore
# default Affine antsRegSyNQuick call
# function KUL_antsRegSyNQ_Def {

#     task_in="antsRegistrationSyNQuick.sh -d 3 -f ${fix_im} -m ${mov_im} -o ${output} -n ${ncpu} -j 1 -t ${transform} ${mask}"

#     task_exec

# }

# default Affine antsRegSyN call
function KUL_antsRegSyN_Def {

    task_in="antsRegistrationSyN.sh -d 3 -f ${fix_im} -m ${mov_im} -o ${output} -n ${ncpu} -j 1 -t ${transform} ${mask}"

    task_exec

}

# functions for ANTsBET

# adding new ANTsBET workflow
# actually, we could use hd-bet cpu version if it is installed also
# make a little if loop testing if hd-bet is alive

function KUL_antsBETp {

    # need to try this out!

    # if you want to use the modified ANTs based BET approach and not HD-BET
    # just comment out the if loop and hd-bet condition (be sure to get the if, else and fi lines)

    task_in="fslreorient2std ${Lmask_o} ${L_mask_reori}"

    task_exec

    if [[ $(which hd-bet) ]]; then

        hd_bet_flag=1

        echo "hd-bet is present, will use this for brain extraction" >> ${prep_log}

        # echo "sourcing ptc conda virtual env, if yours is named differently please edit lines 822 823 " >> ${prep_log}

        task_in="source /anaconda3/bin/activate ptc && hd-bet -i ${prim_in} -o ${output} -tta 0 -mode fast -s 1 -device cpu"

        # task_exec

        # task_in="hd-bet -i ${prim_in} -o ${output}"

        task_exec

    else

        echo "hd-bet is not found, resorting to ANTs based BET" >> ${prep_log}

        task_in="mrthreshold -force -nthreads ${ncpu} -percentile 55 ${prim_in} ${rough_mask} -force -nthreads ${ncpu} && fslmaths ${L_mask_reori} -binv -mul ${rough_mask} ${rough_mask_minL}"

        task_exec

        task_in="antsBrainExtraction.sh -d 3 -a ${prim_in} -e ${MNI_T1} -m ${MNI_brain_mask} -f ${rough_mask_minL} -u 1 -k 1 -o ${output}_"

        task_exec

        # use the inverse priors warp from antsbet to get MNI_brain_mask to T1 space and apply it to the brain

        task_in="WarpImageMultiTransform 3 ${MNI_brain_mask} ${MNI_bm_BET_innat} -R ${prim_in} -i ${output}_BrainExtractionPrior0GenericAffine.mat \
        ${output}_BrainExtractionPrior1InverseWarp.nii.gz"

        task_exec

        task_in="fslmaths ${MNI_bm_BET_innat} -thr 0.1 -bin -mul ${output}_BrainExtractionBrain.nii.gz -save ${T1_brain_clean} -bin ${clean_mask_nat}"

        task_exec

    fi

    # exit 2

}

# Dealing with the lesion mask part 1

function KUL_Lmask_part1 {

    # since we only operate in 1 space (unimodal) this if condition is useless and deprecated
    # substituting with E_flag coniditional arguments

    if [[ "${E_flag}" -eq 0 ]]; then

        # echo " Lesion mask is already in T1 space " >> ${prep_log}

        echo " Intra-axial lesion running VBG Lmask_pt1 workflow and subsequent steps" >> ${prep_log}

        # start by smoothing and thring the mask

        task_in="fslmaths ${L_mask_reori} -s 2 -thr 0.2 -bin -save ${Lmask_bin} -binv ${Lmask_in_T1_binv}"

        task_exec

        echo " Copying Lmask_bin_s2 file to Lmask_in_T1_bin " >> ${prep_log}

        cp ${Lmask_bin} ${Lmask_in_T1_bin}

        # subtract lesion from brain mask

        task_in="fslmaths ${clean_mask_nat} -mas ${Lmask_in_T1_binv} -mas ${clean_mask_nat} ${brain_mask_minL}"

        task_exec

    else

        echo " Extra-axial lesion running simplified VBG Lmask_pt1 workflow, FS and subsequent steps" >> ${prep_log}

        task_in="fslmaths ${L_mask_reori} -binv ${L_O_binv}"

        task_exec

    
    fi

}

#  determine lesion laterality and proceed accordingly
#  define all vars for this function

function KUL_Lmask_part2 {

    #############################################################
    # creating edited lesion masks
    # should add proc control to this section

    # now do the unflipped brain_mask_minL & L_mask

    mask_in="${Lmask_bin_inMNI1}"

    mask_out="${Lmask_bin_inMNI2}"

    ref="${MNI_T1_brain}"

    task_in="WarpImageMultiTransform 3 ${mask_in} ${mask_out} -R ${ref} ${T1_brMNI2_str}1Warp.nii.gz ${T1_brMNI2_str}0GenericAffine.mat --use-NN"

    task_exec

    unset mask_in mask_out

    task_in="fslmaths ${Lmask_bin_inMNI2} -bin -save ${Lmask_bin_inMNI2} -binv -mas ${brain_mask_inMNI1} ${brain_mask_minL_inMNI2}"

    task_exec

    # here we are really making the Lmask bigger
    # using -dilM x2 and -s 2 with a -thr 0.2 to avoid very low value voxels
    # actually will not be using dilx2 probably

    task_in="fslmaths ${Lmask_bin_inMNI1} -binv -mas ${brain_mask_inMNI1} -save ${Lmask_binv_inMNI1} -restart ${Lmask_bin_inMNI1} -dilM -dilM -save ${Lmask_bin_inMNI1_dilx2} \
    -s 2 -thr 0.2 -mas ${brain_mask_inMNI1} ${Lmask_bin_inMNI1_s3} && fslmaths ${brain_mask_inMNI1} -sub ${Lmask_bin_inMNI1_s3} -mas ${brain_mask_inMNI1} \
    ${Lmask_binv_inMNI1_s3} && fslmaths ${Lmask_bin_inMNI1_dilx2} -binv ${Lmask_binv_inMNI1_dilx2}"

    task_exec

    # task_in="fslmaths ${Lmask_bin_inMNI2} -dilM -dilM -save ${Lmask_bin_inMNI2_dilx2} -s 2 -thr 0.2 -mas ${brain_mask_inMNI1} ${Lmask_bin_inMNI2_s3} && fslmaths \
    # ${brain_mask_inMNI1} -sub ${Lmask_bin_inMNI2_s3} -mas ${brain_mask_inMNI1} ${Lmask_binv_inMNI2_s3} && fslmaths ${Lmask_bin_inMNI1_dilx2} -binv ${Lmask_binv_inMNI1_dilx2}"

    task_in="fslmaths ${Lmask_bin_inMNI2} -dilM -dilM -s 2 -thr 0.2 -mas ${brain_mask_inMNI1} ${Lmask_bin_inMNI2_s3} && fslmaths \
    ${brain_mask_inMNI1} -sub ${Lmask_bin_inMNI2_s3} -mas ${brain_mask_inMNI1} ${Lmask_binv_inMNI2_s3}"

    task_exec

    # task_in="fslmaths ${Lmask_in_T1_bin} -dilM -dilM -save ${Lmask_bin_dilx2} -s 2 -thr 0.2 -mas ${clean_mask_nat} ${Lmask_bin_s3} && fslmaths \
    # ${clean_mask_nat} -sub ${Lmask_bin_s3} -mas ${clean_mask_nat} ${Lmask_binv_s3} && fslmaths ${Lmask_bin_dilx2} -binv ${Lmask_binv_dilx2}"

    task_in="fslmaths ${Lmask_in_T1_bin} -dilM -dilM -s 2 -thr 0.2 -mas ${clean_mask_nat} ${Lmask_bin_s3} && fslmaths \
    ${clean_mask_nat} -sub ${Lmask_bin_s3} -mas ${clean_mask_nat} ${Lmask_binv_s3}"

    task_exec

    ######################################################################

    echo " Now running lesion magic part 2 "

    # determine lesion laterality
    # this is all happening in MNI space (between the first and second warped images)
    # apply warps to MNI_rl to match patient better
    # generate L_hemi+L_mask & H_hemi_minL_mask for unilateral lesions
    # use those to generate stitched image

    task_in="WarpImageMultiTransform 3 ${MNI_l} ${MNI_lw} -R ${T1_brain_inMNI1} -i ${T1_brMNI2_str}0GenericAffine.mat ${T1_brMNI2_str}1InverseWarp.nii.gz && fslmaths \
    ${MNI_lw} -thr 0.1 -bin -mas ${brain_mask_inMNI1} -save ${MNI_lwr} -binv -mas ${brain_mask_inMNI1} ${MNI_rwr}"

    task_exec

    task_in="fslmaths ${MNI_lwr} -mas ${Lmask_bin_inMNI1} ${lesion_left_overlap}"

    task_exec

    task_in="fslmaths ${MNI_rwr} -mas ${Lmask_bin_inMNI1} ${lesion_right_overlap}"

    task_exec

    Lmask_tot_v=$(mrstats -force -nthreads ${ncpu} ${Lmask_bin_inMNI1} -output count -quiet -ignorezero)

    overlap_left=$(mrstats -force -nthreads ${ncpu} ${lesion_left_overlap} -output count -quiet -ignorezero)

    overlap_right=$(mrstats -force -nthreads ${ncpu} ${lesion_right_overlap} -output count -quiet -ignorezero)

    L_ovLt_2_total=$(echo ${overlap_left}*100/${Lmask_tot_v} | bc)

    L_ovRt_2_total=$(echo ${overlap_right}*100/${Lmask_tot_v} | bc)

    echo " total lesion vox count ${Lmask_tot_v}" >> ${prep_log}

    echo " ov_left is ${overlap_left}" >> ${prep_log}

    echo " ov right is ${overlap_right}" >> ${prep_log}

    echo " ov_Lt to total is ${L_ovLt_2_total}" >> ${prep_log}

    echo " ov_Rt to total is ${L_ovRt_2_total}" >> ${prep_log}

    # we set a hard-coded threshold of 65, if unilat. then native heatlhy hemi is used
    # if bilateral by more than 35, template brain is used
    # # this needs to be modified, also need to include simple lesion per hemisphere overlap with percent to total hemi volume
    # this will enable us to use template or simple filling and derive mean values per tissue class form another source (as we are currently using the original images).
    # AR 09/02/2020
    # here we also need to make unilateral L masks, masked by hemi mask to overcome midline issue
    
    if [[ "${L_ovLt_2_total}" -gt 65 ]]; then

        # instead of simply copying
        # here we add the lesion patch to the L_hemi
        # task_in="cp ${MNI_l} ${L_hemi_mask}"

        task_in="fslmaths ${MNI_lwr} -add ${Lmask_bin_inMNI1} -bin -mas ${brain_mask_inMNI1} -save ${L_hemi_mask} -binv -mas ${brain_mask_inMNI1} ${L_hemi_mask_binv}"

        task_exec

        task_in="fslmaths ${MNI_rwr} -mas ${Lmask_binv_inMNI1} -bin -mas ${brain_mask_inMNI1} -save ${H_hemi_mask} -binv -mas ${brain_mask_inMNI1} ${H_hemi_mask_binv}"

        task_exec

        echo ${L_ovLt_2_total} >> ${prep_log}

        echo " This patient has a left sided or predominantly left sided lesion " >> ${prep_log}

        echo "${L_hemi_mask}" >> ${prep_log}

        echo "${H_hemi_mask}" >> ${prep_log}

        # for debugging will set this to -lt 10
        # should change it back to -gt 65 ( on the off chance you will need the bilateral condition, that is also been tested now)
        
    elif [[ "${L_ovRt_2_total}" -gt 65 ]]; then

        # task_in="cp ${MNI_r} ${L_hemi_mask}"

        task_in="fslmaths ${MNI_rwr} -add ${Lmask_bin_inMNI1} -bin -save ${L_hemi_mask} -binv ${L_hemi_mask_binv}"

        task_exec

        # task_in="cp ${MNI_l} ${H_hemi_mask}"

        task_in="fslmaths ${MNI_lwr} -add ${Lmask_bin_inMNI1} -bin -save ${H_hemi_mask} -binv ${H_hemi_mask_binv}"

        task_exec

        echo ${L_ovRt_2_total} >> ${prep_log}

        echo " This patient has a right sided or predominantly right sided lesion " >> ${prep_log}

        echo "${L_hemi_mask}" >> ${prep_log}

        echo "${H_hemi_mask}" >> ${prep_log}
        
    else 

        bilateral=1

        echo " This is a bilateral lesion with ${L_ovLt_2_total} left side and ${L_ovRt_2_total} right side, using Template T1 to derive lesion fill patch. "  >> ${prep_log}

        echo " note Atropos1 will use the filled images instead of the stitched ones "  >> ${prep_log}

    fi

    ################

    # for loop apply warp to each tissue tpm
    # first we scale the images then
    # histogram match within masks

    # mrstats to get the medians to match with mrcalc

    med_tmp=$(mrstats -quiet -nthreads ${ncpu} -output median -ignorezero -mask ${MNI_brain_mask} ${MNI2_in_T1})

    med_nat=$(mrstats -quiet -nthreads ${ncpu} -output median -ignorezero -mask ${brain_mask_minL_inMNI2} ${T1_brain_inMNI1})

    task_in="mrcalc -force -nthreads ${ncpu} ${med_nat} ${med_tmp} -divide ${MNI2_in_T1} -mult - | mrhistmatch linear - ${T1_brain_inMNI1} ${MNI2_in_T1_scaled} -force \
    -nthreads ${ncpu} -mask_target ${brain_mask_minL_inMNI2} -mask_input ${MNI_brain_mask}"

    task_exec

    # first we get the mean and normalized MNI2_inT1 after the scaling process done above

    MNI2_inT1_sc_mean=$(fslstats ${MNI2_in_T1_scaled} -M)

    task_in="fslmaths ${MNI2_in_T1_scaled} -div ${MNI2_inT1_sc_mean} ${MNI2_in_T1_linsc_norm}"

    task_exec

    # same for the T1brain in MNI1 image

    # before we get any values for the T1 we are trying to fill
    # we have to mask out the lesion

    # we get normalized target and source T1 images by dividing each by its mean

    task_in="fslmaths ${T1_brain_inMNI1} -mas ${Lmask_binv_inMNI1_dilx2} ${T1b_inMNI1_punched}"

    task_exec

    T1b_inMNI1p_mean=$(fslstats ${T1b_inMNI1_punched} -M)

    task_in="fslmaths ${T1b_inMNI1_punched} -div ${T1b_inMNI1p_mean} ${T1b_inMNI1_p_norm}"

    task_exec

    # for each tissue type
    # attempting to minimize intensity difference between donor and recipient images

    for ts in ${!tissues[@]}; do

        NP_arr_rs[$ts]="${str_pp}_atropos_${tissues[$ts]}_rs.nii.gz"

        NP_arr_rs_bin[$ts]="${str_pp}_atropos_${tissues[$ts]}_rs_bin.nii.gz"

        NP_arr_rs_binv[$ts]="${str_pp}_atropos_${tissues[$ts]}_rs_binv.nii.gz"

        Atropos2_posts_bin[$ts]="${str_pp}_atropos_${tissues[$ts]}_bin.nii.gz"

        # MNI2inT1_tiss_HM[$ts]="${str_pp}_atropos_${tissues[$ts]}_HM.nii.gz"

        # MNI2inT1_tiss_HMM[$ts]="${str_pp}_atropos_${tissues[$ts]}_HMM.nii.gz"

        MNI2_inT1_ntiss[$ts]="${str_pp}_MNItmp_${tissues[$ts]}_IM.nii.gz"

        T1_ntiss_At2masked[$ts]="${str_pp}_T1inMNI2_${tissues[$ts]}_IM.nii.gz"

        nMNI2_inT1_ntiss_sc2T1MNI1[$ts]="${str_pp}_nMNI2_inT1_linsc_norm_n${tissues[$ts]}.nii.gz"

        # warp the tissues to T1_brain_inMNI1 (first deformation)

        task_in="WarpImageMultiTransform 3 ${priors_array[$ts]} ${NP_arr_rs[$ts]} -R ${T1_brain_inMNI1} \
        -i ${T1_brMNI2_str}0GenericAffine.mat ${T1_brMNI2_str}1InverseWarp.nii.gz"

        task_exec

        # create the tissue masks and punch the lesion out of them

        task_in="fslmaths ${NP_arr_rs[$ts]} -thr 0.1 -mas ${MNI_brain_mask} -bin -save ${NP_arr_rs_bin[$ts]} -binv \
        ${NP_arr_rs_binv[$ts]} && mrthreshold -force -quiet -nthreads ${ncpu} -toppercent 5 ${Atropos2_posts[$ts]} - | mrcalc - ${brain_mask_minL_inMNI1} -mult 0.001 -gt ${Atropos2_posts_bin[$ts]}"

        task_exec

        # get tissue intensity maps from template

        task_in="fslmaths ${MNI2_in_T1_linsc_norm} -mas ${NP_arr_rs_bin[$ts]} ${MNI2_inT1_ntiss[$ts]} && fslmaths ${T1b_inMNI1_p_norm} -mas ${Atropos2_posts_bin[$ts]} \
        ${T1_ntiss_At2masked[$ts]}"

        task_exec

        T1_ntiss_At2m_mean=$(fslstats ${T1_ntiss_At2masked[$ts]} -M)

        MNI2_inT1_ntiss_mean=$(fslstats ${MNI2_inT1_ntiss[$ts]} -M)

        task_in="fslmaths ${MNI2_inT1_ntiss[$ts]} -div ${MNI2_inT1_ntiss_mean} -mul ${T1_ntiss_At2m_mean} ${nMNI2_inT1_ntiss_sc2T1MNI1[$ts]}"

        task_exec

    done

    # Sum up the tissues while masking in and out to minimize overlaps and holes
    # here we use ImageMath addtozero instead, to preserve a smooth interface between the tissues
    # the fslmaths step works well, but results a rather cartoon looking image
    # the order of images input to ImageMath addtozero makes a difference
    # we start with GMC as that is the most important class
    # add the CSF voxels, then add the GM-BG voxels, then finally the WM voxels

    CSF_max=$(mrstats -ignorezero -output max -quiet -force ${nMNI2_inT1_ntiss_sc2T1MNI1[0]})

    CSF_nmean=$(mrcalc `mrstats -ignorezero -output mean -quiet -force ${nMNI2_inT1_ntiss_sc2T1MNI1[1]}` 0.2 -mul -force -quiet)

    # fix for CSF signal in case a post contrast input is used

    if  (( $(bc <<<"${CSF_max} > ${CSF_nmean}") )); then

        echo " CSF signal is too high, is this a postcontrast scan ? correcting"

        echo " CSF signal is too high, is this a postcontrast scan ? correcting" >> ${prep_log}

        task_in="fslmaths ${MNI2_inT1_ntiss[0]} -div ${CSF_max} -mul ${CSF_nmean} ${str_pp}_nMNI2_inT1_linsc_norm_nCSF_cor.nii.gz"

        task_exec

        task_in="ImageMath 3 ${tmp_s2T1_nCSFGMC} addtozero ${nMNI2_inT1_ntiss_sc2T1MNI1[1]} ${str_pp}_nMNI2_inT1_linsc_norm_nCSF_cor.nii.gz && ImageMath 3 \
        ${tmp_s2T1_nCSFGMCB} addtozero ${tmp_s2T1_nCSFGMC} ${nMNI2_inT1_ntiss_sc2T1MNI1[2]} && ImageMath 3 ${tmp_s2T1_nCSFGMCBWM} addtozero ${tmp_s2T1_nCSFGMCB} ${nMNI2_inT1_ntiss_sc2T1MNI1[3]}"

        task_exec

    else

        task_in="ImageMath 3 ${tmp_s2T1_nCSFGMC} addtozero ${nMNI2_inT1_ntiss_sc2T1MNI1[1]} ${nMNI2_inT1_ntiss_sc2T1MNI1[0]} && ImageMath 3 \
        ${tmp_s2T1_nCSFGMCB} addtozero ${tmp_s2T1_nCSFGMC} ${nMNI2_inT1_ntiss_sc2T1MNI1[2]} && ImageMath 3 ${tmp_s2T1_nCSFGMCBWM} addtozero ${tmp_s2T1_nCSFGMCB} ${nMNI2_inT1_ntiss_sc2T1MNI1[3]}"

        task_exec


    fi

    
    task_in="ImageMath 3 ${tmp_s2T1_nCSFGMCBWMr} addtozero ${tmp_s2T1_nCSFGMCBWM} ${T1b_inMNI1_p_norm}"

    task_exec

    task_in="fslmaths ${tmp_s2T1_nCSFGMCBWMr} -mul ${T1b_inMNI1p_mean} ${tmp_s2T1_CSFGMCBWM}"

    task_exec

    ############

    # here we create the stitched and initial filled images
    # we also need to reconstitute the target image it seems
    # this is done in line, using fslmaths and fslstats, we divide the real image by its mean and multiply it by the mean of the synth image

    echo " is it bilateral -- ${bilateral} -- is it with a template flag -- ${t_flag} -- "

    echo " is it bilateral -- ${bilateral} -- is it with a template flag -- ${t_flag} -- " >> ${prep_log}

    if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

        echo " not bilateral -- ${bilateral} -- and no template flag -- ${t_flag} -- "

        echo " not bilateral -- ${bilateral} -- and no template flag -- ${t_flag} -- " >> ${prep_log}

        # if not bilateral, we do this using native tissue and template tissue
        
        # first we create a new healthy version of the lesioned hemisphere
        # native tissue stitched image doesnt need scaling

        task_in="fslmaths ${fT1brain_inMNI2} -mas ${L_hemi_mask} ${fT1_H_hemi}"

        task_exec

        # now we harvest the real healthy hemisphere
        
        task_in="fslmaths ${T1_brain_inMNI2} -mas ${L_hemi_mask_binv} ${T1_H_hemi}"

        task_exec

        # here we stitch the two

        task_in="fslmaths ${fT1_H_hemi} -mas ${L_hemi_mask} -add ${T1_H_hemi} ${stitched_T1_nat}"

        task_exec

        #######

        # repeat above process for template data - without filling of the donor image
        # this is not correct
        # it should be the trully scaled MNI2_in_T1
        # here we need scaling
        
        task_in="fslmaths ${tmp_s2T1_CSFGMCBWM} -mas ${L_hemi_mask} ${Temp_L_hemi}"

        task_exec

        task_in="fslmaths ${T1_brain_inMNI2} -div `mrstats -force -nthreads ${ncpu} -quiet -mask ${Lmask_binv_inMNI1_dilx2} -ignorezero -output mean ${T1_brain_inMNI2} ` \
        -mul `fslstats ${tmp_s2T1_CSFGMCBWM} -M ` -mas ${L_hemi_mask_binv} -add ${Temp_L_hemi} ${stitched_T1_temp}"

        task_exec

        #######

        stitched_T1=${stitched_T1_temp}

        # follow same pipeline for generating a noise map

        task_in="fslmaths ${T1_noise_inMNI1} -mas ${H_hemi_mask} ${T1_noise_H_hemi}"

        task_exec

        task_in="fslmaths ${fT1_noise_inMNI1} -mas ${H_hemi_mask_binv} -add ${T1_noise_H_hemi} ${stitched_noise_MNI1}"

        task_exec

        # now we generate the initial filled map deriving the graft from the stitched_T1 using template derived tissue
        # this is to avoid midline spill over

        task_in="fslmaths ${stitched_T1} -mul ${Lmask_bin_inMNI2_s3} ${Temp_L_fill_T1}"

        task_exec

        task_in="fslmaths ${T1_brain_inMNI2} -mul ${Lmask_binv_inMNI2_s3} -add ${Temp_L_fill_T1} ${Temp_T1_filled1}"

        task_exec

        # define your initial filled map as Temp_T1_filled1
        #### I can add a move command here to simply rename this to whatever it needs to be for later on
        #### can also use a more generic name for that

        T1_filled1=${Temp_T1_filled1}

    elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

        echo " yes bilateral -- ${bilateral} -- and - or template flag -- ${t_flag} -- " >> ${prep_log}

        # if bilateral we do a simple(r) filling

        # if bilateral we fill holes with the template image of the MNI2 step (which is deformed to match patient anatomy in MNI space)

        # task_in="ImageMath 3 ${tmp_s2T1_CSFGMCBWMr} addtozero ${tmp_s2T1_CSFGMCBWM} ${MNI2_in_T1_scaled}"

        # task_exec

        # similarly but no hemisphere work and no stitching
        # stitched_T1 and stitched_T1_nat are now fake ones

        stitched_T1=${tmp_s2T1_CSFGMCBWM}

        # create the initial filling graft

        task_in="fslmaths ${tmp_s2T1_CSFGMCBWM} -mul ${Lmask_bin_inMNI2_s3} ${Temp_bil_Lmask_fill1}"

        task_exec

        # Generate initial filled image

        task_in="fslmaths ${T1_brain_inMNI2} -div `mrstats -force -nthreads ${ncpu} -quiet -mask ${Lmask_binv_inMNI1_dilx2} -ignorezero -output mean ${T1_brain_inMNI2} ` \
        -mul `fslstats ${tmp_s2T1_CSFGMCBWM} -M ` -mul ${Lmask_binv_inMNI2_s3} -add ${Temp_bil_Lmask_fill1} ${Temp_T1_bilfilled1}"

        task_exec

        ######

        # if bilateral!

        T1_filled1=${Temp_T1_bilfilled1}

        stitched_T1_nat=${T1_filled1}

        echo " Since lesion is bilateral we use filled brain for Atropos1 " >> ${prep_log}

    fi

    # warp the stitched to filled images, if not already done

    if [[ -z "${stitch2fill_mark}" ]] ; then

        echo "Warping stitched T1 to filled T1" >> ${prep_log}

        fix_im="${T1_filled1}"

        mov_im="${stitched_T1}"

        mask=" -x ${brain_mask_inMNI1},${brain_mask_inMNI1} "

        transform="so"

        output="${T1_sti2fil_str}" 

        KUL_antsRegSyN_Def

    else

        echo " Warping stitched T1 to filled T1 already done, skipping" >> ${prep_log}

    fi

    # also warp the filled T1 to the T1 in MNI1 (excluding the lesion)

    if [[ -z "${fill2MNI1mniL_mark}" ]] ; then

        echo "Warping filled T1 to T1 in MNI minL" >> ${prep_log}

        fix_im="${T1_brain_inMNI1}"

        mov_im="${T1_filled1}"

        mask=" -x ${brain_mask_minL_inMNI1},${brain_mask_inMNI1} "

        transform="so"

        output="${T1fill2MNI1minL_str}" 

        KUL_antsRegSyN_Def

    else

        echo " Warping filled T1 to T1 in MNI minL already done, skipping" >> ${prep_log}

    fi

    # Run Atropos 1 on the stitched ims after warping to the filled ones

    if [[ -z "${Atropos1_wf_mark}" ]] ; then

        # Run AtroposN4

        if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

            atropos1_brain=${T1_sti2fill_brain}

        elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

            echo " Using the initial filled for Atropos " >> ${prep_log}

            atropos1_brain=${Temp_T1_bilfilled1}

        fi

        prim_in=${atropos1_brain}

        atropos_mask="${MNI_brain_mask}"
        # this is so to avoid failures with atropos

        atropos_priors=${new_priors}

        atropos_out="${str_pp}_atropos1_"

        wt="0.3"

        mrf="[0.2,1,1,1]"

        KUL_antsAtropos

        Atropos1_str="${str_pp}_atropos1_SegmentationPosteriors?.nii.gz"

        Atropos1_posts=($(ls ${Atropos1_str}))

        echo ${Atropos1_posts[@]} >> ${prep_log}

    else

        priors_str="${priors::${#priors}-9}*.nii.gz"

        # echo ${priors_str}

        priors_array=($(ls ${priors_str}))

        echo ${priors_array[@]} >> ${prep_log}

        if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

            atropos1_brain=${T1_sti2fill_brain}

        elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

            echo " Using the initial filled for Atropos " >> ${prep_log}

            atropos1_brain=${Temp_T1_bilfilled1}

        fi

        Atropos1_str="${str_pp}_atropos1_SegmentationPosteriors?.nii.gz"

        Atropos1_posts=($(ls ${Atropos1_str}))

        echo ${Atropos1_posts[@]} >> ${prep_log}

        echo " Atropos1 already done " >> ${prep_log}

    fi

}

# image flipping in x with fslswapdim and fslorient 

function KUL_flip_ims {

    task_in="fslswapdim ${input} -x y z ${flip_out}"

    task_exec

    task_in="fslorient -forceradiological ${flip_out}"
    
    task_exec
    
}

# ANTs N4Atropos
# set outer iterations loop to 1 for debugging

function KUL_antsAtropos {

    task_in="antsAtroposN4.sh -d 3 -a ${prim_in} -x ${atropos_mask} -m 2 -n 6 -c 4 -y 2 -y 3 -y 4 \
    -p ${atropos_priors} -w ${wt} -r ${mrf} -o ${atropos_out} -u 1 -g 1 -k 1 -s nii.gz -z 0"

    task_exec
}


# check what kind of lesion it is

if [[ "${E_flag}" -eq 0 ]]; then

    echo
    echo "No -E flag set, treating the lesion as an intra-axial lesion, we will run VBG" >&2
    echo "No -E flag set, treating the lesion as an intra-axial lesion, we will run VBG" >> ${prep_log}
    echo

    # check and report if temp flag is set

    if [[ "${t_flag}" -eq 0 ]]; then
    
        echo
        echo "Template flag not set, using native tissue for filling" >&2
        echo "Template flag not set, using native tissue for filling" >> ${prep_log}
        echo
        
    elif [[ "${t_flag}" -eq 1 ]]; then

        echo
        echo " -t flag is active works best with a cooked template using KUL_VBG_cook_template.sh" >&2
        echo " -t flag is active works best with a cooked template using KUL_VBG_cook_template.sh" >> ${prep_log}
        echo
        echo "Template flag is set, using native and donor tissue for filling" >&2
        echo "Template flag is set, using native and donor tissue for filling" >> ${prep_log}
        echo

    fi


    # ------------------------------------------------------------------------------------------ #

    ## Start of Script

    echo " You are using VBG " >> ${prep_log}

    echo "" >> ${prep_log}

    echo " VBG started at ${start_t} " >> ${prep_log}

    echo ${priors_array[@]} >> ${prep_log}

    if [[ -z "${search_wf_mark1}" ]]; then

        if [[ -z "${srch_preprocp1}" ]]; then

            input="${prim}"

            output1="${str_pp}_T1_reori2std.nii.gz"

            # task_in="fslreorient2std -m ${T1_reori_mat} ${input} ${output1}"

            task_in="fslreorient2std ${input} ${output1} && fslreorient2std ${input} >> ${T1_reori_mat}"

            task_exec

            # reorient T1s

            input="${output1}"

            dn_model="Gaussian"

            output2="${str_pp}_T1_dn.nii.gz"

            output=${output2}

            noise="${str_pp}_T1_noise.nii.gz"

            mask=""

            # denoise T1s
            KUL_denoise_im

            # to avoid failures with BFC due to negative pixel values

            task_in="fslmaths ${output2} -thr 0 ${str_pp}_T1_dn_thr.nii.gz"

            task_exec

            input="${str_pp}_T1_dn_thr.nii.gz"

            unset output2

            bias="${str_pp}_T1_bais1.nii.gz"

            output="${T1_N4BFC}"

            # N4BFC T1s
            KUL_N4BFC

        else

            echo "Reorienting, denoising, and bias correction already done, skipping " >> ${prep_log}

        fi

        # Run ANTs BET, make masks

        if [[ -z "${srch_antsBET}" ]]; then

            echo " running Brain extraction " >> ${prep_log}

            prim_in="${T1_N4BFC}"

            output="${hdbet_str}"

            # run antsBET

            KUL_antsBETp

            task_in="fslmaths ${clean_mask_nat} -s 2 -thr 0.5 -save ${BET_mask_s2} -binv -fillh -s 2 -thr 0.2 \
            -sub ${BET_mask_s2} -thr 0 ${BET_mask_binvs2}"

            task_exec

            task_in="fslmaths ${T1_N4BFC} -mul ${BET_mask_binvs2} ${T1_skull}"

            task_exec

        else

            echo " Brain extraction already done, skipping " >> ${prep_log}

            echo "${T1_brain_clean}" >> ${prep_log}

            echo "${clean_mask_nat}" >> ${prep_log}

            echo " ANTsBET already run, skipping " >> ${prep_log}

        fi

        # run KUL_lesion_magic1
        # this creates a bin, binv, & bm_minL 

        if [[ -z "${sch_brnmsk_minL}" ]]; then

            KUL_Lmask_part1

        else

            echo "${brain_mask_minL} already created " >> ${prep_log}

        fi

        # carry on
        # here we do the first T1 warp to template (default antsRegSyN 3 stage)

        if [[ -z "${T1brain2MNI1}" ]] ; then
        
            mov_im="${T1_brain_clean}"

            fix_im="${MNI_T1_brain}"

            mask=" -x ${MNI_brain_mask},${brain_mask_minL} "

            transform="s"

            output="${T1_brMNI1_str}"

            KUL_antsRegSyN_Def

        else

            echo "${T1_brain_inMNI1} already created " >> ${prep_log}

        fi

        # Apply warps to brain_mask, noise, L_mask and make BM_minL

        task_in="WarpImageMultiTransform 3 ${clean_mask_nat} ${brain_mask_inMNI1} -R ${MNI_T1_brain} ${T1_brMNI1_str}1Warp.nii.gz ${T1_brMNI1_str}0GenericAffine.mat --use-NN"

        task_exec

        task_in="WarpImageMultiTransform 3 ${str_pp}_T1_noise.nii.gz ${T1_noise_inMNI1} -R ${MNI_T1_brain} ${T1_brMNI1_str}1Warp.nii.gz ${T1_brMNI1_str}0GenericAffine.mat --use-NN"

        task_exec

        task_in="WarpImageMultiTransform 3 ${Lmask_in_T1_bin} ${str_pp}_Lmask_rsMNI1.nii.gz -R ${MNI_T1_brain} ${T1_brMNI1_str}1Warp.nii.gz ${T1_brMNI1_str}0GenericAffine.mat"

        task_exec
        
        task_in="fslmaths ${str_pp}_Lmask_rsMNI1.nii.gz -bin -mas ${brain_mask_inMNI1} -save ${Lmask_bin_inMNI1} -binv -mas ${brain_mask_inMNI1} ${brain_mask_minL_inMNI1}"

        task_exec


    else


        echo " First part already done, skipping. " >> ${prep_log}

    fi

    # Flip the images in MNI1

    if [[ -z "${search_wf_mark2}" ]]; then

        # do it for the T1s

        input="${T1_brain_inMNI1}"

        flip_out="${fT1brain_inMNI1}"

        KUL_flip_ims

        unset input flip_out

        input="${brain_mask_minL_inMNI1}"

        flip_out="${fbrain_mask_minL_inMNI1}"

        KUL_flip_ims

        unset input flip_out

        input="${T1_noise_inMNI1}"

        flip_out="${fT1_noise_inMNI1}"

        KUL_flip_ims

        unset input flip_out

    else

        echo " flipped images already created, skipping " >> ${prep_log}

    fi

    # Second deformation, warp to template a second time (1 stage SyN)

    if [[ -z "${T1brain2MNI2}" ]]; then

        fix_im="${MNI_T1_brain}"

        mov_im="${T1_brain_inMNI1}"

        transform="s"

        output="${T1_brMNI2_str}"

        mask=" -x ${MNI_brain_mask},${brain_mask_minL_inMNI1} "

        KUL_antsRegSyN_Def

    else

        echo " Second T1_brain 2 MNI already done, skipping " >> ${prep_log}

    fi

    # Warp flipped brain to template (3 stage)

    if [[ -z "${fT1_brain_2MNI2}" ]]; then

        fix_im="${MNI_T1_brain}"

        mov_im="${fT1brain_inMNI1}"

        transform="s"

        output="${fT1_brMNI2_str}"

        mask=" -x ${MNI_brain_mask},${fbrain_mask_minL_inMNI1} "

        echo " now making fT1brain2MNI2 " >> ${prep_log}

        KUL_antsRegSyN_Def

    else

        echo " Second fT1_brain 2 MNI already done, skipping " >> ${prep_log}

    fi

    # Atropos2 runs on the T1 brain in MNI1 space (after first deformation)
    # after this runs, cleanup and apply inverse warps to native space

    if [[ -z "${Atropos2_wf_mark}" ]]; then

        unset atropos_out prim_in atropos_mask atropos_priors wt mrf

        echo " using MNI priors for segmentation "  >> ${prep_log}

        echo ${priors_array[@]} >> ${prep_log}

        prim_in=${T1_brain_inMNI1}

        atropos_mask="${brain_mask_minL_inMNI1}"

        echo " using brain mask minL in MNI1 "  >> ${prep_log}
        # this is so to avoid failures with atropos

        atropos_priors=${new_priors}

        atropos_out="${str_pp}_atropos2_"

        wt="0.1"

        mrf="[0.1,1,1,1]"

        KUL_antsAtropos

        Atropos2_str="${str_pp}_atropos2_SegmentationPosteriors?.nii.gz"

        Atropos2_posts=($(ls ${Atropos2_str}))

        echo ${Atropos2_posts[@]} >> ${prep_log}

        unset atropos_out prim_in atropos_mask atropos_priors wt mrf

    else

        Atropos2_str="${str_pp}_atropos2_SegmentationPosteriors?.nii.gz"

        Atropos2_posts=($(ls ${Atropos2_str}))

        echo ${Atropos2_posts[@]} >> ${prep_log}

        echo " Atropos2 segmentation already finished, skipping. " >> ${prep_log}

    fi

    # second part handling lesion masks and Atropos run
    # this function has builtin processing control points

    if [[ -z "${srch_Lmask_pt2}" ]]; then

        echo " Starting KUL lesion magic part 2 " >> ${prep_log}

        KUL_Lmask_part2

        echo " Finished KUL lesion magic part 2 " >> ${prep_log}

    else

        task_in="fslmaths ${MNI_lwr} -mas ${Lmask_bin_inMNI1} ${lesion_left_overlap}"

        task_exec

        task_in="fslmaths ${MNI_rwr} -mas ${Lmask_bin_inMNI1} ${lesion_right_overlap}"

        task_exec

        Lmask_tot_v=$(mrstats -force -nthreads ${ncpu} ${Lmask_bin_inMNI1} -output count -quiet -ignorezero)

        overlap_left=$(mrstats -force -nthreads ${ncpu} ${lesion_left_overlap} -output count -quiet -ignorezero)

        overlap_right=$(mrstats -force -nthreads ${ncpu} ${lesion_right_overlap} -output count -quiet -ignorezero)

        T1b_inMNI1p_mean=$(fslstats ${T1b_inMNI1_punched} -M)

        L_ovLt_2_total=$(echo ${overlap_left}*100/${Lmask_tot_v} | bc)

        L_ovRt_2_total=$(echo ${overlap_right}*100/${Lmask_tot_v} | bc)

        echo " total lesion vox count ${Lmask_tot_v}" >> ${prep_log}

        echo " ov_left is ${overlap_left}" >> ${prep_log}

        echo " ov right is ${overlap_right}" >> ${prep_log}

        echo " ov_Lt to total is ${L_ovLt_2_total}" >> ${prep_log}

        echo " ov_Rt to total is ${L_ovRt_2_total}" >> ${prep_log}

        # we set a hard-coded threshold of 65, if unilat. then native heatlhy hemi is used
        # if bilateral by more than 35, template brain is used
        # # this needs to be modified, also need to include simple lesion per hemisphere overlap with percent to total hemi volume
        # this will enable us to use template or simple filling and derive mean values per tissue class form another source (as we are currently using the original images).
        # AR 09/02/2020
        # here we also need to make unilateral L masks, masked by hemi mask to overcome midline issue
        
        if [[ "${L_ovLt_2_total}" -gt 65 ]]; then

            echo ${L_ovLt_2_total} >> ${prep_log}

            echo " This patient has a left sided or predominantly left sided lesion " >> ${prep_log}

            echo "${L_hemi_mask}" >> ${prep_log}

            echo "${H_hemi_mask}" >> ${prep_log}

            T1_filled1=${Temp_T1_filled1}

            stitched_T1=${stitched_T1_temp}

        elif [[ "${L_ovRt_2_total}" -gt 65 ]]; then

            echo ${L_ovRt_2_total} >> ${prep_log}

            echo " This patient has a right sided or predominantly right sided lesion " >> ${prep_log}

            echo "${L_hemi_mask}" >> ${prep_log}

            echo "${H_hemi_mask}" >> ${prep_log}

            T1_filled1=${Temp_T1_filled1}

            stitched_T1=${stitched_T1_temp}
            
        else 

            bilateral=1

            stitched_T1=${tmp_s2T1_CSFGMCBWM}

            T1_filled1=${Temp_T1_bilfilled1}

            stitched_T1_nat=${T1_filled1}

            echo " This is a bilateral lesion with ${L_ovLt_2_total} left side and ${L_ovRt_2_total} right side, using Template T1 to derive lesion fill patch. "  >> ${prep_log}

            echo " note Atropos1 will use the filled images instead of the stitched ones "  >> ${prep_log}

        fi

        if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

            atropos1_brain=${T1_sti2fill_brain}

        elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

            echo " Using the initial filled for Atropos " >> ${prep_log}

            atropos1_brain=${Temp_T1_bilfilled1}

        fi

        Atropos1_str="${str_pp}_atropos1_SegmentationPosteriors?.nii.gz"

        Atropos1_posts=($(ls ${Atropos1_str}))

        echo ${Atropos1_posts[@]} >> ${prep_log}

        echo " Lesion magic part 2 already finished, skipping " >> ${prep_log}


    fi

    ##### 

    # Now we warp back to MNI brain in native space
    # which will be needed after Atropos1
    # this can be replaced by a different kind of reg no ? or we simply apply the inverse warps!
    # just to show the initial filled result (initially for diagnostic purposes)

    if [[ -z "${srch_bk2anat1_mark}" ]]; then

        # fix_im="${T1_brMNI1_str}InverseWarped.nii.gz"

        fix_im="${T1_filled1}"

        mov_im="${T1_brain_clean}"

        mask=" -x ${brain_mask_inMNI1},${brain_mask_minL} "

        transform="s"

        output="${T1_bk2nat1_str}"

        KUL_antsRegSyN_Def

        task_in="cp ${T1_bk2nat1_str}InverseWarped.nii.gz ${str_op}_T1_initial_filled_brain.nii.gz"

        task_exec    

        # the bk2anat1 step is for the outputs of Atropos1 mainly.

    else

        echo "First step Warping images back to anat already done, skipping " >> ${prep_log}

    fi

    # we will need fslmaths to make lesion_fill2 from the segmentations
    # fslmaths Atropos2_posteriors -add lesion_fill2
    # fslstats -m
    # fslmaths to binarize each tpm then -mul the mean intensity of that tissue type
    # should mask out the voxels of each tpm from the resulting image before inserting it
    # finally fslmaths -add noise and -mul bias

    echo " Starting KUL lesion magic part 3 " >> ${prep_log}

    if [[ -z "${srch_make_images}" ]]; then 

        # warping nat filled (in case of unilat. lesion and place holder for initial filled)
        # will be used to fill holes in synth image

        task_in="WarpImageMultiTransform 3 ${stitched_T1_nat} ${stitched_T1_nat_innat} -R ${T1_brain_clean} \
        -i ${T1_bk2nat1_str}0GenericAffine.mat ${T1_bk2nat1_str}1InverseWarp.nii.gz && WarpImageMultiTransform 3 ${stitched_T1_temp} \
        ${stitched_T1_temp_innat} -R ${T1_brain_clean} -i ${T1_bk2nat1_str}0GenericAffine.mat ${T1_bk2nat1_str}1InverseWarp.nii.gz"

        task_exec

        # first we warp the Atropos1_segmentation back to native space

        echo "in make images loop " >> ${prep_log}

        echo " Creating synthetic image... almost there "

        # Create the segmentation image lesion fill

        task_in="fslmaths ${str_pp}_atropos1_Segmentation.nii.gz -mas ${Lmask_bin_inMNI1_dilx2} ${Lfill_segm_im}"

        task_exec

        # Make a hole in the real segmentation image and fill it

        task_in="fslmaths ${str_pp}_atropos2_Segmentation.nii.gz -mas ${Lmask_binv_inMNI1_dilx2} -add ${Lfill_segm_im} ${atropos2_segm_im_filled}"

        task_exec

        # Bring the Atropos2_segm_im to native space
        # for diagnostic purposes

        task_in="WarpImageMultiTransform 3 ${atropos2_segm_im_filled} ${atropos2_segm_im_filled_nat} -R ${T1_brain_clean} -i ${T1_bk2nat1_str}0GenericAffine.mat ${T1_bk2nat1_str}1InverseWarp.nii.gz --use-NN"

        task_exec

        # Making the cleaned segmentation images here

        echo ${tissues[@]} >> ${prep_log}

        # here we make this -> ${str_pp}_synthT1_MNI1.nii.gz using a simple fslmaths step

        # task_in="fslmaths ${T1_sti2fill_brain} -mas ${Lmask_bin_inMNI1_dilx2} ${Lfill_T1_dilx2}"

        # task_exec

        # task_in="fslmaths ${T1_brain_inMNI2} -mas ${Lmask_binv_inMNI1_dilx2} -add ${Lfill_T1_dilx2_im} ${str_pp}_synthT1_MNI1.nii.gz"

        # task_exec

        # task_in="fslmaths ${T1_sti2fill_brain} -bin -mul ${T1_st2f_mean} ${T1b_st2f_mean_im} && ImageMath 3 ${atropos1_brain_norm} \
        # Normalize ${T1_sti2fill_brain} ${T1b_st2f_mean_im}"

        # just in case but this fslstats step is getting done before this point
        T1b_inMNI1p_mean=$(fslstats ${T1b_inMNI1_punched} -M)

        T1_st2f_mean=$(fslstats ${T1_sti2fill_brain} -M)

        task_in="fslmaths ${atropos1_brain} -div ${T1_st2f_mean} ${atropos1_brain_norm}"

        task_exec

        T1b_inMNI1p_N_mean=$(fslstats ${T1b_inMNI1_p_norm} -M)

        task_in="fslmaths ${T1b_inMNI1_p_norm} -div ${T1b_inMNI1p_N_mean} -mul `fslstats ${atropos1_brain_norm} -M ` ${T1b_inMNI1_pN_sc2st2f}"

        task_exec

        # T1b_inMNI1_p_norm is generated before 

        # Match the intensities of the normalized tissue components from each image

        for i in ${!tissues[@]}; do

            # Create the atropos1 tpms lesion fill patches and inject in respective punched atropos2 tpm

            atropos2_tpms_punched[$i]="${str_pp}_atropos_${tissues[$i]}_punched.nii.gz"

            atropos1_tpms_Lfill[$i]="${str_pp}_atropos1_Lfill_${tissues[$i]}.nii.gz"

            atropos2_tpms_filled[$i]="${str_pp}_atropos2_${tissues[$i]}_filled.nii.gz"

            Atropos2_Int_finder[$i]="${str_pp}_atropos2_${tissues[$i]}_intensity_finder.nii.gz"

            atropos2_tpms_filled_GLC[$i]="${str_pp}_atropos2_${tissues[$i]}_filled_GLC.nii.gz"

            atropos2_tpms_filled_GLCbinv[$i]="${str_pp}_atropos2_${tissues[$i]}_filled_GLCbinv.nii.gz"

            # T1 stuff
            
            R_nTiss_intmap[$i]="${str_pp}_T1_${tissues[$i]}_real_norm_intmap.nii.gz"

            Atropos1_posts_bin[$i]="${str_pp}_T1_${tissues[$i]}_Atr1_post_bin.nii.gz"

            Atropos1b_ntiss_map[$i]="${str_pp}_T1_${tissues[$i]}_Atr1b_norm_intmap.nii.gz"

            R_nTiss_Int_map_norm[$i]="${str_pp}_T1_${tissues[$i]}_real_norm_nintmap.nii.gz"

            A1_nTiss_Int_scaled[$i]="${str_pp}_T1_${tissues[$i]}_Atr1b_norm_scaled_intmap.nii.gz"

            A1_nTiss_Int_scaled_fill[$i]="${str_pp}_T1_${tissues[$i]}_Atr1b_norm_scaled_intmap_fill.nii.gz"

            R_nTiss_map_filled[$i]="${str_pp}_T1_${tissues[$i]}_real_norm_intmap_filled.nii.gz"

            # make the punched tpms
            # Atropos2 was run with only the Lmask_bin excluded
            # no smoothing or dilation
            # so dilx2 Lmasks should be fine

            task_in="fslmaths ${Atropos2_posts[$i]} -mas ${Lmask_binv_inMNI1_dilx2} -thr 0.1 -bin ${atropos2_tpms_punched[$i]}"

            task_exec

            # derive a very specific tissue mask, e.g. for GM we only accept voxels with probability > 99 % as GM

            task_in="fslmaths ${Atropos1_posts[$i]} -mas ${Lmask_bin_inMNI1_dilx2} -bin -save ${atropos1_tpms_Lfill[$i]} \
            -add ${atropos2_tpms_punched[$i]} ${atropos2_tpms_filled[$i]} && mrthreshold -force -quiet -nthreads ${ncpu} \
            -toppercent 5 ${Atropos2_posts[$i]} - | mrcalc - ${brain_mask_minL_inMNI1} -mult 0.001 -gt ${Atropos2_Int_finder[$i]} -force"
            
            # "-restart ${Atropos2_posts[$i]} -thr 0.99 -bin ${Atropos2_Int_finder[$i]}"

            task_exec

            # find out if we still need this - yes we do

            task_in="maskfilter -force -nthreads ${ncpu} -connectivity -largest ${atropos2_tpms_filled[$i]} connect - | mrcalc - 0 -gt \
            -force -nthreads ${ncpu} ${atropos2_tpms_filled_GLC[$i]} && fslmaths ${atropos2_tpms_filled_GLC[$i]} -binv ${atropos2_tpms_filled_GLCbinv[$i]}"

            task_exec

            ##

            # need to warp the atropos2 tpms (after punching) to native space
            # threshold and apply as masks to the original image to get tissue specific intensity maps
            # then histmatch each synth tissue map to the corresponding native real tissue intensity map.

            # so we can do this the opposite way, where we first match intensities then warp to native
            # after synth image is created

            # clean the atropos1 posts

            task_in="mrcalc ${Atropos1_posts[$i]} 0.1 -gt - | maskfilter - connect ${Atropos1_posts_bin[$i]} -force -nthreads ${ncpu} -connectivity -largest"

            task_exec

            # get Atropos1 brain intensity map per tissue

            task_in="fslmaths ${atropos1_brain_norm} -mas ${Atropos1_posts_bin[$i]} ${Atropos1b_ntiss_map[$i]}"

            task_exec

            # calculate mean of each tissue type norm intensity ignoring zeroes

            A1_nTiss_Norm_mean[$i]=$(fslstats ${Atropos1b_ntiss_map[$i]} -M)

            # get the T1 brain in MNI1 punched tissue norm intensity map 
            # we use a very specific tpm mask here

            task_in="fslmaths ${T1b_inMNI1_pN_sc2st2f} -mas ${Atropos2_Int_finder[$i]} ${R_nTiss_intmap[$i]}"

            task_exec

            # calculate its mean norm intensity

            R_nTiss_Norm_mean[$i]=$(fslstats ${R_nTiss_intmap[$i]} -M)

            # scale the Atropos1b normalized map of normalized intensities to that of the real normalized image normalized intensity map

            task_in="fslmaths ${Atropos1b_ntiss_map[$i]} -div ${A1_nTiss_Norm_mean[$i]} -mul ${R_nTiss_Norm_mean[$i]} \
            -save ${A1_nTiss_Int_scaled[$i]} -mas ${Lmask_bin_inMNI1_dilx2} ${A1_nTiss_Int_scaled_fill[$i]}"
            
            task_exec

            task_in="fslmaths ${T1b_inMNI1_pN_sc2st2f} -mas ${atropos2_tpms_punched[$i]} -add ${A1_nTiss_Int_scaled_fill[$i]} -mas ${atropos2_tpms_filled_GLC[$i]} ${R_nTiss_map_filled[$i]}"

            task_exec

        done

        echo ${Atropos1b_ntiss_map[@]}
        echo ${A1_nTiss_Int_scaled[@]}
        echo ${R_nTiss_Int_map_norm[@]}
        echo ${atropos2_tpms_filled_GLCbinv[@]}

        CSF_max_2=$(mrstats -ignorezero -output max -quiet -force ${A1_nTiss_Int_scaled[0]})

        CSF_nmean_2=$(mrcalc `mrstats -ignorezero -output mean -quiet -force ${A1_nTiss_Int_scaled[1]}` 0.2 -mul -force -quiet)

        if (( $(bc <<<"${CSF_max_2} > ${CSF_nmean_2}") )); then

            echo " CSF signal is too high, is this a postcontrast scan ? correcting"

            echo " CSF signal is too high, is this a postcontrast scan ? correcting" >> ${prep_log}

            task_in="fslmaths ${Atropos1b_ntiss_map[0]} -div ${CSF_max_2} -mul ${CSF_nmean_2} \
            -save ${str_pp}_T1_CSF_corr_Atr1b_norm_scaled_intmap.nii.gz -mas ${Lmask_bin_inMNI1_dilx2} \
            ${str_pp}_T1_CSF_corr_Atr1b_norm_scaled_intmap_fill.nii.gz"
            
            task_exec

            task_in="fslmaths ${T1b_inMNI1_pN_sc2st2f} -mas ${atropos2_tpms_punched[0]} -add ${str_pp}_T1_CSF_corr_Atr1b_norm_scaled_intmap_fill.nii.gz -mas ${atropos2_tpms_filled_GLC[0]} ${str_pp}_T1_CSF_corr_real_norm_intmap_filled.nii.gz"

            task_exec

            task_in="ImageMath 3 ${str_pp}_T1_nGCCS_synth.nii.gz addtozero ${R_nTiss_map_filled[1]} ${str_pp}_T1_CSF_corr_real_norm_intmap_filled.nii.gz && ImageMath 3 \
            ${str_pp}_T1_nGCCSBG_synth.nii.gz addtozero ${str_pp}_T1_nGCCS_synth.nii.gz ${R_nTiss_map_filled[2]} && ImageMath 3 ${str_pp}_T1_nGCCSBGWM_synth.nii.gz \
            addtozero ${str_pp}_T1_nGCCSBG_synth.nii.gz ${R_nTiss_map_filled[3]}"

            task_exec


        else

            task_in="ImageMath 3 ${str_pp}_T1_nGCCS_synth.nii.gz addtozero ${R_nTiss_map_filled[1]} ${R_nTiss_map_filled[0]} && ImageMath 3 \
            ${str_pp}_T1_nGCCSBG_synth.nii.gz addtozero ${str_pp}_T1_nGCCS_synth.nii.gz ${R_nTiss_map_filled[2]} && ImageMath 3 ${str_pp}_T1_nGCCSBGWM_synth.nii.gz \
            addtozero ${str_pp}_T1_nGCCSBG_synth.nii.gz ${R_nTiss_map_filled[3]}"

            task_exec

        fi

        # are the intensities now the same or do I have to reconstitute the target image also ?

        # task_in="fslmaths ${R_nTiss_map_filled[0]} -mas ${atropos2_tpms_filled_GLCbinv[1]} -add ${R_nTiss_map_filled[1]} \
        # -save ${str_pp}_T1_cw_dil_s_fill.nii.gz -mas ${atropos2_tpms_filled_GLCbinv[2]} -add ${R_nTiss_map_filled[2]} \
        # -save ${str_pp}_T1_cwc_dil_s_fill.nii.gz -mas ${atropos2_tpms_filled_GLCbinv[3]} -add ${R_nTiss_map_filled[3]} \
        # -save ${str_pp}_T1_cwcbg_dil_s_fill.nii.gz -mas ${brain_mask_inMNI1} -mul ${T1b_inMNI1p_mean} ${str_pp}_synthT1_MNI1_holes.nii.gz"

        # use this instead

        task_in="fslmaths ${str_pp}_T1_nGCCSBGWM_synth.nii.gz -mul ${T1b_inMNI1p_mean} ${str_pp}_synthT1_MNI1_holes.nii.gz"

        task_exec

        ###

        # task_in="WarpImageMultiTransform 3 ${atropos2_tpms_filled_GLC[$i]} ${atropos2_tpms_filled_GLC_nat[$i]} -R ${T1_brain_clean} \
        # -i ${T1_bk2nat1_str}0GenericAffine.mat ${T1_bk2nat1_str}1InverseWarp.nii.gz"

        # Make the new images
        # this part needs to be redesigned
        # probably mrhistmatch will work better here
        # should respect the actual BG shape....
        # if parts of BG missing, fill with WM

        task_in="ImageMath 3 ${str_pp}_synthT1_MNI1.nii.gz addtozero ${str_pp}_synthT1_MNI1_holes.nii.gz ${T1_brain_inMNI1}"

        task_exec

        # if the lesion is not bilateral, then use the filled T1 to derive diff map, if it is bilateral then use stit2fill
        # added the template flag condition here
        # diff map may not be needed anymore even

        if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

            task_in="fslmaths ${T1_filled1} -sub ${str_pp}_synthT1_MNI1.nii.gz ${filledT1_synthT1_diff}"

            task_exec

            task_in="fslmaths ${filledT1_synthT1_diff} -add ${str_pp}_synthT1_MNI1.nii.gz ${str_pp}_hybridT1_MNI1.nii.gz"

            task_exec

        elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

            task_in="fslmaths ${T1_sti2fill_brain} -sub ${str_pp}_synthT1_MNI1.nii.gz ${stiT1_synthT1_diff}"

            task_exec

            task_in="fslmaths ${stiT1_synthT1_diff} -add ${str_pp}_synthT1_MNI1.nii.gz ${str_pp}_hybridT1_MNI1.nii.gz"

            task_exec

        fi
        
        image_in="${str_pp}_hybridT1_MNI1.nii.gz"

        image_out="${str_pp}_hybridT1_native.nii.gz"

        task_in="WarpImageMultiTransform 3 ${image_in} ${image_out} -R ${T1_brain_clean} -i ${T1_brMNI1_str}0GenericAffine.mat ${T1_brMNI1_str}1InverseWarp.nii.gz"

        task_exec

        unset image_in image_out
        
        task_in="ImageMath 3 ${str_pp}_hybridT1_native_S.nii.gz Sharpen ${str_pp}_hybridT1_native.nii.gz"

        task_exec

        task_in="fslmaths ${str_pp}_hybridT1_native_S.nii.gz -div `mrstats -force -nthreads ${ncpu} -quiet -mask ${clean_mask_nat} -ignorezero -output mean ${str_pp}_hybridT1_native_S.nii.gz ` \
        -mul `mrstats -mask ${brain_mask_minL} -force -nthreads ${ncpu} -quiet -ignorezero -output mean ${T1_brain_clean} ` -mul ${Lmask_bin_s3} ${T1_fin_Lfill}"

        task_exec
        
        # make the final outputs

        echo " is it bilateral -- ${bilateral} -- is it with a template flag -- ${t_flag} -- "

        echo " is it bilateral -- ${bilateral} -- is it with a template flag -- ${t_flag} -- " >> ${prep_log}
        
        if [[ -z "${bilateral}" ]] && [[ "${t_flag}" -eq 0 ]]; then

            echo " not bilateral -- ${bilateral} -- and no template flag -- ${t_flag} -- "

            echo " not bilateral -- ${bilateral} -- and no template flag -- ${t_flag} -- " >> ${prep_log}
        
            # if bilateral is empty, then we generate final output with stitched noise map
        
            image_in="${stitched_noise_MNI1}"

            image_out="${stitched_noise_nat}"

            task_in="WarpImageMultiTransform 3 ${image_in} ${image_out} -R ${T1_brain_clean} -i ${T1_brMNI1_str}0GenericAffine.mat ${T1_brMNI1_str}1InverseWarp.nii.gz"

            task_exec

            unset image_in image_out

            # will need this here

            task_in="fslmaths ${T1_brain_clean} -mul ${Lmask_binv_s3} -add ${T1_fin_Lfill} -thr 0 -save ${T1_nat_filled_out} -mul ${BET_mask_s2} \
            -add ${T1_skull} -thr 0 -save ${T1_nat_fout_wskull} -add ${stitched_noise_nat} -thr 0 ${T1_nat_fout_wN_skull}"

            task_exec
        
            task_in="convert_xfm -omat ${T1_reori_mat_inv} -inverse ${T1_reori_mat} && sleep 5 && flirt -in ${T1_nat_fout_wN_skull} -ref ${T1_orig} \
            -out ${T1_4_FS} -applyxfm -init ${T1_reori_mat_inv} && sleep 5  && flirt -in ${T1_nat_filled_out} -ref ${T1_orig} -out ${T1_Brain_4_FS} \
            -applyxfm -init ${T1_reori_mat_inv} && sleep 5 && fslmaths ${T1_Brain_4_FS} -bin ${T1_BM_4_FS}"

            task_exec

        elif [[ ! -z "${bilateral}" ]] || [[ "${t_flag}" -eq 1 ]]; then

            echo " yes bilateral -- ${bilateral} -- and - or template flag -- ${t_flag} -- "

            echo " yes bilateral -- ${bilateral} -- and - or template flag -- ${t_flag} -- " >> ${prep_log}
        
            # if bilateral is 1, then we generate final output with original noise map
        
            task_in="fslmaths ${T1_brain_clean} -mul ${Lmask_binv_s3} -add ${T1_fin_Lfill} -thr 0 -save ${T1_nat_filled_out} -mul ${BET_mask_s2} \
            -add ${T1_skull} -thr 0 -save ${T1_nat_fout_wskull} -add ${str_pp}_T1_noise.nii.gz -thr 0 ${T1_nat_fout_wN_skull}"

            task_exec
            
            task_in="convert_xfm -omat ${T1_reori_mat_inv} -inverse ${T1_reori_mat} && sleep 5 && flirt -in ${T1_nat_fout_wN_skull} -ref ${T1_orig} \
            -out ${T1_4_FS} -applyxfm -init ${T1_reori_mat_inv} && sleep 5 && flirt -in ${T1_nat_filled_out} -ref ${T1_orig} -out ${T1_Brain_4_FS} \
            -applyxfm -init ${T1_reori_mat_inv} && sleep 5 && fslmaths ${T1_Brain_4_FS} -bin ${T1_BM_4_FS}"

            task_exec

        fi



    else

        echo " Making fake healthy images done, skipping. " >> ${prep_log}

        # need to define the output files here if we dont run the above if loop condition

    fi


    unset i
    
else

    echo
    echo "You have set the -E flag, indicating an extra-axial lesion" 
    echo "You have set the -E flag, indicating an extra-axial lesion" >> ${prep_log}
    echo "The lesion patch is filled with 0s only, recon-all should be able to run, if it fails try without -E" 
    echo "The lesion patch is filled with 0s only, recon-all should be able to run, if it fails try without -E" >> ${prep_log}
    echo

     if [[ -z "${srch_preprocp1}" ]]; then

            input="${prim}"

            output1="${str_pp}_T1_reori2std.nii.gz"

            # task_in="fslreorient2std -m ${T1_reori_mat} ${input} ${output1}"

            task_in="fslreorient2std ${input} ${output1} && fslreorient2std ${input} >> ${T1_reori_mat}"

            task_exec

        if [[ -z "${srch_antsBET}" ]]; then

            echo " running Brain extraction " >> ${prep_log}

            prim_in="${str_pp}_T1_reori2std.nii.gz"

            output="${hdbet_str}"

            # run antsBET

            KUL_antsBETp


        else

            echo " Brain extraction already done, skipping " >> ${prep_log}

            echo "${T1_brain_clean}" >> ${prep_log}

            echo "${clean_mask_nat}" >> ${prep_log}

            echo " ANTsBET already run, skipping " >> ${prep_log}

        fi

        # run KUL_lesion_magic1
        # this creates a bin, binv, & bm_minL 

        if [[ -z "${sch_brnmsk_minL}" ]]; then

            KUL_Lmask_part1

        else

            echo "${brain_mask_minL} already created " >> ${prep_log}

        fi

    else

        echo "Reorienting, brain extraction, and VBG pt1 already done, skipping " >> ${prep_log}
    
        
    fi

    # here we fill the lesion mask with 0 and save it where FS recon-all expects it to be

    task_in="fslmaths ${str_pp}_T1_reori2std.nii.gz -mul ${L_O_binv} ${T1_nat_fout_wN_skull}"

    task_exec

    task_in="convert_xfm -omat ${T1_reori_mat_inv} -inverse ${T1_reori_mat} && sleep 5 && flirt -in ${T1_nat_fout_wN_skull} -ref ${T1_orig} \
    -out ${T1_4_FS} -applyxfm -init ${T1_reori_mat_inv} && sleep 5  && flirt -in ${T1_brain_clean} -ref ${T1_orig} -out ${T1_Brain_4_FS} \
    -applyxfm -init ${T1_reori_mat_inv} && sleep 5 && fslmaths ${T1_Brain_4_FS} -bin -save ${T1_BM_4_FS} -restart ${T1_4_FS} -mas ${T1_BM_4_FS} \
    ${T1_Brain_4_FS}"

    task_exec

        
fi



# now we need to try all the above steps, and debug, then program a function for the lesion patch filling
# then add in the recon-all step
# and add in again the overlap calculator and report parts.

# classic_FS

# for recon-all

if [[ "${F_flag}" -eq 1 ]] ; then
	
    echo
    echo "Fresurfer flag is set, now starting FS recon-all based part of VBG" >&2
    echo "Fresurfer flag is set, now starting FS recon-all based part of VBG" >> ${prep_log}
    echo
	
    fs_output="${str_op}_FS_output/sub-${subj}"

    recall_scripts="${fs_output}/${subj}/scripts"

    search_wf_mark4=($(find ${recall_scripts} -type f 2> /dev/null | grep recon-all.done));

    FS_brain="${fs_output}/${subj}/mri/brainmask.mgz"

    new_brain="${str_pp}_T1_Brain_4FS.mgz"

    if [[ $(which hd-bet) ]]; then

        hd_bet_flag=1

    else

        hd_bet_flag=""

    fi


    # need to define fs output dir to fit the KUL_NITs folder structure.
            
    if [[ -z "${search_wf_mark4}" ]]; then

        task_in="mkdir -p ${fs_output} >/dev/null 2>&1"

        task_exec

        # Run recon-all and convert the real T1 to .mgz for display
        # running with -noskulltrip and using brain only inputs
        # for recon-all
        # if we can run up to skull strip, break, fix with hd-bet result then continue it would be much better
        # if we can switch to fast-surf, would be great also
        # another possiblity is using recon-all -skullstrip -clean-bm -gcut -subjid <subject name>

        if [[ ${hd_bet_flag} == 1 ]] ; then 

            task_in="recon-all -i ${T1_4_FS} -s ${subj} -sd ${fs_output} -openmp ${ncpu} -parallel -autorecon1"

            task_exec

            task_in="mri_convert -rl ${fs_output}/${subj}/mri/brainmask.mgz ${T1_BM_4_FS} ${clean_BM_mgz}"

            task_exec

            task_in="mri_mask ${FS_brain} ${T1_BM_4_FS} ${new_brain} && mv ${new_brain} ${fs_output}/${subj}/mri/brainmask.mgz && cp \
            ${fs_output}/${subj}/mri/brainmask.mgz ${fs_output}/${subj}/mri/brainmask.auto.mgz"

            task_exec

            task_in="recon-all -s ${subj} -sd ${fs_output} -openmp ${ncpu} -parallel -all -noskullstrip"

            task_exec

        elif [[ ${hd_bet_flag} == 0 ]] ; then 

            task_in="recon-all -i ${T1_4_FS} -s ${subj} -sd ${fs_output} -openmp ${ncpu} -parallel -all"

            task_exec

        fi

        task_in="mri_convert -rl ${fs_output}/${subj}/mri/brain.mgz ${T1_brain_clean} ${fs_output}/${subj}/mri/real_T1.mgz"

        task_exec

        task_in="mri_convert -rl ${fs_output}/${subj}/mri/brain.mgz -rt nearest ${Lmask_o} ${fs_output}/${subj}/mri/Lmask_T1_bin.mgz"

        task_exec

    else

        echo " recon-all already done, skipping. "
        echo " recon-all already done, skipping. "  >> ${prep_log}
        
    fi

    # ## After recon-all is finished we need to calculate percent lesion/lobe overlap
    # # need to make labels array

    lesion_lobes_report="${fs_output}/percent_lobes_lesion_overlap_report.txt"

    task_in="touch ${lesion_lobes_report}"

    task_exec

    echo " Percent overlap between lesion and each lobe " >> $lesion_lobes_report

    echo " each lobe mask voxel count and volume in cmm is reported " >> $lesion_lobes_report

    echo " overlap in voxels and volume cmm are reported " >> $lesion_lobes_report

    # these labels, wm and gm values are used later for the reporting

    # double checking: RT_Frontal, LT_Frontal, RT_Temporal, LT_Temporal 

    declare -a labels=("RT_Frontal"  "LT_Frontal"  "RT_Temporal"  "LT_Temporal"  "RT_Parietal"  "LT_Parietal" \
    "RT_Occipital"  "LT_Occipital"  "RT_Cingulate"  "LT_Cingulate"  "RT_Insula"  "LT_Insula"  "RT_Putamen"  "LT_Putamen" \
    "RT_Caudate"  "LT_Caudate"  "RT_Thalamus"  "LT_Thalamus" "RT_Pallidum"  "LT_Pallidum"  "RT_Accumbens"  "LT_Accumbens"  "RT_Amygdala"  "LT_Amygdala" \
    "RT_Hippocampus"  "LT_Hippocampus"  "RT_PWM"  "LT_PWM");

    declare -a wm=("4001"  "3001"  "4005"  "3005"  "4006"  "3006" \
    "4004"  "3004"  "4003"  "3003"  "4007"  "3007" "0"  "0" \
    "0"  "0"  "0"  "0"  "0"  "0"  "0"  "0"  "0"  "0" \
    "0"  "0"  "5002"  "5001");

    declare -a gm=("2001"  "1001"  "2005"  "1005"  "2006"  "1006" \
    "2004"  "1004"  "2003"  "1003"  "2007"  "1007" "51"  "12" \
    "50"  "11"  "49"  "10"  "52"  "13"  "58"  "26" "54"  "18" \
    "53"  "17"  "0"  "0");

    fs_lobes_mgz="${fs_output}/${subj}/mri/lobes_ctx_wm_fs.mgz"

    fs_parc_mgz="${fs_output}/${subj}/mri/aparc+aseg.mgz"

    fs_parc_nii="${str_op}_aparc+aseg.nii.gz"

    fs_parc_minL_nii="${str_op}_aparc+aseg_minL.nii.gz"

    fs_lobes_nii="${str_op}_lobes_ctx_wm_fs.nii.gz"

    fs_lobes_minL_nii="${str_op}_lobes_ctx_wm_fs_minL.nii.gz"

    fs_parc_plusL_nii="${str_op}_aparc+aseg+Lesion.nii.gz"

    fs_lobes_plusL_nii="${str_op}_lobes_ctx_wm_fs+Lesion.nii.gz"

    labelslength=${#labels[@]}

    wmslength=${#wm[@]}

    gmslength=${#gm[@]}

    fs_lobes_mark=${fs_lobes_nii}

    search_wf_mark5=($(find ${output_d} -type f | grep lobes_ctx_wm_fs+Lesion.nii));

    if [[ -z "$search_wf_mark5" ]]; then

        # quick sanity check

        if [[ "${labelslength}" -eq "${wmslength}" ]] && [[ "${gmslength}" -eq "${wmslength}" ]]; then

            echo "we are doing okay captain! ${labelslength} ${wmslength} ${gmslength}" >> ${prep_log}

        else

            echo "we have a problem captain! ${labelslength} ${wmslength} ${gmslength}" >> ${prep_log}
            
            exit 2

        fi

        # this approach apparently screws up the labels order, so i need to use annotation2label and mergelabels instead.

        task_in="mri_annotation2label --subject ${subj} --sd ${fs_output} --hemi rh --lobesStrict ${fs_output}/${subj}/label/rh.lobesStrict"

        task_exec

        task_in="mri_annotation2label --subject ${subj} --sd ${fs_output} --hemi lh --lobesStrict ${fs_output}/${subj}/label/lh.lobesStrict"

        task_exec

        task_in="mri_aparc2aseg --s ${subj} --sd ${fs_output} --labelwm --hypo-as-wm --rip-unknown --volmask --annot lobesStrict --o ${fs_lobes_mgz}"

        task_exec

        task_in="mri_convert -rl ${T1_4_FS} -rt nearest ${fs_lobes_mgz} ${fs_lobes_nii}"
        
        task_exec

        task_in="mri_convert -rl ${T1_4_FS} -rt nearest ${fs_parc_mgz} ${fs_parc_nii}"
        
        task_exec

        # here we want to add a loop looking at lesion mask volume
        l_vol=($(fslstats ${Lmask_o} -V))

        # echo "this lesion is not larger than 10 ml, we will not erode it"

        task_in="fslmaths ${Lmask_o} -binv -mul ${T1_BM_4_FS} -bin ${bmc_minL_true}"

        task_exec

        task_in="maskfilter -force -nthreads ${ncpu} ${bmc_minL_true} connect - -connectivity -largest | mrcalc - 0.1 -gt ${bmc_minL_conn} -force -nthreads ${ncpu} -quiet"

        task_exec

        task_in="fslmaths ${Lmask_o} -bin -mul 99 ${L_mask_reori_scaled}"

        task_exec

        task_in="fslmaths ${fs_parc_nii} -mas ${bmc_minL_conn} ${fs_parc_minL_nii} && ImageMath 3 ${fs_parc_plusL_nii} \
        addtozero ${fs_parc_minL_nii} ${L_mask_reori_scaled}"

        task_exec

        task_in="fslmaths ${fs_lobes_nii} -mas ${bmc_minL_conn} ${fs_lobes_minL_nii} && ImageMath 3 ${fs_lobes_plusL_nii} \
        addtozero ${fs_lobes_minL_nii} ${L_mask_reori_scaled}"

        task_exec
    
    else
        
        echo " lobes fs image already done, skipping. " >> ${prep_log}
        
    fi

    # use for loop to read all values and indexes

    search_wf_mark6=($(find ${ROIs} -type f | grep LT_PWM_bin.nii.gz));
        
    if [[ -z "$search_wf_mark6" ]]; then

        for i in {0..11}; do

            echo "Now working on ${labels[$i]}" >> ${prep_log}

            task_in="fslmaths ${fs_lobes_nii} -thr ${gm[$i]} -uthr ${gm[$i]} ${ROIs}/${labels[$i]}_gm.nii.gz"

            task_exec

            task_in="fslmaths ${fs_lobes_nii} -thr ${wm[$i]} -uthr ${wm[$i]} ${ROIs}/${labels[$i]}_wm.nii.gz"

            task_exec

            task_in="fslmaths ${ROIs}/${labels[$i]}_gm.nii.gz -add ${ROIs}/${labels[$i]}_wm.nii.gz -bin ${ROIs}/${labels[$i]}_bin.nii.gz"

            task_exec

        done

        i=""

        for i in {12..25}; do

            echo "Now working on ${labels[$i]}" >> ${prep_log}

            task_in="fslmaths ${fs_lobes_nii} -thr ${gm[$i]} -uthr ${gm[$i]} -bin ${ROIs}/${labels[$i]}_bin.nii.gz"

            task_exec

        done

        i=""

        for i in {26..27}; do

            echo "Now working on ${labels[$i]}" >> ${prep_log}

            task_in="fslmaths ${fs_lobes_nii} -thr ${wm[$i]} -uthr ${wm[$i]} -bin ${ROIs}/${labels[$i]}_bin.nii.gz"

            task_exec

        done
        
    else
        
        echo " isolating lobe labels already done, skipping to lesion overlap check" >> ${prep_log}
        
    fi

    i=""

    # Now to check overlap and quantify existing overlaps
    # we also need to calculate volume and no. of vox for each lobe out of FS
    # also lesion volume

    l_vol=($(fslstats ${Lmask_o} -V))

    echo " * The lesion occupies " ${l_vol[0]} " voxels in total with " ${l_vol[0]} " cmm volume. " >> $lesion_lobes_report

    for (( i=0; i<${labelslength}; i++ )); do


        task_in="fslmaths ${ROIs}/${labels[$i]}_bin.nii.gz -mas ${Lmask_o} ${overlap}/${labels[$i]}_intersect_L_mask.nii.gz"

        task_exec

        b=($(fslstats ${overlap}/${labels[$i]}_intersect_L_mask.nii.gz -V))
        
        a=($( echo ${b[0]} | cut -c1-1))

        vol_lobe=($(fslstats ${ROIs}/${labels[$i]}_bin.nii.gz -V))

        echo " - The " ${labels[$i]} " label is " ${vol_lobe[0]} " voxels in total, with a volume of " ${vol_lobe[1]} " cmm volume. " >> ${lesion_lobes_report}

        if [[ $a -ne 0 ]]; then

            vol_ov=($(fslstats ${overlap}/${labels[$i]}_intersect_L_mask.nii.gz -V))
            
            ov_perc=($(echo "scale=4; (${vol_ov[1]}/${vol_lobe[1]})*100" | bc ))

            echo " ** The lesion overlaps with the " ${labels[$i]} " in " ${vol_ov[1]} \
            " cmm " ${ov_perc} " percent of total lobe volume " >> ${lesion_lobes_report}

        else

        echo " No overlap between the lesion and " ${labels[$i]} " lobe. " >> ${lesion_lobes_report}

        fi


    done

elif [[ "${F_flag}" -eq 0 ]] ; then

    echo
    echo "Fresurfer flag not set, finished, exiting" >&2
    echo "Fresurfer flag not set, finished, exiting" >> ${prep_log}
    echo

fi


finish_t=$(date +%s)

# echo ${start_t}
# echo ${finish_t}

run_time_s=($(echo "scale=4; (${finish_t}-${start_t})" | bc ))
run_time_m=($(echo "scale=4; (${run_time_s}/60)" | bc ))
run_time_h=($(echo "scale=4; (${run_time_m}/60)" | bc ))

echo " execution took " ${run_time_m} " minutes, or approximately " ${run_time_h} " hours. "

echo " execution took " ${run_time_m} " minutes, or approximately " ${run_time_h} " hours. " >> ${prep_log}

# if not running FS, but MSBP should use something like this:
# to run MSBP after a recon-all run is finished
# 
# docker run -it --rm -v $(pwd)/sham_BIDS:/bids_dir \
# -v $(pwd)/sham_BIDS/derivatives:/output_dir \
# -v /NI_apps/freesurfer/license.txt:/opt/freesurfer/license.txt \
# sebastientourbier/multiscalebrainparcellator:v1.1.1 /bids_dir /output_dir participant \
# --participant_label PT007 --isotropic_resolution 1.0 --thalamic_nuclei \
# --brainstem_structures --skip_bids_validator --fs_number_of_cores 4 \
# --multiproc_number_of_cores 4 2>&1 >> $(pwd)/MSBP_trial_run.txt

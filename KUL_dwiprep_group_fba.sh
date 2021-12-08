#!/bin/bash -e
# Bash shell script to process diffusion & structural 3D-T1w MRI data
#
# Requires Mrtrix3 
#
# @ Stefan Sunaert - UZ/KUL - stefan.sunaert@uzleuven.be
# @ Ahmed Radwan - KUL - ahmed.radwan@kuleuven.be
#
# v1.0 - dd 19/11/2021 - beta version
v="v1.0 - dd 19/11/2021"

# Changes made by AR:
# 1- Updated to use new MRTrix3
# 2- Made the suffix an optional argument
# 3- Template construction and following steps now use the wmfod_norm rather than wmfod
# 4- Use same masks generated by KUL_dwiprep rather than generate new ones
# 5- algorithms can now be single shell single tissue, single shell multi-tissue, or multi-shell multi-tissue


# -----------------------------------  MAIN  ---------------------------------------------
# this script defines a few functions:
#  - Usage (for information to the novice user)
kul_main_dir=`dirname "$0"`
source $kul_main_dir/KUL_main_functions.sh
cwd=$(pwd)
ncpu_foreach=4
# suffix="_reg2T1w"
#suffix=""

#select_shells="0 700 1000 2000"
select_shells=""

# FUNCTIONS --------------

# function Usage
function Usage {

cat <<USAGE

`basename $0` performs a group fixel based analysis

Usage:

  `basename $0` -g group_name <OPT_ARGS>

Example:

  `basename $0` -g group_first_32 -n 6 -t "pat01 pat02 pat03 pat04 pat05 con01 con02 con03 con04 con05" 

Required arguments:

     -g: group_name

Optional arguments:
     
     -a:  algorithm: single shell single tissue (ssst), single shell multi tissue (ssmt), multi-shell multi-tissue (default=msmt)
     -t:  subjects used for population_template (useful if you have more than 30 to 40 subjects, otherwise the template building takes very long)
     -n:  number of cpu for parallelisation
     -s:  suffix of input dwis. Options are: 1- to leave it blank (to use native dMRI space processed dMRIs), 2- _reg2T1w (to use the processed dMRIs in native T1 space)
     -v:  show output from mrtrix commands


USAGE

    exit 1
}


# CHECK COMMAND LINE OPTIONS -------------
# 
# Set defaults
ncpu=6 # default if option -n is not given
silent=1 # default if option -v is not given
algo=mt

# Set required options
g_flag=0
t_flag=0

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "n:g:t:a:v" OPT; do

        case $OPT in
        n) #ncpu
            ncpu=$OPTARG
        ;;
        g) #group_name
            group_name="$OPTARG"
            g_flag=1
        ;;
        t) #templatesubjects
            templatesubjects="$OPTARG"
            t_flag=1
        ;;
        a) #algorithm
            algo="$OPTARG"
        ;;
        s) #suffix 
            suffix="$OPTARG"
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
if [ $g_flag -eq 0 ] ; then 
    echo 
    echo "Option -p is required: give the BIDS name of the participant." >&2
    echo
    exit 2 
fi 


# MRTRIX verbose or not?
if [ $silent -eq 1 ] ; then 

    export MRTRIX_QUIET=1

fi

# check suffix and use blank if not set
# Add a third condition here if needed
if [ -z $suffix ]; then

    suffix=""
    echo "No suffix is specified for dMRI data, a blank suffix will be used"
    echo "We will use the processed dMRIs in native diffusion space"

else

    echo "dMRI suffix is specified as ${suffix}"
    echo "We will use the processed dMRIs in native T1 space"

fi

# REST OF SETTINGS ---

# timestamp
start=$(date +%s)

# Some parallelisation
FSLPARALLEL=$ncpu; export FSLPARALLEL
OMP_NUM_THREADS=$ncpu; export OMP_NUM_THREADS

d=$(date "+%Y-%m-%d_%H-%M-%S")
log=log/log_${d}.txt


# --- MAIN ----------------

# make dirs
mkdir -p dwiprep/${group_name}/fba/subjects
if [ "$algo" = "ssst" ]; then 
    mkdir -p dwiprep/${group_name}/fba/dwiintensitynorm/dwi_input
    mkdir -p dwiprep/${group_name}/fba/dwiintensitynorm/mask_input
fi

cd dwiprep/${group_name}/fba

# find the preproced mifs

if [ ! -f data_prep.done ]; then
    
    echo "   Preparing data in dwiprep/${group_name}/fba/"
    
    search_subjects=($(find ${cwd}/dwiprep/sub-* -type f | grep dwi_preproced${suffix}.mif | sort ))
    num_sessions=${#search_subjects[@]}

    for i in ${search_subjects[@]}
    do

        sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
        #echo $i
        #echo $sub
        #echo $ses
        s=${sub}_${ses}
        mkdir -p ${cwd}/dwiprep/${group_name}/fba/subjects/${s}
        ln -sfn $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dwi_preproced${suffix}.mif
        if [ "$algo" = "ssst" ]; then 
            ln -sfn $i ${cwd}/dwiprep/${group_name}/fba/dwiintensitynorm/dwi_input/${s}_dwi_preproced${suffix}.mif
        fi

    done
 
    # find the preproced masks
    # need to make sure this is correct in case KUL_dwiprep_anat.sh is used in advance
    search_subjects=($(find ${cwd}/dwiprep -type f | grep dwi_mask${suffix}.nii.gz | sort ))
    num_subjects=${#search_subjects[@]}

    for i in ${search_subjects[@]}
    do

        sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
        s=${sub}_${ses}

        if [ "$algo" = "ssst" ]; then 
        
            mrconvert $i ${cwd}/dwiprep/${group_name}/fba/dwiintensitynorm/mask_input/${s}_dwi_preproced${suffix}.mif -force
        
        fi

    done
    

    if [ "$algo" = "ssmt" ] || [ "$algo" = "msmt" ]; then 

        # find the response functions
        search_subjects=($(find ${cwd}/dwiprep -type f | grep dhollander_csf_response.txt | sort ))
        num_subjects=${#search_subjects[@]}

        for i in ${search_subjects[@]}
        do

            #s=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
            s=${sub}_${ses}
            ln -sfn $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dhollander_csf_response.txt
        
        done

        # find the response functions
        search_subjects=($(find ${cwd}/dwiprep -type f | grep dhollander_gm_response.txt | sort ))
        num_subjects=${#search_subjects[@]}

        for i in ${search_subjects[@]}
        do

            #s=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
            s=${sub}_${ses}
            ln -sfn $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dhollander_gm_response.txt
        
        done

        # find the response functions
        search_subjects=($(find ${cwd}/dwiprep -type f | grep dhollander_wm_response.txt | sort ))
        num_subjects=${#search_subjects[@]}

        for i in ${search_subjects[@]}
        do

            #s=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
            s=${sub}_${ses}
            ln -sfn $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dhollander_wm_response.txt
        
        done
    
    fi

    echo "done" > data_prep.done

else

    echo "   Preparing data in dwiprep/${group_name}/fba/ already done"

fi


# Option to select certain shells from the data
if [ "$select_shells" = "" ]; then 

    echo "No shell selection, just continue"

else

    echo "Shells $select_shells will now be used in further analysis"
    echo "NOT YET IMPLEMENTED!!!!"

fi

# STEP 1 - Intensity Normalisation (only for ST data)
#dwiintensitynorm ../dwiintensitynorm/dwi_input/ ../dwiintensitynorm/mask_input/ ../dwiintensitynorm/dwi_output/ ../dwiintensitynorm/fa_template.mif        ../dwiintensitynorm/fa_template_wm_mask.mif

if [ "$algo" = "ssst" ]; then 

    if [ ! -f dwiintensitynorm/fa_template_wm_mask.mif ]; then

        echo "   Doing Intensity Normalisation"

        dwinromalise group dwiintensitynorm/dwi_input/ dwiintensitynorm/mask_input/ \
        dwiintensitynorm/dwi_output/ dwiintensitynorm/fa_template.mif \
        dwiintensitynorm/fa_template_wm_mask.mif -nthreads $ncpu -force

        mrinfo dwiintensitynorm/dwi_output/* -property dwi_norm_scale_factor > CHECK_dwi_norm_scale_factor.txt

    else

        echo "   Intensity Normalisation already done"

    fi

    # Adding a subject
    # dwi2tensor new_subject/dwi_denoised_unringed_preproc_unbiased.mif -mask new_subject/dwi_temp_mask.mif - | tensor2metric - -fa - | mrregister -force \
    # ../dwiintensitynorm/fa_template.mif - -mask2 new_subject/dwi_temp_mask.mif -nl_scale 0.5,0.75,1.0 -nl_niter 5,5,15 -nl_warp - /tmp/dummy_file.mif | \
    # mrtransform ../dwiintensitynorm/fa_template_wm_mask.mif -template new_subject/dwi_denoised_unringed_preproc_unbiased.mif -warp - - | dwinormalise \ 
    # new_subject/dwi_denoised_unringed_preproc_unbiased.mif - ../dwiintensitynorm/dwi_output/new_subject.mif

fi

# Link back the normalised data
cd ${cwd}/dwiprep/${group_name}/fba/subjects

if [ "$algo" = "ssst" ]; then 

    for_each * : ln -sfn ${cwd}/dwiprep/${group_name}/fba/dwiintensitynorm/dwi_output/PRE_dwi_preproced${suffix}.mif \
    ${cwd}/dwiprep/${group_name}/fba/subjects/IN/dwi_preproced${suffix}_normalised.mif

fi

# STEP 2 - Computing an (average) white matter response function
# foreach * : dwi2response tournier IN/dwi_denoised_unringed_preproc_unbiased_normalised.mif IN/response.txt

if [ ! -f ../average_response.done ]; then
    
    echo "   Computing an (average) white matter response function"
    
    if [ "$algo" = "ssst" ]; then 

        for_each * : dwi2response tournier IN/dwi_preproced${suffix}_normalised.mif \
        IN/response.txt -nthreads $ncpu -force

        responsemean */response.txt ../group_average_response.txt
    
    else
          
        responsemean */dhollander_wm_response.txt ../group_average_response_wm.txt
        responsemean */dhollander_gm_response.txt ../group_average_response_gm.txt
        responsemean */dhollander_csf_response.txt ../group_average_response_csf.txt

    fi

    if [ $? -eq 0 ]; then
        echo "done" > ../average_response.done
    fi

else

    echo "   Computing of an (average) white matter response function alrady done"

fi

# Use same masks generated by KUL_dwiprep
# foreach * : dwi2mask IN/dwi_denoised_unringed_preproc_unbiased_normalised_upsampled.mif IN/dwi_mask_upsampled.mif

search_subjects=($(find ${cwd}/dwiprep -type f | grep dwi_mask${suffix}.nii.gz | sort ))
num_subjects=${#search_subjects[@]}

if [ ! -f ../mask.done ]; then

    echo "   Compute new brain mask images"
        
    # if [ "$algo" = "ssst" ]; then 

        # for_each -nthreads ${ncpu_foreach} * : dwi2mask IN/dwi_preproced${suffix}_normalised.mif IN/dwi_preproced${suffix}_mask.mif -nthreads $ncpu -force
    
    # else

        for i in ${search_subjects[@]}; do

            sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
            ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
            s=${sub}_${ses}

            # this mask isn't really normalized but shouldn't matter so much
            mrconvert $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dwi_preproced${suffix}_mask.mif -force

        done

    # fi


    if [ $? -eq 0 ]; then
        echo "done" > ../mask.done
    fi

else

    echo "   Computing of new brain mask images already done"

fi

# STEP 3 - Fibre Orientation Distribution estimation (spherical deconvolution)
# see https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html
#  Note that dwi2fod csd can be used, however here we use dwi2fod msmt_csd (even with single shell data) to benefit from the hard non-negativity constraint, 
#  which has been observed to lead to more robust outcomes
# foreach * : dwiextract IN/dwi_denoised_unringed_preproc_unbiased_normalised_upsampled.mif - \| dwi2fod msmt_csd - ../group_average_response.txt IN/wmfod.mif -mask IN/dwi_mask_upsampled.mif

if [ ! -f ../fod_estimation.done ]; then
    
    echo "   Performing FOD estimation"

    if [ "$algo" = "ssst" ]; then 
    
        for_each -nthreads ${ncpu_foreach} * : dwiextract IN/dwi_preproced${suffix}_normalised.mif - \
        \| dwi2fod msmt_csd - ../group_average_response.txt IN/wmfod.mif \
        -mask IN/dwi_preproced${suffix}_mask.mif -nthreads $ncpu -force
    
    elif [ "$algo" = "ssmt" ]; then 

        for_each -nthreads ${ncpu_foreach} * : dwi2fod msmt_csd IN/dwi_preproced${suffix}.mif \
        ../group_average_response_wm.txt IN/wmfod_nogm.mif \
        ../group_average_response_csf.txt IN/csf_nogm.mif \
        -mask IN/dwi_preproced${suffix}_mask.mif -force

    elif [ "$algo" = "msmt" ]; then 

        for_each -nthreads ${ncpu_foreach} * : dwi2fod msmt_csd IN/dwi_preproced${suffix}.mif \
        ../group_average_response_wm.txt IN/wmfod_nogm.mif \
        ../group_average_response_csf.txt IN/csf_nogm.mif \
        -mask IN/dwi_preproced${suffix}_mask.mif -force

    fi

    if [ $? -eq 0 ]; then
        echo "done" > ../fod_estimation.done
    fi

fi

# STEP 3B - for multi-tissue only - Joint bias field correction and intensity normalisation

if [ "$algo" = "msmt" ]; then 

    if [ ! -f ../mtnormalise.done ]; then

        for_each -nthreads ${ncpu_foreach} * : mtnormalise IN/wmfod.mif IN/wmfod_norm.mif \
        IN/gm.mif IN/gm_norm.mif IN/csf.mif IN/csf_norm.mif \
        -mask IN/dwi_preproced${suffix}_mask.mif

        if [ $? -eq 0 ]; then
            echo "done" > ../mtnormalise.done
        fi

    fi

elif [ "$algo" = "ssmt" ]; then 

    if [ ! -f ../mtnormalise.done ]; then

        for_each -nthreads ${ncpu_foreach} * : mtnormalise IN/wmfod_nogm.mif IN/wmfod_norm.mif \
        IN/csf_nogm.mif IN/csf_norm.mif \
        -mask IN/dwi_preproced${suffix}_mask.mif

        if [ $? -eq 0 ]; then
            echo "done" > ../mtnormalise.done
        fi

    fi

fi

# STEP 4 - Generate a study-specific unbiased FOD template
mkdir -p ../template/fod_input
mkdir -p ../template/mask_input

declare -a links

templatesubjects_a=(${templatesubjects})

echo ${templatesubjects_a[@]}

if [ ! -f ../template/wmfod_template.mif ]; then

    echo "   Generating FOD template"

    # search_sessions=($(find ${cwd}/dwiprep/${group_name}/fba/subjects | grep wmfod_norm.mif | sort ))
    search_sessions=($(ls -f ${cwd}/dwiprep/${group_name}/fba/subjects/*/wmfod_norm.mif | sort ))

    for t in ${!search_sessions[@]}; do

        #links[$bb]=1
        # s=$(echo $t | awk -F 'subjects/' '{print $2}' | awk -F '/' '{print $1}')
        s=$(echo ${search_sessions[$t]} | rev | cut -d '/' -f2 | rev)
        # echo $s
        # echo $t

        if [ $t_flag -eq 1 ]; then
            # Don't link subjects not given in -t
            for hb in ${!templatesubjects_a[@]}; do

                # echo "${templatesubjects_a[$hb]}"
              
                if [[ "${s}" == "${templatesubjects_a[$hb]}" ]]; then

                    ln -sfn ${search_sessions[$t]} ${cwd}/dwiprep/${group_name}/fba/template/fod_input/${s}_wmfod_norm.mif
            
                    ln -sfn ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dwi_preproced${suffix}_*mask.mif \
                    ${cwd}/dwiprep/${group_name}/fba/template/mask_input/${s}_mask.mif

                fi

            done

        else

            ln -sfn ${search_sessions[$t]} ${cwd}/dwiprep/${group_name}/fba/template/fod_input/${s}_wmfod_norm.mif
            
            ln -sfn ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/dwi_preproced${suffix}_*mask.mif \
            ${cwd}/dwiprep/${group_name}/fba/template/mask_input/${s}_mask.mif

        fi

    done

    population_template  ../template/fod_input -mask_dir ../template/mask_input ../template/wmfod_template.mif \
    -voxel_size 1.3 -nthreads $ncpu

else

    echo "   FOD template already generated"

fi

# Register all subject FOD images to the FOD template
# foreach -${ncpu_foreach} * : mrregister IN/wmfod.mif -mask1 IN/dwi_mask_upsampled.mif ../template/wmfod_template.mif -nl_warp IN/subject2template_warp.mif IN/template2subject_warp.mif

if [ ! -f ../fod_reg2template.done ]; then

    echo "   Registering all subject FOD images to the FOD template"

    # at this point ssst, ssmt, and msmt are the same no?

    for_each -nthreads ${ncpu_foreach} * : mrregister IN/wmfod_norm.mif -mask1 IN/dwi_preproced${suffix}_mask.mif \
    ../template/wmfod_template.mif \
    -nl_warp IN/subject2template_warp.mif IN/template2subject_warp.mif -nthreads $ncpu -force

    if [ $? -eq 0 ]; then
        echo "done" > ../fod_reg2template.done
    fi

else 

    echo "   Registration of all subject FOD images to the FOD template already done"

fi

# Compute the template mask (intersection of all subject masks in template space)
#foreach * : mrtransform IN/dwi_mask_upsampled.mif -warp IN/subject2template_warp.mif -interp nearest -datatype bit IN/dwi_mask_in_template_space.mif

if [ ! -f ../template/template_mask.mif ]; then

    echo "   Compute the template mask"

    if [ "$algo" = "ssst" ]; then 
        
        for_each -nthreads ${ncpu_foreach} * : mrtransform IN/dwi_preproced${suffix}_normalised_mask.mif -warp IN/subject2template_warp.mif \
        -interp nearest -datatype bit IN/dwi_mask_in_template_space.mif -nthreads $ncpu -force

    else

        for_each -nthreads ${ncpu_foreach} * : mrtransform IN/dwi_preproced${suffix}_mask.mif -warp IN/subject2template_warp.mif \
        -interp nearest -datatype bit IN/dwi_mask_in_template_space.mif -nthreads $ncpu -force

    fi
    
    mrmath */dwi_mask_in_template_space.mif min ../template/template_mask.mif -datatype bit -nthreads $ncpu

else

    echo "   Computation of the template mask already done"

fi



# Compute a white matter template analysis fixel mask
# fod2fixel -mask ../template/template_mask.mif -fmls_peak_value 0.10 ../template/wmfod_template.mif ../template/fixel_mask

if [ ! -d ../template/fixel_mask ]; then

    echo "   Compute a white matter template analysis fixel mask"
    fod2fixel -mask ../template/template_mask.mif -fmls_peak_value 0.10 ../template/wmfod_template.mif ../template/fixel_mask -nthreads $ncpu -force

else

    echo "   Computation of a white matter template analysis fixel mask already done"

fi

# Warp FOD images to template space
#foreach * : mrtransform IN/wmfod.mif -warp IN/subject2template_warp.mif -noreorientation IN/fod_in_template_space_NOT_REORIENTED.mif

if [ ! -f ../fod_warp.done ]; then
    
    # if [ $mrtrix3new ]
    echo "   Warping FOD images to template space"
    for_each -nthreads ${ncpu_foreach} * : mrtransform IN/wmfod_norm.mif -warp IN/subject2template_warp.mif \
    IN/fod_in_template_space_NOT_REORIENTED.mif -reorient_fod 0 -nthreads $ncpu -force

    for_each -nthreads ${ncpu_foreach} * : mrtransform IN/wmfod_norm.mif -warp IN/subject2template_warp.mif \
    IN/fod_in_template_space_REORIENTED.mif -reorient_fod 1 -nthreads $ncpu -force

    if [ $? -eq 0 ]; then
        echo "done" > ../fod_warp.done
    fi

else

    echo "   Warping FOD images to template space already done"

fi  

# Make FA/ADC images in template space

if [ ! -f ../fa_adc_warp.done ]; then
    
    # find the FA in subject space
    search_sessions=($(find ${cwd}/dwiprep/sub-* -type f | grep qa/fa${suffix}.nii.gz | sort ))
    num_sessions=${#search_sessions[@]}

    for i in ${search_sessions[@]}
    do
        # s=$(echo $i | awk -F 'subjects/' '{print $2}' | awk -F '/' '{print $1}')
        # s=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
        s=${sub}_${ses}
        echo $i
        echo $s
        mrconvert $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/FA_subj_space.mif -force

    done

    # exit 2

    # find the ADC in subject space
    search_sessions=($(find ${cwd}/dwiprep/sub-* -type f | grep qa/adc${suffix}.nii.gz | sort ))
    num_sessions=${#search_sessions[@]}

    for i in ${search_sessions[@]}
    do

        # s=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        # s=$(echo $i | awk -F 'subjects/' '{print $2}' | awk -F '/' '{print $1}')
        sub=$(echo $i | awk -F 'sub-' '{print $2}' | awk -F '/' '{print $1}')
        ses=$(echo $i | awk -F 'ses-' '{print $2}' | awk -F '/' '{print $1}')
        s=${sub}_${ses}
        mrconvert $i ${cwd}/dwiprep/${group_name}/fba/subjects/${s}/ADC_subj_space.mif -force

    done

    echo "   Warping FA/ADC images to template space"
    for_each -nthreads ${ncpu_foreach} * : mrtransform IN/FA_subj_space.mif -warp IN/subject2template_warp.mif \
      IN/FA_in_template_space.nii.gz -nthreads $ncpu -force
    for_each -nthreads ${ncpu_foreach} * : mrtransform IN/ADC_subj_space.mif -warp IN/subject2template_warp.mif \
      IN/ADC_in_template_space.nii.gz -nthreads $ncpu -force

    if [ $? -eq 0 ]; then
        echo "done" > ../fa_adc_warp.done
    fi

    mkdir -p ../template/fa
    #ln -sfn ${cwd}/dwiprep/${group_name}/fba/dwiintensitynorm/dwi_output
    for_each -nthreads ${ncpu_foreach} * : ln -sfn ${cwd}/dwiprep/${group_name}/fba/subjects/IN/FA_in_template_space.nii.gz ${cwd}/dwiprep/${group_name}/fba/template/fa/sub_IN_FA.nii.gz
    mkdir -p ../template/adc
    for_each -nthreads ${ncpu_foreach} * : ln -sfn ${cwd}/dwiprep/${group_name}/fba/subjects/IN/ADC_in_template_space.nii.gz ${cwd}/dwiprep/${group_name}/fba/template/adc/sub_IN_ADC.nii.gz

else

    echo "   Warping FA/ADC images to template space already done"

fi  

# Segment FOD images to estimate fixels and their apparent fibre density (FD)
#foreach * : fod2fixel -mask ../template/template_mask.mif IN/fod_in_template_space_NOT_REORIENTED.mif IN/fixel_in_template_space_NOT_REORIENTED -afd fd.mif

if [ ! -f ../fod_segment.done ]; then

    echo "   Segment FOD images to estimate fixels and their apparent fibre density (FD)"
    for_each -nthreads ${ncpu_foreach} * : fod2fixel -mask ../template/template_mask.mif IN/fod_in_template_space_NOT_REORIENTED.mif \
     IN/fixel_in_template_space_NOT_REORIENTED -afd fd.mif -nthreads $ncpu -force

    if [ $? -eq 0 ]; then
        echo "done" > ../fod_segment.done
    fi

else

    echo "   Segmenting of FOD images to estimate fixels and their apparent fibre density (FD) already done"

fi

# Reorient fixels
#foreach * : fixelreorient IN/fixel_in_template_space_NOT_REORIENTED IN/subject2template_warp.mif IN/fixel_in_template_space

if [ ! -f ../fod_reor_fixels.done ]; then

    echo "   Reorient fixels"
    for_each -nthreads ${ncpu_foreach} * : fixelreorient IN/fixel_in_template_space_NOT_REORIENTED IN/subject2template_warp.mif \
    IN/fixel_in_template_space -nthreads $ncpu -force

    if [ $? -eq 0 ]; then
        echo "done" > ../fod_reor_fixels.done
    fi

else

    echo "   Reorient fixels already done"

fi

# Assign subject fixels to template fixels
# foreach * : fixelcorrespondence IN/fixel_in_template_space/fd.mif ../template/fixel_mask ../template/fd PRE.mif
# Note: do NOT run in PARALLEL
if [ ! -f ../assign_fixels.done ]; then

    echo "   Assign subject fixels to template fixels"
    for_each -nthreads ${ncpu_foreach} * : fixelcorrespondence IN/fixel_in_template_space/fd.mif \
    ../template/fixel_mask ../template/fd PRE.mif -force
  
    if [ $? -eq 0 ]; then
        echo "done" > ../assign_fixels.done
    fi

else

    echo "   Assign subject fixels to template fixels already done"

fi


# Compute the fibre cross-section (FC) metric
# IT IS possible that the script will exit at this stage with an error
# This seems to relate to the presence of an index file in the template/fc folder
# IT runs just fine if simply restarted and doesn't quit with fd or fdc
# THESE steps are in accordance with the guide on https://mrtrix.readthedocs.io/en/latest/fixel_based_analysis/st_fibre_density_cross-section.html
if [ ! -f ../compute_fc.done ]; then

    echo "   Compute the fibre cross-section (FC) metric"
    for_each -nthreads ${ncpu_foreach} * : warp2metric IN/subject2template_warp.mif -fc ../template/fixel_mask ../template/fc IN.mif -force
  
    if [ $? -eq 0 ]; then
        echo "done" > ../compute_fc.done
    fi

else

    echo "   Compute the fibre cross-section (FC) metric already done"

fi


if [ ! -f ../compute_log_fc.done ]; then

    echo "   Compute the fibre cross-section LOG-(FC) metric"
    mkdir -p ../template/log_fc
    cp ../template/fc/index.mif ../template/fc/directions.mif ../template/log_fc
    for_each * : mrcalc ../template/fc/IN.mif -log ../template/log_fc/IN.mif -force

   if [ $? -eq 0 ]; then
        echo "done" > ../compute_log_fc.done
    fi

else
    
    echo "   Compute the fibre cross-section LOG-(FC) metric already done"

fi

# Compute a combined measure of fibre density and cross-section (FDC)
if [ ! -f ../compute_fdc.done ]; then

    echo "   Compute a combined measure of fibre density and cross-section (FDC)"
    mkdir -p ../template/fdc
    cp ../template/fc/index.mif ../template/fdc
    cp ../template/fc/directions.mif ../template/fdc
    for_each -nthreads ${ncpu_foreach} * : mrcalc ../template/fd/IN.mif ../template/fc/IN.mif -mult ../template/fdc/IN.mif -force

   if [ $? -eq 0 ]; then
        echo "done" > ../compute_fdc.done
    fi
    
else
    
    echo "   Compute the fibre cross-section LOG-(FC) metric already done"

fi

# Perform whole-brain fibre tractography on the FOD template
cd ../template
if [ ! -f ../tckgen.done ]; then

    n=20000000

    echo "   Perform whole-brain fibre tractography on the FOD template"
    tckgen -angle 22.5 -maxlen 250 -minlen 10 -power 1.0 wmfod_template.mif -seed_image template_mask.mif \
     -mask template_mask.mif -select $n -cutoff 0.10 tracks_20_million.tck
    
    if [ $? -eq 0 ]; then
        echo "done" > ../tckgen.done
    fi
    
else
    
    echo "   Whole brain fibre tractography already done"

fi



# Reduce biases in tractogram densities
# tcksift tracks_20_million.tck wmfod_template.mif tracks_2_million_sift.tck -term_number 200000
if [ ! -f ../tckshift.done ]; then

    echo "   Reduce biases in tractogram densities"

    n=2000000

    tcksift tracks_20_million.tck wmfod_template.mif tracks_2_million_sift.tck -term_number $n
    
    if [ $? -eq 0 ]; then
        echo "done" > ../tckshift.done
    fi
    
else
    
    echo "   Reduce biases in tractogram densities already done"

fi



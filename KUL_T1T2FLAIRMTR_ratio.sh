#!/bin/bash 
# Sarah Cappelle & Stefan Sunaert
# 22/12/2020
# This script is the first part of Sarah's Study1
# This script computes a T1/T2, T1/FLAIR and MTC (magnetisation transfer contrast) ratio
# 
# This scripts follows the rationale of D. Pareto et al. AJNR 2020
# Starting from 3D-T1w, 3D-FLAIR and 2D-T2w scans we compute:
#  create masked brain images using HD-BET
#  bias correct the images using N4biascorrect from ANTs
#  ANTs rigid coregister and reslice all images to the 3D-T1w (in isotropic 1 mm space)
#  compute a T1FLAIR_ratio, a T1T2_ratio and a MTR
v="1.0"

kul_main_dir=`dirname "$0"`
script=$0
source $kul_main_dir/KUL_main_functions.sh
cwd=$(pwd)

# FUNCTIONS --------------

# function Usage
function Usage {

cat <<USAGE

`basename $0` computes a T1/T2 and a T1/FLAIR ratio image.

Usage:

  `basename $0` <OPT_ARGS>

Example:

  `basename $0` -p JohnDoe -v 

Required arguments:

     -p:  participant name


Optional arguments:

     -s:  session of the participant
     -a:  automatic mode (just work on all images in the BIDS folder)
     -n:  number of cpu to use (default 15)
     -m:  also run MS lesion segmentation using Freesurfer7 SamSeg
     -v:  show output from commands


USAGE

	exit 1
}


# CHECK COMMAND LINE OPTIONS -------------
#
# Set defaults
auto=0 # default if option -s is not given
silent=1 # default if option -v is not given
outputdir="$cwd/T1T2FLAIRMTR_ratio"
ms=0
ncpu=15

# Set required options
#p_flag=0

if [ "$#" -lt 1 ]; then
	Usage >&2
	exit 1

else

	while getopts "p:s:n:amv" OPT; do

		case $OPT in
		a) #automatic mode
			auto=1
		;;
		p) #participant
			participant=$OPTARG
		;;
        s) #session
			session=$OPTARG
		;;
        n) #ncpu
			ncpu=$OPTARG
		;;
        m) #MS lesion segmentation
			ms=1
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
#if [ $p_flag -eq 0 ] ; then
#	echo
#	echo "Option -p is required: give the BIDS name of the participant." >&2
#	echo
#	exit 2
#fi

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${ncpu}
ants_verbose=1
fs_silent=""
# verbose or not?
if [ $silent -eq 1 ] ; then
	export MRTRIX_QUIET=1
    ants_verbose=0
    fs_silent=" > /dev/null 2>&1" 
fi

d=$(date "+%Y-%m-%d_%H-%M-%S")
log=log/log_${d}.txt

# --- FUNCTIONS ---

function KUL_antsApply_Transform {
    antsApplyTransforms -d 3 \
    --verbose $ants_verbose \
    -i $input \
    -o $output \
    -r $reference \
    -t $transform \
    -n Linear
}
function KUL_antsApply_Transform_MNI {
    antsApplyTransforms -d 3 \
        --verbose $ants_verbose \
        -i $input \
        -o $output \
        -r $reference \
        -t $transform1 -t $transform2 \
        -n NearestNeighbor
}

function KUL_reorient_crop_hdbet_biascorrect_iso {
    fslreorient2std $input $outputdir/compute/${output}_std
    mrgrid $outputdir/compute/${output}_std.nii.gz regrid -voxel 1 $outputdir/compute/${output}_std_iso.nii.gz -force
    #mrgrid $outputdir/compute/${output}_std_iso.nii.gz crop -axis 0 $crop_x,$crop_x -axis 2 $crop_z,0 \
    #        $outputdir/compute/${output}_std_iso_cropped.nii.gz -nthreads $ncpu -force
    #result=$(hd-bet -i $outputdir/compute/${output}_std_cropped.nii.gz -o $outputdir/compute/${output}_std_cropped_brain.nii.gz 2>&1)
    #if [ $silent -eq 0 ]; then
    #    echo $result
    #fi 
    bias_input=$outputdir/compute/${output}_std_iso.nii.gz
    #mask=$outputdir/compute/${output}_std_cropped_mask.nii.gz
    bias_output=$outputdir/compute/${output}_std_iso_biascorrected.nii.gz
    N4BiasFieldCorrection --verbose $ants_verbose \
     -d 3 \
     -i $bias_input \
     -o $bias_output
    #iso_output=$outputdir/compute/${output}_std_cropped_brain_biascorrected_iso.nii.gz
    #mrgrid $bias_output regrid -voxel 1 $iso_output -force
    #iso_output2=$outputdir/compute/${output}_std_cropped_brain_mask_iso.nii.gz
    #mrgrid $mask regrid -voxel 1 $iso_output2 -nthreads $ncpu -force
    #iso_output3=$outputdir/compute/${output}_std_cropped_iso.nii.gz
    #mrgrid $outputdir/compute/${output}_std_cropped.nii.gz regrid -voxel 1 $iso_output3 -nthreads $ncpu -force
}

function KUL_MTI_reorient_crop_hdbet_iso {
    fslreorient2std $input $outputdir/compute/${output}_std
    mrgrid $outputdir/compute/${output}_std.nii.gz crop -axis 0 $crop_x,$crop_x -axis 2 $crop_z,0 \
        $outputdir/compute/${output}_std_cropped.nii.gz -nthreads $ncpu -force
    mrmath $outputdir/compute/${output}_std_cropped.nii.gz mean $outputdir/compute/${output}_mean_std_cropped.nii.gz -axis 3 -nthreads $ncpu
    result=$(hd-bet -i $outputdir/compute/${output}_mean_std_cropped.nii.gz -o $outputdir/compute/${output}_mean_std_cropped_brain.nii.gz 2>&1)
    if [ $silent -eq 0 ]; then
        echo $result
    fi 
    mrcalc $outputdir/compute/${output}_std_cropped.nii.gz $outputdir/compute/${output}_mean_std_cropped_brain_mask.nii.gz \
        -mul $outputdir/compute/${output}_std_cropped_brain.nii.gz -force
    iso_output=$outputdir/compute/${output}_std_cropped_brain_iso.nii.gz
    mrgrid $outputdir/compute/${output}_std_cropped_brain.nii.gz regrid -voxel 1 $iso_output -force
}

# Rigidly register the input to the T1w
function KUL_rigid_register {
antsRegistration --verbose $ants_verbose --dimensionality 3 \
    --output [$outputdir/compute/${ants_type},$outputdir/compute/${newname}] \
    --interpolation BSpline \
    --use-histogram-matching 0 --winsorize-image-intensities [0.005,0.995] \
    --initial-moving-transform [$outputdir/compute/$ants_template,$outputdir/compute/$ants_source,1] \
    --transform Rigid[0.1] \
    --metric MI[$outputdir/compute/$ants_template,$outputdir/compute/$ants_source,1,32,Regular,0.25] \
    --convergence [1000x500x250x100,1e-6,10] \
    --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox

    # also apply the registration to the mask
    #input=$mask
    #output=${mask##*/}
    #output=${output%%.*}
    #output=$outputdir/compute/${output}_reg2T1w.nii.gz
    #transform=$outputdir/compute/${ants_type}0GenericAffine.mat
    #reference=$outputdir/compute/$ants_template
    #echo "input $input"
    #echo "output $output"
    #echo "transform $transform"
    #echo "reference $reference"
    #KUL_antsApply_Transform
}

# Register and compute the ratio
function KUL_register_computeratio {
    base0=${test_T1w##*/}
    base=${base0%_T1w*}
    ants_type="${base}_rigid_${td}_reg2t1_"
    ants_template="${base}_T1w_std_iso_biascorrected_calibrated.nii.gz"
    ants_source="${base}_${td}_std_iso_biascorrected.nii.gz"
    newname="${base}_${td}_std_iso_biascorrected_reg2T1w.nii.gz"
    finalname="${base}_${td}_reg2T1w.nii.gz"
    KUL_rigid_register

    # Calibrate
    echo " Performing linear histogram matching"
    mrhistmatch -mask_input $outputdir/compute/${base}_eye_and_muscle.nii.gz \
        -mask_target /tmp/mni_eye_and_muscle.nii.gz \
        linear \
        $outputdir/compute/$newname \
        $HOME/KUL_apps/spm12/toolbox/MRTool/template/mni_icbm152_t2_tal_nlin_sym_09a.nii \
        $outputdir/compute/${base}_${td}_std_iso_biascorrected_calibrated_reg2T1w.nii.gz -force
    
    # make a better mask
    result=$(hd-bet -i $outputdir/compute/${base}_${td}_std_iso_biascorrected_calibrated_reg2T1w.nii.gz \
     -o $outputdir/compute/${base}_${td}_std_iso_biascorrected_calibrated_brain_reg2T1w.nii.gz 2>&1)
    if [ $silent -eq 0 ]; then
        echo $result
    fi 
    #maskfilter ${output} erode $outputdir/compute/${base}_${td}_mask_eroded.nii.gz -nthreads $ncpu -force
    
    #mrcalc $outputdir/compute/$ants_template $outputdir/compute/$newname -divide \
    #    $outputdir/${base}_T1${td}_ratio_a.nii.gz
    mrcalc $outputdir/compute/$ants_template $outputdir/compute/${base}_${td}_std_iso_biascorrected_calibrated_brain_reg2T1w.nii.gz -divide \
        $outputdir/compute/${base}_${td}_std_iso_biascorrected_calibrated_brain_reg2T1w_mask.nii.gz -multiply \
        $outputdir/${base}_T1${td}_ratio.nii.gz -nthreads $ncpu -force
    cp $outputdir/compute/$newname $outputdir/$finalname
}

function KUL_MTI_register_computeratio {
    base0=${test_T1w##*/}
    base=${base0%_T1w*}
    # convert the 4D MTI to single 3Ds
    input="$outputdir/compute/${base}_${td}_std_cropped_brain_iso.nii.gz"
    S0="$outputdir/compute/${base}_${td}_std_cropped_brain_iso_S0.nii.gz"
    Smt="$outputdir/compute/${base}_${td}_std_cropped_brain_iso_Smt.nii.gz"
    mrconvert $input -coord 3 0 $S0 -force
    mrconvert $input -coord 3 1 $Smt -force
    # determine the registration
    ants_type="${base}_rigid_${td}_reg2t1_"
    ants_template="${base}_T1w_std_iso_biascorrected_calibrated.nii.gz"
    ants_source="${base}_${td}_std_cropped_brain_iso_Smt.nii.gz"
    newname="${base}_${td}_std_cropped_brain_iso_Smt_reg2T1w.nii.gz"
    finalname="${base}_${td}_reg2T1w.nii.gz"
    KUL_rigid_register
    Smt="$outputdir/compute/$newname"
    # Now apply the coregistration to the 4D MTI 
    input=$S0
    output="$outputdir/compute/${base}_${td}_std_cropped_brain_iso_S0_reg2T1w.nii.gz"
    S0=$output
    transform="$outputdir/compute/${base}_rigid_${td}_reg2t1_0GenericAffine.mat"
    reference="$outputdir/compute/${base}_T1w_std_cropped_brain_biascorrected_iso.nii.gz"
    KUL_antsApply_Transform
    # make a better mask
    mask=$outputdir/compute/${base}_T1w_std_cropped_brain_mask_iso.nii.gz
    # MTR formula: (S0 - Smt)/S0
    mrcalc $S0 $Smt -subtract $S0 -divide $mask -multiply \
     $outputdir/${base}_MTC_ratio.nii.gz -nthreads $ncpu -force
    cp $outputdir/compute/$newname $outputdir/$finalname
}

# --- MAIN ---
printf "\n\n\n"

# here we give the data
if [ $auto -eq 0 ]; then
    datadir="$cwd/BIDS/sub-${participant}/ses-$session/anat"
    T1w=("$datadir/sub-${participant}_ses-${session}_T1w.nii.gz")
    T2w=("$datadir/sub-${participant}_ses-${session}_T2w.nii.gz")
    FLAIR=("$datadir/sub-${participant}_ses-${session}_FLAIR.nii.gz")
    MTI=("$datadir/sub-${participant}_ses-${session}_MTI.nii.gz")
else
    T1w=($(find BIDS -type f -name "*T1w.nii.gz" | sort ))
fi

d=0
t2=0
flair=0
mti=0
for test_T1w in ${T1w[@]}; do

    base0=${test_T1w##*/};base=${base0%_T1w*}
    check_done="$outputdir/compute/${base}.done"
    check_done2="$outputdir/${base}_T1w.nii.gz"

    if [ ! -f $check_done2 ];then

        # Test whether T2 and/or FLAIR also exist
        test_T2w="${test_T1w%_T1w*}_T2w.nii.gz"
        if [ -f $test_T2w ];then
            #echo "The T2 exists"
            d=$((d+1))
            t2=1
        fi
        test_FLAIR="${test_T1w%_T1w*}_FLAIR.nii.gz"
        if [ -f $test_FLAIR ];then
            #echo "The FLAIR exists"
            d=$((d+1))
            flair=1
        fi
        test_MTI="${test_T1w%_T1w*}_MTI.nii.gz"
        if [ -f $test_MTI ];then
            #echo "The MTI exists"
            d=$((d+1))
            mti=1
        fi

        # If a T2 and/or a FLAIR exists
        if [ $d -gt 0 ]; then
            mkdir -p $outputdir/compute
            mkdir -p $outputdir/log
            kul_e2cl "KUL_T1T2FLAIR_ratio is starting" ${outputdir}/${log}
            

            # for the T1w
            input=$test_T1w
            output=${test_T1w##*/}
            output=${output%%.*}
            echo " doing biascorrection on image $output"
            crop_x=0
            crop_z=0
            KUL_reorient_crop_hdbet_biascorrect_iso
            mask_T1W=$mask
            #cp $iso_output $outputdir/${base}_T1w.nii.gz

            #KUL_normalise_T1w
            fix_im="$HOME/KUL_apps/spm12/toolbox/MRTool/template/mni_icbm152_t1_tal_nlin_sym_09a.nii"
            mov_im=$bias_output
            output="$outputdir/compute/${base}_T1w2MNI_"
            if [ ! -f $outputdir/compute/${base}_T1w2MNI_Warped.nii.gz ]; then 
                echo " starting MNI spatial normalisation (takes about 20 minutes)"
                antsRegistrationSyN.sh -d 3 -f ${fix_im} -m ${mov_im} -o ${output} -n ${ncpu} -j 1 -t s
            else
                eho " skipping MNI spatial normalisation, since it exists already"
            fi
            
            # Warp the eye and muscle back to subject space
            input="$HOME/KUL_apps/spm12/toolbox/MRTool/template/eyemask.nii"
            output="$outputdir/compute/${base}_eye.nii.gz"
            reference=$mov_im
            transform1="$outputdir/compute/${base}_T1w2MNI_1InverseWarp.nii.gz"
            transform2="[$outputdir/compute/${base}_T1w2MNI_0GenericAffine.mat,1]"
            KUL_antsApply_Transform_MNI

            input="$HOME/KUL_apps/spm12/toolbox/MRTool/template/tempmask.nii"
            output="$outputdir/compute/${base}_tempmuscle.nii.gz"
            KUL_antsApply_Transform_MNI
            
            # sum the masks
            echo " Performing linear histogram matching"
            mrcalc $outputdir/compute/${base}_eye.nii.gz $outputdir/compute/${base}_tempmuscle.nii.gz -add \
             $outputdir/compute/${base}_eye_and_muscle.nii.gz -force
            mrcalc $HOME/KUL_apps/spm12/toolbox/MRTool/template/eyemask.nii $HOME/KUL_apps/spm12/toolbox/MRTool/template/tempmask.nii -add \
             /tmp/mni_eye_and_muscle.nii.gz -force
            
            mrhistmatch -mask_input $outputdir/compute/${base}_eye_and_muscle.nii.gz \
             -mask_target /tmp/mni_eye_and_muscle.nii.gz \
             linear \
             $bias_output \
             $HOME/KUL_apps/spm12/toolbox/MRTool/template/mni_icbm152_t1_tal_nlin_sym_09a.nii \
             $outputdir/compute/${base}_T1w_std_iso_biascorrected_calibrated.nii.gz -force

            cp $outputdir/compute/${base}_T1w_std_iso_biascorrected_calibrated.nii.gz $outputdir/${base}_T1w.nii.gz

            if [ $t2 -eq 1 ];then
                input=$test_T2w
                output=${test_T2w##*/}
                output=${output%%.*}
                crop_x=0
                crop_z=0
                echo " doing biascorrection of the T2w"
                KUL_reorient_crop_hdbet_biascorrect_iso

                td="T2w"
                echo " coregistering T2 to T1 and computing the ratio"
                KUL_register_computeratio
            fi

            if [ $flair -eq 1 ];then
                input=$test_FLAIR
                output=${test_FLAIR##*/}
                output=${output%%.*}
                crop_x=0
                crop_z=0
                echo " doing biascorrection of the FLAIR"
                KUL_reorient_crop_hdbet_biascorrect_iso
                
                td="FLAIR"
                echo " coregistering FLAIR to T1 and computing the ratio"
                KUL_register_computeratio
            fi

            # if MS lesion segmentation
            if [ $ms -eq 1 ];then
                if [ $flair -eq 1 ];then
                    echo " running samseg (takes about 20 minutes)"
                    T1w_iso="$outputdir/${base}_T1w.nii.gz"
                    FLAIR_reg2T1w="$outputdir/${base}_FLAIR_reg2T1w.nii.gz"
                    my_cmd="run_samseg --input $T1w_iso $FLAIR_reg2T1w --pallidum-separate \
                     --lesion --lesion-mask-pattern 0 1 --output $cwd/$outputdir/compute/${base}_samsegOutput \
                     --threads $ncpu $fs_silent"
                    eval $my_cmd
                    SamSeg="$cwd/$outputdir/compute/${base}_samsegOutput/seg.mgz"
                    MSlesion="$cwd/$outputdir/${base}_MSLesion.nii.gz"
                    mrcalc $SamSeg 99 -eq $MSlesion -force -nthreads $ncpu
                else
                    echo " Warning! No Flair available to do lesion MS segmentation"
                fi        
            fi

            if [ $mti -eq 1 ];then
                input=$test_MTI
                output=${test_MTI##*/}
                output=${output%%.*}
                crop_x=0
                crop_z=0
                echo " doing hd-bet of the MTI"
                KUL_MTI_reorient_crop_hdbet_iso
                td="MTI"
                echo " coregistering MTI to T1 and computing the MTC ratio"
                KUL_MTI_register_computeratio
            fi

            #rm -fr $outputdir/compute/${base}*.gz
            touch $check_done

            echo " done"

        else
            echo " Nothing to do here"
        fi

    else
        echo " $base already done"
    fi

done

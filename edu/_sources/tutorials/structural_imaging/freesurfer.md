---
title: FreeSurfer
linkTitle: FreeSurfer
weight: 1
aliases:
- /tutorials/structural_imaging/freesurfer
description: Example workflow for FreeSurfer
authors:
- name: Steffen Bollmann
- name: Michèle Masson-Trottier
date: '2026-10-20'
---
# FreeSurfer

**Authors:** Steffen Bollmann, Michèle Masson-Trottier

**Last updated:** 20 October 2026

:::{admonition} Learning Objectives
:class: tip

By the end of this tutorial you will be able to:

- Launch FreeSurfer and its Freeview viewer.
- Open anatomical images and add segmentation or surface overlays.
- Use the slice, visibility and display controls to inspect the result.
:::


Example workflow for FreeSurfer

> _This tutorial was created by Steffen Bollmann._
>
> Github: [@stebo85](https://github.com/stebo85)
> Web: [mri.sbollmann.net](https://mri.sbollmann.net/)
> Twitter: [@sbollmann_MRI](https://twitter.com/sbollmann_MRI)

<!-- Following line adds a link to getting set up with Neurodesk -->
[Getting Set Up with Neurodesk](https://neurodesk.org/getting-started/)
<!-- -->

## FreeSurfer Example using module load (e.g. on an HPC)
Download data:
```
osf -p bt4ez fetch osfstorage/TOMCAT_DIB/sub-01/ses-01_7T/anat/sub-01_ses-01_7T_T1w_defaced.nii.gz sub-01_ses-01_7T_T1w_defaced.nii.gz
```

Setup FreeSurfer:
```
ml freesurfer/7.3.2
export SUBJECTS_DIR=$PWD/freesurfer-output
mkdir $SUBJECTS_DIR
export SINGULARITYENV_SUBJECTS_DIR=$SUBJECTS_DIR
export APPTAINERENV_SUBJECTS_DIR=$SUBJECTS_DIR
```

Run Recon all pipeline:
```
recon-all -subject test-subject -i sub-01_ses-01_7T_T1w_defaced.nii.gz -all
```

When using Freesurfer >8.0.0:
```
export FS_ALLOW_DEEP=1
export APPTAINERENV_FS_ALLOW_DEEP=$FS_ALLOW_DEEP
export SINGULARITYENV_FS_ALLOW_DEEP=$FS_ALLOW_DEEP
```

When running on a GPU, make sure to check if this is set:
```
export neurodesk_singularity_opts='--nv'
```

## Alternative instructions for using Freesurfer via the Neurodesk application menu
### Download demo data
Open a terminal and run:
```
pip install osfclient
osf -p bt4ez fetch TOMCAT_DIB/sub-01/ses-01_7T/anat/sub-01_ses-01_7T_T1w_defaced.nii.gz /neurodesktop-storage/sub-01_ses-01_7T_T1w_defaced.nii.gz
```

### FreeSurfer License file:
Before using Freesurfer you need to request a license here (https://surfer.nmr.mgh.harvard.edu/registration.html) and store it in your homedirectory as ~/.license

### FreeSurfer Example
Open FreeSurfer (Neurodesk -> Image Segmentation -> Freesurfer -> Freesurfer 7.1.1)

Current FreeSurfer containers may supply a license. Check the launch terminal for its location. If your selected version requires a personal license, obtain it from the [FreeSurfer registration page](https://surfer.nmr.mgh.harvard.edu/registration.html), save it privately, and set `FS_LICENSE` to its path. Never paste license contents into a tutorial or repository.

Setup FreeSurfer:
```
mkdir /neurodesktop-storage/freesurfer-output
source /opt/freesurfer-7.1.1/SetUpFreeSurfer.sh
export SUBJECTS_DIR=/neurodesktop-storage/freesurfer-output
```

Run Recon all pipeline:
```
recon-all -subject test-subject -i /neurodesktop-storage/sub-01_ses-01_7T_T1w_defaced.nii.gz -all
```


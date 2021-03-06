!{\src2tex{textfont=tt}}
!!****f* ABINIT/xchybrid_ncpp_cc
!! NAME
!! xchybrid_ncpp_cc
!!
!! FUNCTION
!! XC Hybrid Norm-Conserving PseudoPotential Core Correction:
!! Relevant only for Norm-Conserving PseudoPotentials (NCPP) and for hybrid functionals.
!! Compute the correction to the XC energy/potential due to the lack of core wave-functions:
!! As Fock exchange cannot be computed for core-core and core-valence interactions, these
!! contribution have to be also substracted from the GGA exchange-correlation.
!!
!! COPYRIGHT
!!  Copyright (C) 2015-2017 ABINIT group (FA,MT)
!!  This file is distributed under the terms of the
!!  GNU General Public License, see ~abinit/COPYING
!!  or http://www.gnu.org/copyleft/gpl.txt .
!!
!! INPUTS
!!  dtset <type(dataset_type)>= all input variables in this dataset
!!  mpi_enreg= information about MPI parallelization
!!  nfft= number of fft grid points.
!!  ngfft(1:3)= integer fft box dimensions, see getng for ngfft(4:8).
!!  n3xccc=dimension of the xccc3d array (0 or nfft).
!!  rhor(nfft,nspden)= electron density in real space in electrons/bohr**3
!!  rprimd(3,3)= dimensional primitive translations for real space in Bohr.
!!  xccc3d(n3xccc)=3D core electron density for XC core correction (bohr^-3)
!!
!! OUTPUT
!!
!! SIDE EFFECTS
!!  enxc= exchange correlation energy
!!  strsxc(6)= exchange correlation contribution to stress tensor
!!  vxc= exchange correlation potential
!!  vxcavg= unit cell average of Vxc
!!
!! NOTES
!!  The final expression of the XC potential (that should be added to alpha*VFock[Psi_val]) is:
!!   Vxc=Vx[rho_core+rho_val] - alpha*Vx[rho_val] + Vc[rho_core+rho_val]
!!  To accomodate libXC convention, Vxc is computed as follows:
!!   Vxc=Vxc_libXC[rho_val] + Vxc_gga[rho_core+rho_val] - Vxc_gga[rho_val]
!!
!! PARENTS
!!      rhotov,setvtr
!!
!! CHILDREN
!!      dtset_copy,dtset_free,libxc_functionals_end,libxc_functionals_init
!!      rhohxc
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine xchybrid_ncpp_cc(dtset,enxc,mpi_enreg,nfft,ngfft,n3xccc,rhor,rprimd,strsxc,vxc,vxcavg,xccc3d)

 use defs_basis
 use m_profiling_abi
 use m_errors
 use libxc_functionals

 use defs_abitypes, only : MPI_type, dataset_type
 use m_dtset,       only : dtset_copy, dtset_free

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'xchybrid_ncpp_cc'
 use interfaces_56_xc, except_this_one => xchybrid_ncpp_cc
!End of the abilint section

 implicit none

!Arguments -------------------------------------------------------------
!scalars
 integer,intent(in) :: nfft,n3xccc
 real(dp),intent(out) :: enxc,vxcavg
 type(dataset_type),intent(in) :: dtset
 type(MPI_type),intent(in) :: mpi_enreg
!arrays
 integer,intent(in) :: ngfft(18)
 real(dp),intent(in) :: rhor(nfft,dtset%nspden),rprimd(3,3),xccc3d(n3xccc)
 real(dp),intent(out) :: strsxc(6),vxc(nfft,dtset%nspden)

!Local variables -------------------------------------------------------
!scalars
 integer :: ixc_gga,izero,ndim,nkxc,n3xccc_null,option,usexcnhat
 real(dp) :: enxc_corr,vxcavg_corr
 character(len=500) :: msg
 type(dataset_type) :: dtLocal
!arrays
 integer :: gga_id(2)
 real(dp) :: nhat(1,0),nhatgr(1,1,0),strsxc_corr(6)
 real(dp),allocatable :: kxc_dum(:,:),rhog_dum(:,:),vhartr_dum(:),vxc_corr(:,:),xccc3d_null(:)

! *************************************************************************

 DBG_ENTER("COLL")

!Not relevant for PAW
 if (dtset%usepaw==1) return

!Not applicable for electron-positron
 if (dtset%positron>0) then
   msg='NCPP+Hybrid functionals not applicable for electron-positron calculations!'
   MSG_ERROR(msg)
 end if

!Select the GGA on which the hybrid functional is based on
!or return if not applicable
 if (dtset%ixc==41.or.dtset%ixc==42) then
   ixc_gga = 11
 else if (dtset%ixc<0) then
   if (libxc_functionals_gga_from_hybrid(gga_id=gga_id)) then
     ixc_gga=-gga_id(1)*1000-gga_id(2)
   else
     return
   end if
 else
   return
 end if


!Dirty trick: as rhohxc needs dtset, create a temporary copy if it
 call dtset_copy(dtLocal,dtset)

!Initialize args for rhohxc
 option=0 ! XC only
 nkxc=0;ndim=0;izero=0;usexcnhat=0;n3xccc_null=0
 ABI_ALLOCATE(vxc_corr,(nfft,dtset%nspden))
 ABI_ALLOCATE(rhog_dum,(2,nfft))
 ABI_ALLOCATE(kxc_dum,(nfft,nkxc))
 ABI_ALLOCATE(vhartr_dum,(nfft))
 ABI_ALLOCATE(xccc3d_null,(n3xccc_null))

!Compute Vxc^Hybrid(rho_val)
 call rhohxc(dtset,enxc,zero,izero,kxc_dum,mpi_enreg,nfft,ngfft,nhat,ndim,nhatgr,ndim,nkxc,nkxc,&
& dtset%nspden,n3xccc_null,option,rhog_dum,rhor,rprimd,strsxc,usexcnhat,vhartr_dum,vxc,vxcavg,xccc3d_null)

!Initialize GGA functional
 dtLocal%ixc=ixc_gga
 if (dtLocal%ixc<0) then
   call libxc_functionals_end()
   call libxc_functionals_init(dtLocal%ixc,dtLocal%nspden)
 end if

!Add Vxc^GGA(rho_core+rho_val)
 call rhohxc(dtLocal,enxc_corr,zero,izero,kxc_dum,mpi_enreg,nfft,ngfft,nhat,ndim,nhatgr,ndim,nkxc,nkxc,&
& dtLocal%nspden,n3xccc,option,rhog_dum,rhor,rprimd,strsxc_corr,usexcnhat,vhartr_dum,vxc_corr,vxcavg_corr,xccc3d)
 enxc=enxc+enxc_corr
 vxc(:,:)=vxc(:,:)+vxc_corr(:,:)
 vxcavg=vxcavg+vxcavg_corr
 strsxc(:)=strsxc(:)+strsxc_corr(:)

!Substract Vxc^GGA(rho_val)
 call rhohxc(dtLocal,enxc_corr,zero,izero,kxc_dum,mpi_enreg,nfft,ngfft,nhat,ndim,nhatgr,ndim,nkxc,nkxc,&
& dtLocal%nspden,n3xccc_null,option,rhog_dum,rhor,rprimd,strsxc_corr,usexcnhat,vhartr_dum,vxc_corr,vxcavg_corr,xccc3d_null)
 enxc=enxc-enxc_corr
 vxc(:,:)=vxc(:,:)-vxc_corr(:,:)
 vxcavg=vxcavg-vxcavg_corr
 strsxc(:)=strsxc(:)-strsxc_corr(:)

! Revert libxc to original settings
 if (dtLocal%ixc<0) then
   call libxc_functionals_end()
   call libxc_functionals_init(dtset%ixc,dtset%nspden)
 end if

!Release memory
 ABI_DEALLOCATE(vxc_corr)
 ABI_DEALLOCATE(rhog_dum)
 ABI_DEALLOCATE(kxc_dum)
 ABI_DEALLOCATE(vhartr_dum)
 ABI_DEALLOCATE(xccc3d_null)
 call dtset_free(dtLocal)

 DBG_EXIT("COLL")

end subroutine xchybrid_ncpp_cc
!!***

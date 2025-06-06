!>  \file cires_ugwp_post.F90
!! This file contains the calcualtion of the UGWP v0 diagnostics

!> This module contains the calculation of the UGWP v0 diagnostics (ldiag_ugwp)
module cires_ugwp_post

contains

!>\defgroup cires_ugwp_post_mod cires_ugwp_post Module
!! This module contains code run cires_ugwp afterwards.
!> @{
!> The subroutine initializes the CIRES UGWP
!> \section arg_table_cires_ugwp_post_run Argument Table
!! \htmlinclude cires_ugwp_post_run.html
!!
     subroutine cires_ugwp_post_run (ldiag_ugwp, dtf, im, levs,     &
         gw_dtdt, gw_dudt, gw_dvdt, tau_tofd, tau_mtb, tau_ogw,     &
         tau_ngw, zmtb, zlwb, zogw, dudt_mtb, dudt_ogw, dudt_tms,   &
         tot_zmtb, tot_zlwb, tot_zogw,                              &
         tot_tofd, tot_mtb, tot_ogw, tot_ngw,                       &
         du3dt_mtb,du3dt_ogw, du3dt_tms, du3dt_ngw, dv3dt_ngw,      &
         dtdt, dudt, dvdt, errmsg, errflg)

        use machine,                only: kind_phys

        implicit none

        ! Interface variables
        integer,              intent(in) :: im, levs
        real(kind=kind_phys), intent(in) :: dtf
        logical,              intent(in) :: ldiag_ugwp      ! flag for CIRES UGWP Diagnostics

        real(kind=kind_phys), intent(in),    dimension(:)   :: zmtb, zlwb, zogw
        real(kind=kind_phys), intent(in),    dimension(:)   :: tau_mtb, tau_ogw, tau_tofd, tau_ngw
        real(kind=kind_phys), intent(inout), dimension(:)   :: tot_mtb, tot_ogw, tot_tofd, tot_ngw
        real(kind=kind_phys), intent(inout), dimension(:)   :: tot_zmtb, tot_zlwb, tot_zogw
        real(kind=kind_phys), intent(in),    dimension(:,:) :: gw_dtdt, gw_dudt, gw_dvdt, dudt_mtb, dudt_tms
        real(kind=kind_phys), intent(in),    dimension(:,:) :: dudt_ogw
        real(kind=kind_phys), intent(inout), dimension(:,:), optional :: du3dt_mtb, du3dt_ogw, du3dt_tms, du3dt_ngw, dv3dt_ngw
        real(kind=kind_phys), intent(inout), dimension(:,:) :: dtdt, dudt, dvdt

        character(len=*),        intent(out) :: errmsg
        integer,                 intent(out) :: errflg

        ! Initialize CCPP error handling variables
        errmsg = ''
        errflg = 0

        if (ldiag_ugwp) then
          tot_zmtb =  tot_zmtb + dtf *zmtb
          tot_zlwb =  tot_zlwb + dtf *zlwb
          tot_zogw =  tot_zogw + dtf *zogw
    
          tot_tofd  = tot_tofd + dtf *tau_tofd
          tot_mtb   = tot_mtb +  dtf *tau_mtb
          tot_ogw   = tot_ogw +  dtf *tau_ogw
          tot_ngw   = tot_ngw +  dtf *tau_ngw
    
          du3dt_mtb = du3dt_mtb + dtf *dudt_mtb
          du3dt_tms = du3dt_tms + dtf *dudt_tms
          du3dt_ogw = du3dt_ogw + dtf *dudt_ogw
          du3dt_ngw = du3dt_ngw + dtf *gw_dudt
          dv3dt_ngw = dv3dt_ngw + dtf *gw_dvdt
        endif

        dtdt = dtdt + gw_dtdt
        dudt = dudt + gw_dudt
        dvdt = dvdt + gw_dvdt

      end subroutine cires_ugwp_post_run

!> @}

end module cires_ugwp_post

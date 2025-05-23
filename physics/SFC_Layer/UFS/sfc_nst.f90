!>\file sfc_nst.f90
!!  This file contains the GFS NSST model.

!> This module contains the CCPP-compliant GFS near-surface sea temperature scheme.
module sfc_nst

  use machine ,               only : kind_phys, kp => kind_phys
  use funcphys ,              only : fpvs
  use module_nst_parameters , only : one, zero, half
  use module_nst_parameters , only : t0k, cp_w, omg_m, omg_sh, sigma_r, solar_time_6am, sst_max
  use module_nst_parameters , only : ri_c, z_w_max, delz, wd_max, rad2deg, const_rot, tau_min, tw_max
  use module_nst_water_prop , only : get_dtzm_point, density, rhocoef, grv, sw_ps_9b
  use nst_module ,            only : cool_skin, dtm_1p, cal_w, cal_ttop, convdepth, dtm_1p_fca
  use nst_module ,            only : dtm_1p_tla, dtm_1p_mwa, dtm_1p_mda, dtm_1p_mta, dtl_reset
  !
  implicit none
contains

  !>\defgroup gfs_nst_main_mod GFS Near-Surface Sea Temperature Module
  !! This module contains the CCPP-compliant GFS near-surface sea temperature scheme.
  !> @{
  !! This subroutine calls the Thermal Skin-layer and Diurnal Thermocline models to update the NSST profile.
  !! \section arg_table_sfc_nst_run Argument Table
  !! \htmlinclude sfc_nst_run.html
  !!
  !> \section NSST_general_algorithm GFS Near-Surface Sea Temperature Scheme General Algorithm
  subroutine sfc_nst_run                                          &
       ( im, hvap, cp, hfus, jcal, eps, epsm1, rvrdm1, rd, rhw0,  &  ! --- inputs:
       pi, tgice, sbc, ps, u1, v1, usfco, vsfco, icplocn2atm, t1, &
       q1, tref, cm, ch, lseaspray, fm, fm10,                     &
       prsl1, prslki, prsik1, prslk1, wet, use_lake_model, xlon,  &
       sinlat, stress,                                            &
       sfcemis, dlwflx, sfcnsw, rain, timestep, kdt, solhr,xcosz, &
       wind, flag_iter, flag_guess, nstf_name1, nstf_name4,       &
       nstf_name5, lprnt, ipr, thsfc_loc,                         &
       tskin, tsurf, xt, xs, xu, xv, xz, zm, xtts, xzts, dt_cool, &  ! --- input/output:
       z_c,   c_0,   c_d,   w_0, w_d, d_conv, ifd, qrain,         &
       qsurf, gflux, cmm, chh, evap, hflx, ep, errmsg, errflg     &  ! --- outputs:
       )
    !
    ! ===================================================================== !
    !  description:                                                         !
    !                                                                       !
    !                                                                       !
    !  usage:                                                               !
    !                                                                       !
    !    call sfc_nst                                                       !
    !       inputs:                                                         !
    !          ( im, ps, u1, v1, t1, q1, tref, cm, ch,                      !
    !            lseaspray, fm, fm10,                                       !
    !            prsl1, prslki, wet, use_lake_model, xlon, sinlat, stress,  !
    !            sfcemis, dlwflx, sfcnsw, rain, timestep, kdt,solhr,xcosz,  !
    !            wind,  flag_iter, flag_guess, nstf_name1, nstf_name4,      !
    !            nstf_name5, lprnt, ipr, thsfc_loc,                         !
    !       input/outputs:                                                  !
    !            tskin, tsurf, xt, xs, xu, xv, xz, zm, xtts, xzts, dt_cool, !
    !            z_c, c_0,   c_d,   w_0, w_d, d_conv, ifd, qrain,           !
    !  --   outputs:
    !            qsurf, gflux, cmm, chh, evap, hflx, ep                     !
    !           )
    !                                                                       !
    !                                                                       !
    !  subprogram/functions called: fpvs, density, rhocoef, cool_skin       !
    !                                                                       !
    !  program history log:                                                 !
    !         2007  -- xu li       createad original code                   !
    !         2008  -- s. moorthi  adapted to the parallel version          !
    !    may  2009  -- y.-t. hou   modified to include input lw surface     !
    !                     emissivity from radiation. also replaced the      !
    !                     often comfusing combined sw and lw suface         !
    !                     flux with separate sfc net sw flux (defined       !
    !                     as dn-up) and lw flux. added a program doc block. !
    !    sep  2009 --  s. moorthi removed rcl and additional reformatting   !
    !                     and optimization + made pa as input pressure unit.!
    !         2009  -- xu li       recreatead the code                      !
    !    feb  2010  -- s. moorthi added some changes made to the previous   !
    !                  version                                              !
    !    Jul  2016  -- X. Li, modify the diurnal warming event reset        !
    !                                                                       !
    !                                                                       !
    !  ====================  definition of variables  ====================  !
    !                                                                       !
    !  inputs:                                                       size   !
    !     im       - integer, horiz dimension                          1    !
    !     ps       - real, surface pressure (pa)                       im   !
    !     u1, v1   - real, u/v component of surface layer wind (m/s)   im   !
    !     usfco, vsfco - real, u/v component of surface current (m/s)  im   !
    !     icplocn2atm - integer, option to include ocean surface       1    !
    !                       current in the computation of flux              ! 
    !     t1       - real, surface layer mean temperature ( k )        im   !
    !     q1       - real, surface layer mean specific humidity        im   !
    !     tref     - real, reference/foundation temperature ( k )      im   !
    !     cm       - real, surface exchange coeff for momentum (m/s)   im   !
    !     ch       - real, surface exchange coeff heat & moisture(m/s) im   !
    !     lseaspray- logical, .t. for parameterization for sea spray   1    !
    !     fm       - real, a stability profile function for momentum   im   !
    !     fm10     - real, a stability profile function for momentum   im   !
    !                       at 10m                                          !
    !     prsl1    - real, surface layer mean pressure (pa)            im   !
    !     prslki   - real,                                             im   !
    !     prsik1   - real,                                             im   !
    !     prslk1   - real,                                             im   !
    !     wet      - logical, =T if any ocn/lake water (F otherwise)   im   !
    !     use_lake_model- logical, =T if flake model is used for lake  im   !
    !     icy      - logical, =T if any ice                            im   !
    !     xlon     - real, longitude         (radians)                 im   !
    !     sinlat   - real, sin of latitude                             im   !
    !     stress   - real, wind stress       (n/m**2)                  im   !
    !     sfcemis  - real, sfc lw emissivity (fraction)                im   !
    !     dlwflx   - real, total sky sfc downward lw flux (w/m**2)     im   !
    !     sfcnsw   - real, total sky sfc netsw flx into ocean (w/m**2) im   !
    !     rain     - real, rainfall rate     (kg/m**2/s)               im   !
    !     timestep - real, timestep interval (second)                  1    !
    !     kdt      - integer, time step counter                        1    !
    !     solhr    - real, fcst hour at the end of prev time step      1    !
    !     xcosz    - real, consine of solar zenith angle               1    !
    !     wind     - real, wind speed (m/s)                            im   !
    !     flag_iter- logical, execution or not                         im   !
    !                when iter = 1, flag_iter = .true. for all grids   im   !
    !                when iter = 2, flag_iter = .true. when wind < 2   im   !
    !                for both land and ocean (when nstf_name1 > 0)     im   !
    !     flag_guess-logical, .true.=  guess step to get CD et al      im   !
    !                when iter = 1, flag_guess = .true. when wind < 2  im   !
    !                when iter = 2, flag_guess = .false. for all grids im   !
    !     nstf_name - integers , NSST related flag parameters          1    !
    !                nstf_name1 : 0 = NSSTM off                        1    !
    !                             1 = NSSTM on but uncoupled           1    !
    !                             2 = NSSTM on and coupled             1    !
    !                nstf_name4 : zsea1 in mm                          1    !
    !                nstf_name5 : zsea2 in mm                          1    !
    !     lprnt    - logical, control flag for check print out         1    !
    !     ipr      - integer, grid index for check print out           1    !
    !     thsfc_loc- logical, flag for reference pressure in theta     1    !
    !                                                                       !
    !  input/outputs:
    ! li added for oceanic components
    !     tskin    - real, ocean surface skin temperature ( k )        im   !
    !     tsurf    - real, the same as tskin ( k ) but for guess run   im   !
    !     xt       - real, heat content in dtl                         im   !
    !     xs       - real, salinity  content in dtl                    im   !
    !     xu       - real, u-current content in dtl                    im   !
    !     xv       - real, v-current content in dtl                    im   !
    !     xz       - real, dtl thickness                               im   !
    !     zm       - real, mxl thickness                               im   !
    !     xtts     - real, d(xt)/d(ts)                                 im   !
    !     xzts     - real, d(xz)/d(ts)                                 im   !
    !     dt_cool  - real, sub-layer cooling amount                    im   !
    !     d_conv   - real, thickness of free convection layer (fcl)    im   !
    !     z_c      - sub-layer cooling thickness                       im   !
    !     c_0      - coefficient1 to calculate d(tz)/d(ts)             im   !
    !     c_d      - coefficient2 to calculate d(tz)/d(ts)             im   !
    !     w_0      - coefficient3 to calculate d(tz)/d(ts)             im   !
    !     w_d      - coefficient4 to calculate d(tz)/d(ts)             im   !
    !     ifd      - real, index to start dtlm run or not              im   !
    !     qrain    - real, sensible heat flux due to rainfall (watts)  im   !

    !  outputs:                                                             !

    !     qsurf    - real, surface air saturation specific humidity    im   !
    !     gflux    - real, soil heat flux (w/m**2)                     im   !
    !     cmm      - real,                                             im   !
    !     chh      - real,                                             im   !
    !     evap     - real, evaperation from latent heat flux           im   !
    !     hflx     - real, sensible heat flux                          im   !
    !     ep       - real, potential evaporation                       im   !
    !                                                                       !
    ! ===================================================================== !



    !  ---  inputs:
    integer, intent(in) :: im, kdt, ipr, nstf_name1, nstf_name4, nstf_name5
    integer, intent(in) :: icplocn2atm
  
    real (kind=kind_phys), intent(in) :: hvap, cp, hfus, jcal, eps, &
         epsm1, rvrdm1, rd, rhw0, sbc, pi, tgice
    real (kind=kind_phys), dimension(:), intent(in) :: ps, u1, v1,  &
         usfco, vsfco, t1, q1, cm, ch, fm, fm10,                    &
         prsl1, prslki, prsik1, prslk1, xlon, xcosz,                &
         sinlat, stress, sfcemis, dlwflx, sfcnsw, rain, wind
    real (kind=kind_phys), dimension(:), intent(in) :: tref
    real (kind=kind_phys), intent(in) :: timestep
    real (kind=kind_phys), intent(in) :: solhr

    ! For sea spray effect
    logical, intent(in) :: lseaspray
    !
    logical, dimension(:), intent(in) :: flag_iter, flag_guess, wet
    integer, dimension(:), intent(in) :: use_lake_model
    logical,               intent(in) :: lprnt
    logical,               intent(in) :: thsfc_loc

    !  ---  input/outputs:
    ! control variables of dtl system (5+2) and sl (2) and coefficients for d(tz)/d(ts) calculation
    real (kind=kind_phys), dimension(:), intent(inout) :: tskin, &
         tsurf
    real (kind=kind_phys), dimension(:), intent(inout) :: &
         xt, xs, xu, xv, xz, zm, xtts, xzts, dt_cool,     &
         z_c, c_0, c_d, w_0, w_d, d_conv, ifd, qrain

    !  ---  outputs:
    real (kind=kind_phys), dimension(:), intent(inout) :: qsurf, gflux, cmm, chh, evap, hflx, ep

    character(len=*), intent(out) :: errmsg
    integer,          intent(out) :: errflg

    !
    !     locals
    !
    integer :: k,i
    !
    real (kind=kind_phys), dimension(im) ::  q0, qss, rch, rho_a, theta1, tv1, wndmag

    real(kind=kind_phys) :: elocp,tem,cpinv,hvapi
    !
    !    nstm related prognostic fields
    !
    logical :: flag(im)
    real (kind=kind_phys), dimension(im) :: xt_old, xs_old, xu_old, xv_old, xz_old, &
         zm_old,xtts_old, xzts_old, ifd_old, tref_old, tskin_old, dt_cool_old,z_c_old

    real(kind=kind_phys) :: ulwflx(im), nswsfc(im)
    !     real(kind=kind_phys) rig(im),
    !    &                     ulwflx(im),dlwflx(im),
    !    &                     slrad(im),nswsfc(im)
    real(kind=kind_phys) :: alpha,beta,rho_w,f_nsol,sss,sep, cosa,sina,taux,tauy, &
         grav,dz,t0,ttop0,ttop

    real(kind=kind_phys) :: le,fc,dwat,dtmp,wetc,alfac,ustar_a,rich
    real(kind=kind_phys) :: rnl_ts,hs_ts,hl_ts,rf_ts,q_ts
    real(kind=kind_phys) :: fw,q_warm
    real(kind=kind_phys) :: t12,alon,tsea,sstc,dta,dtz
    real(kind=kind_phys) :: zsea1,zsea2,soltim
    logical :: do_nst
    !
    !  parameters for sea spray effect
    !
    real (kind=kind_phys) :: f10m, u10m, v10m, ws10, ru10, qss1, &
         bb1, hflxs, evaps, ptem
    !
    !     real (kind=kind_phys), parameter :: alps=0.5, bets=0.5, gams=0.1,
    !     real (kind=kind_phys), parameter :: alps=0.5, bets=0.5, gams=0.0,
    !     real (kind=kind_phys), parameter :: alps=1.0, bets=1.0, gams=0.2,
    real (kind=kind_phys), parameter :: alps=0.75,bets=0.75,gams=0.15, &
         ws10cr=30., conlf=7.2e-9, consf=6.4e-8
    real (kind=kind_phys) :: windrel
    !
    !======================================================================================================
    ! Initialize CCPP error handling variables
    errmsg = ''
    errflg = 0

    if (nstf_name1 == 0) return ! No NSST model used

    cpinv = one/cp
    hvapi = one/hvap
    elocp = hvap/cp

    sss = 34.0_kp             ! temporarily, when sea surface salinity data is not ready
    !
    ! flag for open water and where the iteration is on
    !
    do_nst = .false.
    do i = 1, im
       !       flag(i) = wet(i) .and. .not.icy(i) .and. flag_iter(i)
       flag(i) = wet(i) .and. flag_iter(i) .and. use_lake_model(i)/=1
       do_nst  = do_nst .or. flag(i)
    enddo
    if (.not. do_nst) return
    !
    !  save nst-related prognostic fields for guess run
    !
    do i=1, im
       !       if(wet(i) .and. .not.icy(i) .and. flag_guess(i)) then
       if(wet(i) .and. flag_guess(i) .and. use_lake_model(i)/=1) then
          xt_old(i)      = xt(i)
          xs_old(i)      = xs(i)
          xu_old(i)      = xu(i)
          xv_old(i)      = xv(i)
          xz_old(i)      = xz(i)
          zm_old(i)      = zm(i)
          xtts_old(i)    = xtts(i)
          xzts_old(i)    = xzts(i)
          ifd_old(i)     = ifd(i)
          tskin_old(i)   = tskin(i)
          dt_cool_old(i) = dt_cool(i)
          z_c_old(i)     = z_c(i)
       endif
    enddo


    !  --- ...  initialize variables. all units are m.k.s. unless specified.
    !           ps is in pascals, wind is wind speed, theta1 is surface air
    !           estimated from level 1 temperature, rho_a is air density and
    !           qss is saturation specific humidity at the water surface
    !!
    do i = 1, im
       if ( flag(i) ) then

          nswsfc(i) = sfcnsw(i) ! net solar radiation at the air-sea surface (positive downward)
          wndmag(i) = sqrt(u1(i)*u1(i) + v1(i)*v1(i))

          q0(i)     = max(q1(i), 1.0e-8_kp)

          if(thsfc_loc) then ! Use local potential temperature
             theta1(i) = t1(i) * prslki(i)
          else ! Use potential temperature referenced to 1000 hPa
             theta1(i) = t1(i) / prslk1(i) ! potential temperature at the middle of lowest model layer
          endif

          tv1(i)    = t1(i) * (one + rvrdm1*q0(i))
          rho_a(i)  = prsl1(i) / (rd*tv1(i))
          qss(i)    = fpvs(tsurf(i))                          ! pa
          qss(i)    = eps*qss(i) / (ps(i) + epsm1*qss(i))     ! pa
          !
          evap(i)    = zero
          hflx(i)    = zero
          gflux(i)   = zero
          ep(i)      = zero

          !  --- ...  rcp = rho cp ch v

          if (icplocn2atm ==0) then
            rch(i)     = rho_a(i) * cp * ch(i) * wind(i)
            cmm(i)     = cm (i)   * wind(i)
            chh(i)     = rho_a(i) * ch(i) * wind(i)
          else if (icplocn2atm ==1) then
            windrel= sqrt( (u1(i)-usfco(i))**2 + (v1(i)-vsfco(i))**2 )
            rch(i)     = rho_a(i) * cp * ch(i) * windrel
            cmm(i)     = cm (i)   * windrel
            chh(i)     = rho_a(i) * ch(i) * windrel
          endif

          !> - Calculate latent and sensible heat flux over open water with tskin.
          !           at previous time step
          evap(i)    = elocp * rch(i) * (qss(i) - q0(i))
          qsurf(i)   = qss(i)

          if(thsfc_loc) then ! Use local potential temperature
             hflx(i)    = rch(i) * (tsurf(i) - theta1(i))
          else ! Use potential temperature referenced to 1000 hPa
             hflx(i)    = rch(i) * (tsurf(i)/prsik1(i) - theta1(i))
          endif

          !     if (lprnt .and. i == ipr) print *,' tskin=',tskin(i),' theta1=',
          !    & theta1(i),' hflx=',hflx(i),' t1=',t1(i),'prslki=',prslki(i)
          !    &,' tsurf=',tsurf(i)
       endif
    enddo

    ! run nst model: dtm + slm
    !
    zsea1 = 0.001_kp*real(nstf_name4)
    zsea2 = 0.001_kp*real(nstf_name5)

    !> - Call module_nst_water_prop::density() to compute sea water density.
    !> - Call module_nst_water_prop::rhocoef() to compute thermal expansion
    !! coefficient (\a alpha) and saline contraction coefficient (\a beta).
    do i = 1, im
       if ( flag(i) ) then
          tsea      = tsurf(i)
          t12       = tsea*tsea
          ulwflx(i) = sfcemis(i) * sbc * t12 * t12
          alon      = xlon(i)*rad2deg
          grav      = grv(sinlat(i))
          soltim    = mod(alon/15.0_kp + solhr, 24.0_kp)*3600.0_kp
          call density(tsea,sss,rho_w)                     ! sea water density
          call rhocoef(tsea,sss,rho_w,alpha,beta)          ! alpha & beta
          !
          !> - Calculate sensible heat flux (\a qrain) due to rainfall.
          !
          le       = (2.501_kp-0.00237_kp*tsea)*1.0e6_kp
          dwat     = 2.11e-5_kp*(t1(i)/t0k)**1.94_kp        ! water vapor diffusivity
          dtmp     = (one+3.309e-3_kp*(t1(i)-t0k)-1.44e-6_kp*(t1(i)-t0k) &
               * (t1(i)-t0k))*0.02411_kp/(rho_a(i)*cp)  ! heat diffusivity
          wetc     = 622.0_kp*le*qss(i)/(rd*t1(i)*t1(i))
          alfac    = one / (one + (wetc*le*dwat)/(cp*dtmp)) ! wet bulb factor
          tem      = (1.0e3_kp * rain(i) / rho_w) * alfac * cp_w
          qrain(i) =  tem * (tsea-t1(i)+1.0e3_kp*(qss(i)-q0(i))*le/cp)

          !> - Calculate input non solar heat flux as upward = positive to models here

          f_nsol   = hflx(i) + evap(i) + ulwflx(i) - dlwflx(i) + omg_sh*qrain(i)

          !     if (lprnt .and. i == ipr) print *,' f_nsol=',f_nsol,' hflx=',
          !    &hflx(i),' evap=',evap(i),' ulwflx=',ulwflx(i),' dlwflx=',dlwflx(i)
          !    &,' omg_sh=',omg_sh,' qrain=',qrain(i)

          sep      = sss*(evap(i)/le-rain(i))/rho_w
          ustar_a  = sqrt(stress(i)/rho_a(i))          ! air friction velocity
          !
          !  sensitivities of heat flux components to ts
          !
          rnl_ts = 4.0_kp*sfcemis(i)*sbc*tsea*tsea*tsea     ! d(rnl)/d(ts)
          hs_ts  = rch(i)
          hl_ts  = rch(i)*elocp*eps*hvap*qss(i)/(rd*t12)
          rf_ts  = tem * (one+rch(i)*hl_ts)
          q_ts   = rnl_ts + hs_ts + hl_ts + omg_sh*rf_ts
          !
          !> - Call cool_skin(), which is the sub-layer cooling parameterization
          !! (Fairfall et al. (1996) \cite fairall_et_al_1996).
          ! & calculate c_0, c_d
          !
          call cool_skin(ustar_a,f_nsol,nswsfc(i),evap(i),sss,alpha,beta, &
                         rho_w,rho_a(i),tsea,q_ts,hl_ts,grav,le,          &
                         dt_cool(i),z_c(i),c_0(i),c_d(i))

          tem  = one / wndmag(i)
          cosa = u1(i)*tem
          sina = v1(i)*tem
          taux = max(stress(i),tau_min)*cosa
          tauy = max(stress(i),tau_min)*sina
          fc   = const_rot*sinlat(i)
          !
          !  Run DTM-1p system.
          !
          if ( (soltim > solar_time_6am .and. ifd(i) == zero) ) then
          else
             ifd(i) = one
             !
             !     calculate fcl thickness with current forcing and previous time's profile
             !
             !     if (lprnt .and. i == ipr) print *,' beg xz=',xz(i)

             !> - Call convdepth() to calculate depth for convective adjustments.
             if ( f_nsol > zero .and. xt(i) > zero ) then
                call convdepth(kdt,timestep,nswsfc(i),f_nsol,sss,sep,rho_w, &
                               alpha,beta,xt(i),xs(i),xz(i),d_conv(i))
             else
                d_conv(i) = zero
             endif

             !     if (lprnt .and. i == ipr) print *,' beg xz1=',xz(i)
             !
             !    determine rich: wind speed dependent (right now)
             !
             !           if ( wind(i) < 1.0 ) then
             !             rich = 0.25 + 0.03*wind(i)
             !           elseif ( wind(i) >= 1.0 .and. wind(i) < 1.5 ) then
             !             rich = 0.25 + 0.1*wind(i)
             !           elseif ( wind(i) >= 1.5 .and. wind(i) < 6.0 ) then
             !             rich = 0.25 + 0.6*wind(i)
             !           elseif ( wind(i) >= 6.0 ) then
             !             rich = 0.25 + min(0.8*wind(i),0.50)
             !           endif

             rich = ri_c

             !> - Call the diurnal thermocline layer model dtm_1p().
             call dtm_1p(kdt,timestep,rich,taux,tauy,nswsfc(i),           &
                         f_nsol,sss,sep,q_ts,hl_ts,rho_w,alpha,beta,alon, &
                         sinlat(i),soltim,grav,le,d_conv(i),              &
                         xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))

             !     if (lprnt .and. i == ipr) print *,' beg xz2=',xz(i)

             !  apply mda
             if ( xt(i) > zero ) then
                !>  - If \a dtl heat content \a xt > 0.0, call dtm_1p_mda() to apply
                !!  minimum depth adjustment (mda).
                call dtm_1p_mda(xt(i),xtts(i),xz(i),xzts(i))
                if ( xz(i) >= z_w_max ) then
                   !>   - If \a dtl thickness >= module_nst_parameters::z_w_max, call dtl_reset()
                   !! to reset xt/xs/x/xv to zero, and xz to module_nst_parameters::z_w_max.
                   call dtl_reset(xt(i),xs(i),xu(i),xv(i),xz(i),xtts(i), xzts(i))

                   !     if (lprnt .and. i == ipr) print *,' beg xz3=',xz(i),' z_w_max='
                   !    &,z_w_max
                endif

                !  apply fca
                if ( d_conv(i) > zero ) then
                   !>  - If thickness of free convection layer > 0.0, call dtm_1p_fca()
                   !! to apply free convection adjustment.
                   !>   - If \a dtl thickness >= module_nst_parameters::z_w_max(), call dtl_reset()
                   !! to reset xt/xs/x/xv to zero, and xz to module_nst_parameters::z_w_max().
                   call dtm_1p_fca(d_conv(i),xt(i),xtts(i),xz(i),xzts(i))
                   if ( xz(i) >= z_w_max ) then
                      call dtl_reset (xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))
                   endif
                endif

                !     if (lprnt .and. i == ipr) print *,' beg xz4=',xz(i)

                !  apply tla
                dz = min(xz(i),max(d_conv(i),delz))
                !
                !>  - Call sw_ps_9b() to compute the fraction of the solar radiation
                !! absorbed by the depth \a delz (Paulson and Simpson (1981) \cite paulson_and_simpson_1981).
                !! And calculate the total heat absorbed in warm layer.
                call sw_ps_9b(delz,fw)
                q_warm = fw*nswsfc(i)-f_nsol    !total heat absorbed in warm layer

                !>  - Call cal_ttop() to calculate the diurnal warming amount at the top layer with
                !! thickness of \a dz.
                if ( q_warm > zero ) then
                   call cal_ttop(kdt,timestep,q_warm,rho_w,dz, xt(i),xz(i),ttop0)

                   !     if (lprnt .and. i == ipr) print *,' d_conv=',d_conv(i),' delz=',
                   !    &delz,' kdt=',kdt,' timestep=',timestep,' nswsfc=',nswsfc(i),
                   !    &' f_nsol=',f_nsol,' rho_w=',rho_w,' dz=',dz,' xt=',xt(i),
                   !    &' xz=',xz(i),' qrain=',qrain(i)

                   ttop = ((xt(i)+xt(i))/xz(i))*(one-dz/((xz(i)+xz(i))))

                   !     if (lprnt .and. i == ipr) print *,' beg xz4a=',xz(i)
                   !    &,' ttop=',ttop,' ttop0=',ttop0,' xt=',xt(i),' dz=',dz
                   !    &,' xznew=',(xt(i)+sqrt(xt(i)*(xt(i)-dz*ttop0)))/ttop0

                   !>  - Call dtm_1p_tla() to apply top layer adjustment.
                   if ( ttop > ttop0 ) then
                      call dtm_1p_tla(dz,ttop0,xt(i),xtts(i),xz(i),xzts(i))

                      !     if (lprnt .and. i == ipr) print *,' beg xz4b=',xz(i),'z_w_max=',
                      !    &z_w_max
                      if ( xz(i) >= z_w_max ) then
                         call dtl_reset (xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))
                      endif
                   endif
                endif           ! if ( q_warm > 0.0 ) then

                !     if (lprnt .and. i == ipr) print *,' beg xz5=',xz(i)

                !  apply mwa
                !>  - Call dt_1p_mwa() to apply maximum warming adjustment.
                t0 = (xt(i)+xt(i))/xz(i)
                if ( t0 > tw_max ) then
                   call dtm_1p_mwa(xt(i),xtts(i),xz(i),xzts(i))
                   if ( xz(i) >= z_w_max ) then
                      call dtl_reset (xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))
                   endif
                endif

                !     if (lprnt .and. i == ipr) print *,' beg xz6=',xz(i)

                !  apply mta
                !>  - Call dtm_1p_mta() to apply maximum temperature adjustment.
                sstc = tref(i) + (xt(i)+xt(i))/xz(i) - dt_cool(i)

                if ( sstc > sst_max ) then
                   dta = sstc - sst_max
                   call  dtm_1p_mta(dta,xt(i),xtts(i),xz(i),xzts(i))
                   !               write(*,'(a,f3.0,7f8.3)') 'mta, sstc,dta :',islimsk(i),
                   !    &          sstc,dta,tref(i),xt(i),xz(i),2.0*xt(i)/xz(i),dt_cool(i)
                   if ( xz(i) >= z_w_max ) then
                      call dtl_reset (xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))
                   endif
                endif
                !
             endif             ! if ( xt(i) > 0.0 ) then
             !           reset dtl at midnight and when solar zenith angle > 89.994 degree
             if ( abs(soltim) < 2.0_kp*timestep ) then
                call dtl_reset (xt(i),xs(i),xu(i),xv(i),xz(i),xzts(i),xtts(i))
             endif

          endif             ! if (solar_time > solar_time_6am .and. ifd(i) == 0.0 ) then: too late to start the first day

          !     if (lprnt .and. i == ipr) print *,' beg xz7=',xz(i)

          !     update tsurf  (when flag(i) .eqv. .true. )
          !>  - Call get_dtzm_point() to computes \a dtz and \a tsurf.
          call get_dtzm_point(xt(i),xz(i),dt_cool(i),z_c(i), zsea1,zsea2,dtz)
          tsurf(i) = max(tgice, tref(i) + dtz )

          !     if (lprnt .and. i == ipr) print *,' tsurf=',tsurf(i),' tref=',
          !    &tref(i),' xz=',xz(i),' dt_cool=',dt_cool(i)

          !>  - Call cal_w() to calculate \a w_0 and \a w_d.
          if ( xt(i) > zero ) then
             call cal_w(kdt,xz(i),xt(i),xzts(i),xtts(i),w_0(i),w_d(i))
          else
             w_0(i) = zero
             w_d(i) = zero
          endif

          !         if ( xt(i) > 0.0 ) then
          !           rig(i) = grav*xz(i)*xz(i)*(alpha*xt(i)-beta*xs(i))
          !    &             /(2.0*(xu(i)*xu(i)+xv(i)*xv(i)))
          !         else
          !           rig(i) = 0.25
          !         endif

          !         qrain(i) = rig(i)
          zm(i) = wind(i)

       endif
    enddo

    ! restore nst-related prognostic fields for guess run
    do i=1, im
       !       if (wet(i) .and. .not.icy(i)) then
       if (wet(i) .and. use_lake_model(i)/=1) then
          if (flag_guess(i)) then    ! when it is guess of
             xt(i)      = xt_old(i)
             xs(i)      = xs_old(i)
             xu(i)      = xu_old(i)
             xv(i)      = xv_old(i)
             xz(i)      = xz_old(i)
             zm(i)      = zm_old(i)
             xtts(i)    = xtts_old(i)
             xzts(i)    = xzts_old(i)
             ifd(i)     = ifd_old(i)
             tskin(i)   = tskin_old(i)
             dt_cool(i) = dt_cool_old(i)
             z_c(i)     = z_c_old(i)
          else
             !
             !         update tskin when coupled and not guess run
             !         (all other NSST variables have been updated in this case)
             !
             if ( nstf_name1 > 1 ) then
                tskin(i) = tsurf(i)
             endif               ! if nstf_name1 > 1 then
          endif                 ! if flag_guess(i) then
       endif                   ! if wet(i) .and. .not.icy(i) then
    enddo

    !     if (lprnt .and. i == ipr) print *,' beg xz8=',xz(i)

    if ( nstf_name1 > 1 ) then
       !> - Calculate latent and sensible heat flux over open water with updated tskin
       !!      for the grids of open water and the iteration is on.
       do i = 1, im
          if ( flag(i) ) then
             qss(i)   = fpvs( tskin(i) )
             qss(i)   = eps*qss(i) / (ps(i) + epsm1*qss(i))
             qsurf(i) = qss(i)
             evap(i)  = elocp*rch(i) * (qss(i) - q0(i))

             if(thsfc_loc) then ! Use local potential temperature
                hflx(i)  = rch(i) * (tskin(i) - theta1(i))
             else ! Use potential temperature referenced to 1000 hPa
                hflx(i)  = rch(i) * (tskin(i)/prsik1(i) - theta1(i))
             endif

          endif
       enddo
    endif                   ! if ( nstf_name1 > 1 ) then
    !
    !> - Include sea spray effects
    !
    do i=1,im
       if(lseaspray .and. flag(i)) then
          f10m = fm10(i) / fm(i)
          u10m = f10m * u1(i)
          v10m = f10m * v1(i)
          ws10 = sqrt(u10m*u10m + v10m*v10m)
          ws10 = max(ws10,1.)
          ws10 = min(ws10,ws10cr)
          tem = .015 * ws10 * ws10
          ru10 = 1. - .087 * log(10./tem)
          qss1 = fpvs(t1(i))
          qss1 = eps * qss1 / (prsl1(i) + epsm1 * qss1)
          tem = rd * cp * t1(i) * t1(i)
          tem = 1. + eps * hvap * hvap * qss1 / tem
          bb1 = 1. / tem
          evaps = conlf * (ws10**5.4) * ru10 * bb1
          evaps = evaps * rho_a(i) * hvap * (qss1 - q0(i))
          evap(i) = evap(i) + alps * evaps
          hflxs = consf * (ws10**3.4) * ru10
          hflxs = hflxs * rho_a(i) * cp * (tskin(i) - t1(i))
          ptem = alps - gams
          hflx(i) = hflx(i) + bets * hflxs - ptem * evaps
       endif
    enddo
    !
    do i=1,im
       if ( flag(i) ) then
          tem     = one / rho_a(i)
          hflx(i) = hflx(i) * tem * cpinv
          evap(i) = evap(i) * tem * hvapi
       endif
    enddo
    !
    !     if (lprnt) print *,' tskin=',tskin(ipr)

    return
  end subroutine sfc_nst_run
  !> @}
end module sfc_nst

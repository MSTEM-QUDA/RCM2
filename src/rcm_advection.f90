module RCM_advection

  ! Routines for interfacing with MHD

  use ModUtilities, ONLY: CON_stop
  
  use RCM_variables

  use RCM_routines, ONLY: &
       comput, decay, expand_edge, extremum, &
       farmers_wife, get_boundary, move_plasma, rcm_plasma_bc, read_bfield, &
       read_eta_on_bndy, read_kp, read_vdrop, read_winds, &
       set_precipitation_rates, zap_edge, wrap_around_ghostcells

  use RCM_efield, ONLY: &
       compute_efield

  implicit none

  private

  public :: rcm_advec
  
contains
  !===========================================================================

  subroutine rcm_getSize(idim1,idim2)

    integer, intent(inout) :: idim1,idim2

    idim1=isize
    idim2=jsize

  end subroutine rcm_getSize
  !===========================================================================
  subroutine rcm_getLatLon(RCM_lat,RCM_lon)
    real(rprec), intent(inout), dimension(isize) :: RCM_lat
    real(rprec), intent(inout), dimension(jsize) :: RCM_lon

    RCM_lat = (pi/2.-colat(1:isize,1))*(180./pi)
    RCM_lon = (      aloct(1,1:jsize))*(180./pi)
  end subroutine rcm_getLatLon
  !===========================================================================
  subroutine rcm_getpressure(RCM_p)

    real(rprec), intent(inout), dimension(isize,jsize) :: RCM_p

    integer :: i,j,k

    RCM_p = 0.
    do i=1,isize; do j=1,jsize
       if( i<imin_j(j) ) then
          RCM_p(i,j) = -1.
       else
          do k=1,kcsize
             RCM_p(i,j) = RCM_p(i,j) + vm(i,j)**2.5*eeta(i,j,k)*ABS(alamc(k))
          end do
       end if
    end do; end do
    RCM_p = RCM_p * 1.67E-35

  end subroutine rcm_getpressure
  !===========================================================================
  subroutine rcm_getfieldvolume(RCM_vol,RCM_x,RCM_y)
    
    real(rprec), intent(inout), dimension(isize,jsize) :: RCM_vol,RCM_x,RCM_y

    integer :: i,j,k

    RCM_vol = vm(1:isize,1:jsize)
    RCM_x = xmin(1:isize,1:jsize)
    RCM_y = ymin(1:isize,1:jsize)

  end subroutine rcm_getfieldvolume
  !===========================================================================
  subroutine rcm_putfieldvolume(MHD_vol, iopt, MHD_xmin, MHD_ymin, MHD_bmin)

    integer, intent(in) :: iopt
    real(rprec), intent(in), dimension(isize,jsize) :: &
         MHD_vol, MHD_xmin, MHD_ymin, MHD_bmin

    vm(1:isize,1:jsize) = MHD_vol
    CALL Wrap_around_ghostcells (vm,isize,jsize,n_gc)
    if(iopt==1)then
       xmin(1:isize,1:jsize) = MHD_xmin
       ymin(1:isize,1:jsize) = MHD_ymin
       bmin(1:isize,1:jsize) = MHD_bmin
       CALL Wrap_around_ghostcells (xmin,isize,jsize,n_gc)
       CALL Wrap_around_ghostcells (ymin,isize,jsize,n_gc)
       CALL Wrap_around_ghostcells (bmin,isize,jsize,n_gc)
    end if

  end subroutine rcm_putfieldvolume
  !===========================================================================
  subroutine rcm_putrhop(MHD_rho,MHD_p)

    real(rprec), intent(in), dimension(isize,jsize) :: MHD_rho,MHD_p

    integer :: i,j
    density (1:isize,1:jsize) = MHD_rho /xmass(2)/1.0E+6 ! in cm-3
    DO i = 1, isize
       DO j = 1, jsize
          IF (MHD_rho(i,j) > 0.0) THEN
              ! in eV, assuming p=nkT
             temperature (i,j) = MHD_p(i,j) / (MHD_rho(i,j)/xmass(2)) / 1.6E-19
          ELSE
             temperature (i,j) =5000.0
          END IF
       END DO
    END DO
    CALL Wrap_around_ghostcells (density, isize, jsize, n_gc)
    CALL Wrap_around_ghostcells (temperature, isize, jsize, n_gc)

  end subroutine rcm_putrhop 
  !===========================================================================
  subroutine rcm_putpotential(MHD_v)

    real(rprec), intent(in), dimension(isize,jsize) :: MHD_v

    v(1:isize,1:jsize) = MHD_v
    CALL Wrap_around_ghostcells (v,isize,jsize,n_gc)

  end subroutine rcm_putpotential
  !===========================================================================
  subroutine rcm_putbirk(MHD_birk)

    real(rprec), intent(in), dimension(isize,jsize) :: MHD_birk

    birk_mhd(1:isize,1:jsize) = MHD_birk
    CALL Wrap_around_ghostcells (birk_mhd,isize,jsize,n_gc)

  end subroutine rcm_putbirk
  !===========================================================================
  subroutine rcm_get_mass_density (RCM_mass_density)
    !
    ! Written 3/9/2005 for SWMF version of the RCM, Stanislav
    ! Compute mass density of RCM particle population
    ! by summing up distribution functions for all species.
    ! Values outside the modeling region are set to -1.0
    
    real(rprec), intent (out) :: RCM_mass_density (isize,jsize)

    integer :: i,j,k

    rcm_mass_density = 0.0
    do i=1,isize
       do j=1,jsize
          if (i<imin_j(j)) then
             rcm_mass_density(i,j) = -1.0  !outside RCM high-lat. boundary
          else
             do k = 1, kcsize
                rcm_mass_density(i,j) = rcm_mass_density(i,j) + &
                     eeta(i,j,k)*vm(i,j)**1.5 * xmass(ikflavc(k))
             end do
          end if
       end do
    end do
    where (rcm_mass_density > 0.0) &
         rcm_mass_density = rcm_mass_density / 6.37E+15
    ! units of rcm_mass_density are kg/m3

  end subroutine rcm_get_mass_density
  !===========================================================================
  subroutine RCM_advec0

    ! Controll RCM as stand-alone

    use rcm_io
    use ModMpiOrig

    integer :: time_i, time_f, idt2, rec_i, rec_f, istep, time_i_overall, time_f_overall
    REAL(RPREC), dimension (isize,jsize) :: MHD_rho, MHD_p, MHD_vol, MHD_xmin, MHD_ymin, MHD_Bmin, MHD_v
    REAL(RPREC), dimension (1-n_gc:isize+n_gc,1-n_gc:jsize+n_gc) :: vm_tmp, xmin_tmp, ymin_tmp

    ! Get magnetic field for RCM (constant):
    CALL Read_array('rcmvm_inp', 1, label, ARRAY_2D=vm_tmp, ASCI=asci_flag)
    CALL Read_array('rcmxmin_inp', 1, label, ARRAY_2D=xmin_tmp, ASCI=asci_flag)
    CALL Read_array('rcmymin_inp', 1, label, ARRAY_2D=ymin_tmp, ASCI=asci_flag)
    MHD_vol = vm_tmp(1:isize,1:jsize)
    MHD_xmin = xmin_tmp(1:isize,1:jsize)
    MHD_ymin = ymin_tmp(1:isize,1:jsize)
    MHD_Bmin = 0.
    CALL Rcm_putfieldvolume (MHD_vol, 1, MHD_xmin, MHD_ymin, MHD_Bmin)
    fstoff = label%real(13)
    !
    ! Get plasma boundary conditions for RCM (constant):
    ! MHD_rho = 0.4E+6*xmass(2) ! in kg/m3
    ! MHD_p   = 5000.0*1.6E-19*0.4E+6 ! in Pa
    CALL Read_array('rcmdensity_inp', 1, label, ARRAY_2D=density, ASCI=asci_flag)
    CALL Read_array('rcmtemperature_inp', 1, label, ARRAY_2D=temperature, ASCI=asci_flag)
    MHD_rho = density(1:isize,1:jsize)*xmass(2)*1.0E+6 ! in kg/m3
    MHD_p   = temperature(1:isize,1:jsize)*1.6E-19*1.0E+6*density(1:isize,1:jsize) ! in Pa
    CALL Rcm_putrhop (MHD_rho, MHD_p)
    !
    ! Get MHD potential:
    CALL Read_array ('rcmv_inp', 1, label, ARRAY_2D=v, ASCI=asci_flag)
    MHD_v = v (1:isize,1:jsize)
    CALL Rcm_putpotential (MHD_v)

  end subroutine RCM_advec0
  !===========================================================================
  subroutine RCM_advec (icontrol, itimei, itimef, idt)

    ! Controlling RCM as subroutine
    use ModIoUnit, ONLY: io_unit_new
    use ModUtilities, ONLY: open_file, close_file
    use Rcm_io
    use ModMpiOrig

    implicit none

    INTEGER, INTENT (IN) :: icontrol, itimei, itimef, idt

    ! Control RCM action:
    ! icontrol = 0: read grid
    ! icontrol = 1: initialize
    ! icontrol = 2: compute
    !     advance solution from itimei to itimef with time step idt
    ! icontrol = 3: finalize
    ! icontrol = 4: save restart file
    !
    ! The itimei, itimef and idt integer arguments are given in seconds

    INTEGER :: irdr, irdw
    integer :: iCurrentTime=0
    !
    integer :: i,j
    !

    !\\\
    ! type (RCM_ITER) :: r_iter
    integer :: index, ierror, ifile
    logical :: done, status_ok
    !///
    !
    CHARACTER(LEN=8) :: real_date
    CHARACTER (LEN=8) :: time_char
    CHARACTER(LEN=10) ::real_time
    CHARACTER(LEN=80) :: ST='', PS='', HD='', emptystring=''
    LOGICAL :: FD
    !                                                                       
    ! INTEGER (iprec) :: idt
    INTEGER (iprec) :: idt2
    INTEGER (iprec) :: ierr
    INTEGER (iprec) :: itout1, itout2, idt3, itcln, idebug, i_time, k, kc, n
    REAL (rprec) :: dt
    !
    character(len=80) :: filename
    !
    SAVE
    !--------------------------------------------------------------------------
    !  call IM_write_prefix
    !  write(iUnitOut,'(A,I8,A,I8,A,I2)') &
    !       '  PE=',iProc+1,' of ',nProc,' starting.  icontrol=',icontrol
    time0=MPI_Wtime()
    !
    !
    select case (icontrol)
    case(0)      ! JUST READ THE GRID

       CALL Read_grid ()

    case(1)      ! INITIALIZE

       ! SWMF: large arrays are allocated to save memory on other processors
       if(.not.allocated(eeta))then
          allocate(eeta(1-n_gc:isize+n_gc,1-n_gc:jsize+n_gc,kcsize))
          eeta = 0.0
       end if

       ! SWMF: Commented out because ModIoUnit::io_unit_new() provides the units
       ! IF (.NOT.Check_logical_units ( ) ) &
       !       call CON_stop('IM_ERROR: LUNs NOT AVAILABLE')
       !
       !
       !  Grid limit parameters
       i1   = 2          ! will reset anyway
       i2   = isize - 1
       ! j1   = jwrap
       j2   = jsize - 1
       iint = 1 
       jint = 1      
       !
       !
       CALL Read_grid ()
       !
       CALL Read_plasma ()
       !
       !
       call open_file(FILE = trim(NameRcmDir)//'rcm.params', STATUS = 'OLD')
       !
       READ (LUN,*) !     READ (LUN,*) itimei   ! 1.  start time
       READ (LUN,*) !     READ (LUN,*) itimef   ! 2.  end time
       READ (LUN,*) irdr     ! 3.  record # to read in
       READ (LUN,*) irdw     ! 4.  record # to write out
       READ (LUN, '(a80)') label%char! 5.  text label
       READ (LUN,*) idebug   ! 6.  0 <=> do disk printout
       READ (LUN,*) !     READ (LUN,*) idt          !  1.  basic time step in program
       READ (LUN,*) !     READ (LUN,*) iDtPlot_old  !  2.  t-step for changing disk write rcds
       READ (LUN,*) idt2  !  3.  t-step for writing formatted output
       READ (LUN,*) idt3  !  4.  t-step for invoking ADD & ZAP
       READ (LUN,*) imin  !  5.  i-value of poleward bndy
       READ (LUN,*) emptystring ! ipot  !  6.  which potential solver to use, moved to PARAM.in
       READ (LUN,*) iwind !  9.  0 is no neutral winds
       READ (LUN,*) ivoptn! 10.  1-euler time derivs in vcalc, 2-runge-kutta
       READ (LUN,*) emptystring ! ibnd_type  ! 14.  type of bndy, moved to PARAM.in
       READ (LUN,*) ipcp_type  ! 14.  type of bndy (1-eq.p, 2-iono)
       READ (LUN,*) nsmthi! 15.  How much to smooth cond in I
       READ (LUN,*) nsmthj! 16.  How much to smooth cond in J
       READ (LUN,*) icond ! 17.
       READ (LUN,*) ifloor! 18.
       READ (LUN,*) icorrect! 19.
       READ (LUN,*) dstmin ! min allowed dist. between adjacent pnts
       READ (LUN,*) dstmax ! max allowed dist. between adjacent pnts
       READ (LUN,*) rhomax
       READ (LUN,*) vmfact
       READ (LUN,*) epslon_edge  !  in MODULE rcm_mod_edgpt
       READ (LUN,*) fmrwif_dlim    ! min tail thickness for FMRWIF
       READ (LUN,*) cmax    ! in rcm_mod_balgn
       READ (LUN,*) eeta_cutoff ! as a fraction
       READ (LUN,*) tol_gmres
       READ (LUN,*) itype_bf  ! 1 is interpolate for HV, 2--friction code
       READ (LUN,*) i_advect 
       READ (LUN,*) i_eta_bc
       !    READ (LUN,*) L_dktime, sunspot_number, f107, doy !f107 is monthly mean!
       !      L_dktime = .FALSE.
       L_dktime = .TRUE.
       sunspot_number = 125
       f107           = 169
       doy            = 90
       !
       call close_file
       !
       i1 = imin + 1 
       !
       !
       !
       !  Read in other inputs, both constant and run-specific:
       CALL Read_vdrop  ()
       CALL Read_kp     ()
       CALL Read_bfield ()
       CALL Read_eta_on_bndy ()
       CALL Read_qtcond ()
       CALL Read_winds ()
       CALL Read_dktime (L_dktime)
       CALL Read_trf ()
       CALL Set_precipitation_rates ()
       !                                                                       
       IF (iProc == 0) THEN
          CALL Initial_printout () ! initialize formatted printout
       END IF
       !
       !
       !-->  Read initial locations of inner edges 
       !
       bi = 10.0
       bj = 25.0
       etab=0.0
       itrack = 1
       mpoint = 1
       npoint = 1
       IF (DoRestart) THEN
          call IM_write_prefix
          WRITE (iUnitOut,'(A)') '   Reading Restart File ...'
          !Open and read binary file
          write(filename,'(a)') "RCMrestart.rst"
          call open_file(FILE=trim(NameRcmDir)//"restartIN/"//filename, STATUS='old', &
               FORM='unformatted')
          read(LUN) eeta
          call close_file
          !  Replace eeta at boundaries only because we are reading from restart file.
          CALL Get_boundary (boundary, bndloc)
          CALL Rcm_plasma_bc (2, 1)
       ELSE
          ! Replace initial condition on ETA from file with one from MHD:
          CALL Get_boundary (boundary, bndloc)
          CALL Rcm_plasma_bc (2, 2)
       END IF
       !
       itrack (nptmax) = nptmax     !   3/96 frt
       IF (MAXVAL (ABS(itrack)) > nptmax) THEN
          call IM_write_prefix
          write(iUnitOut,'(A)') '  itrack(nptmax) is being reset'
          itrack (nptmax) = MAXVAL (ABS(itrack)) + 1
       END IF
       !                                                                       
       !                                                                       
       !
!!$ The volume is read from MHD so this hot restart is not needed.  Fix if needed
!!$ for stand alone RCM code.
!!$  !     IF hot restart, read V and check the time label:
!!$  !
!!$  IF (itimei /= 0) THEN
!!$     WRITE (*,'(A,I6,A)', ADVANCE='NO') &
!!$          'HOT restart, reading V from file to check time label at ',itimei,' ...'
!!$     CALL READ_array ('rcmv', irdr, label, ARRAY_2D = v)
!!$     IF (label%intg(6) /= itimei )  &
!!$          call CON_stop('IM_ERROR: T in file /=  ITIMEI for V')
!!$     WRITE (*,*) 'OK'
!!$     !
!!$  END IF
       !
       CALL MPI_BARRIER(iComm,ierror) ! ----------- BARRIER ------
       RETURN
       !
    case(2)  ! COMPUTE
       !
       !
       !*******************  main time loop  *************************
       !
       itout1 = 0 !itimei   ! next time to write to disk; set this to
       !                         ITIMEI to write out initial configuration
       itout2 = itimei   ! next time to do formatted output
       itcln = itimei    ! next time to call ADD & ZAP 
       !
       dt = REAL (idt)
       !
       fac = 1.0E-3_rprec * bir * alpha * beta * dlam * dpsi * ri**2 * signbe
       !
       DO i_time = itimei, itimef-idt, idt
          iTimeT1 = i_time

          !IF(iProc==0)THEN
          !   call IM_write_prefix; write(iUnitOut,*)'i_time=',i_time
          !END IF

          time0=MPI_Wtime()
          !
          CALL Comput (i_time, dt)

          CALL compute_efield

          IF (i_time == itcln) THEN
             !sys       CALL Clean_up_edges ()
             itcln = itcln + idt3
          END IF
          !
          !
          IF (i_time == 0) THEN
             !
             do ifile=1,nFilesPlot
                IF (iProc == 0) CALL Disk_write_arrays ( ifile )
             end do
          END IF
          !
          CALL Move_plasma ( dt )
          !
          call decay ( dt )
          !
          !Save current time for use in Disk_write_arrays
          iCurrentTime = i_time+idt
          !
          do iFile=1,nFilesPlot
             IF ( iDtPlot(ifile) > 0 .and. &
                  mod(iDtPlot(ifile), iDt) /= 0 ) then
                write(*,*)'WARNING in IM/RCM2: iFile, iDtPlot(ifile), iDt=',&
                     iFile, iDtPlot(ifile), iDt
                write(*,*)'WARNING: iDtPlot should be a multiple of iDt'
                iDtPlot(iFile) = iDt * (iDtPlot(iFile) / iDt + 1)
                write(*,*)'WARNING: iDtPlot is set to ',iDtPlot(iFile)
             end IF
             IF ( iDtPlot(ifile) > 0 .and. &
                  mod(iCurrentTime,     iDtPlot(ifile)) == 0 .or. &
                  iDnPlot(ifile) > 0 .and. &
                  mod(iCurrentTime/iDt, iDnPlot(ifile)) == 0) then
                !
                IF (iProc == 0) CALL Disk_write_arrays ( ifile )
                !
             END IF
          end do
          !
          ! If tracing satellites, write current sat records to file.
          ! !!! DTW 2007
          if (DoWriteSats .and. (nImSats>0) ) then
             do iFile=1, nImSats
                if (iProc == 0) call write_sat_file(iFile)
             end do
             IsFirstWrite = .false.
             DoWriteSats  = .false.
          end if

          !
          time1=MPI_Wtime()
          if(iProc == 0) then
             call IM_write_prefix
             write(iUnitOut,*)' Time ',i_time,'-',i_time+idt,' completed.' !, &
             !     '  CPUT =', time1-time0
          end if
          !
       END DO
       !
       CALL MPI_BARRIER(iComm,ierror) ! ----------- BARRIER ------
       RETURN
       !
    case(3)    ! FINALIZE
       !
       call close_file(LUN_3)
       CALL MPI_BARRIER(iComm,ierror) ! ----------- BARRIER ------
       RETURN

       ! cleanup mpi
       call IM_write_prefix
       write(iUnitOut,*)'PE=',iProc+1,' of ',nProc,' ending.'
!!$  call MPI_FINALIZE(ierror)
!!$!
!!$  STOP
       !
    case(4)    ! SAVE RESTART

       call Save_Restart

    case default

       call IM_write_prefix; write(*,*)' icontrol=',icontrol
       call CON_STOP("RCM_advec: incorrect icontrol value.")

    end select
    !========================================================================
  CONTAINS
    !
    !
    SUBROUTINE Initial_printout ()
      !
      CALL Date_and_time (real_date, real_time)
      IF (itimei == 0) THEN
         ST = 'REPLACE'
         PS = 'REWIND'
         HD = 'BEGINNING NEW RUN'
      ELSE
         ST = 'OLD'
         PS = 'APPEND'
         HD = 'CONTINUE SAME RUN'
      END IF
      ! Added for SWMF
      LUN_2 = io_unit_new()
      call open_file(LUN_2, FILE=trim(NameRcmDir)//'rcm.printout', STATUS=ST, POSITION=PS)
      LUN_3 = io_unit_new()
      call open_file(LUN_3, FILE=trim(NameRcmDir)//'rcm.index', STATUS=ST, POSITION=PS)
      WRITE (LUN_3,'(T2,A)',ADVANCE='NO') TRIM(HD)
      WRITE (LUN_3,'(A11,A4,A1,A2,A1,A2, A8,A2,A1,A2,A1,A2)') &
           '  TODAY IS ', real_date(1:4), '/', real_date(5:6), '/', real_date(7:8), &
           '  TIME: ',    real_time(1:2), ':', real_time(3:4), ':', real_time(5:6)
      WRITE (LUN_3,902) 
      !
      WRITE (LUN_2,*) 'START OF RCM RUN:'
      WRITE (LUN_2,'(A,I6,A,I6)') 'WILL START AT ITIMEI=',itimei, &
           '  AND STOP AT ITIMEF=',itimef
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'time step =', idt 
      WRITE (LUN_2,'(T5,A,T35,9I5.5)') 'disk write time step=', iDtPlot(1:nFilesPlot)
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'printout time step=', idt2 
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'edge cleanup time step=', idt3 
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'imin =', imin 
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'start at itimei=', itimei
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'stop at itimef=', itimef 
      WRITE (LUN_2,'(T5,A,T35,I5.5)') 'read at itimei from REC ---'
      WRITE (LUN_2,'(T5,A,T35)') 'start writing at REC ---'
      WRITE (LUN_2,'(/T5,A)' ) 'SIZES PARAMETERS:'
      WRITE (LUN_2,'(T10,A,T20,I6)') 'isize=',isize
      WRITE (LUN_2,'(T10,A,T20,I6)') 'jsize=',jsize
      WRITE (LUN_2,'(T10,A,T20,I6)') 'ksize=',ksize
      WRITE (LUN_2,'(T10,A,T20,I6)') 'kcsize=',kcsize
      WRITE (LUN_2,'(T10,A,T20,I6)') 'iesize=',iesize
      WRITE (LUN_2,'(/T5,A)' ) 'GRID PARAMETERS:'
      WRITE (LUN_2,'(T10,A,T20,G9.2)') 'dlam=',dlam
      WRITE (LUN_2,'(T10,A,T20,G9.2)') 'dpsi=',dpsi
      WRITE (LUN_2,'(T10,A,T20,G9.2)') 're=',re
      WRITE (LUN_2,'(T10,A,T20,G9.2)') 're=',re
      WRITE (LUN_2,'(T10,A,T20,3G9.2)') 'xmass',xmass
      WRITE (LUN_2,'(/T5,A)' ) 'PLASMA EDGES PARAMETERS:'
      DO k = 1, ksize
         WRITE (LUN_2,'(T10,A,I3,T25,A,I3,T40,A,G9.2,T60,A,ES9.2)')&
              'k=', k, 'ikflav=',ikflav(k), &
              'alam=',  alam(k), 'eta=', eta(k)
      END DO
      WRITE (LUN_2,'(/T5,A)' ) 'PLASMA GRID PARAMETERS:'
      DO kc = 1, kcsize
         WRITE (LUN_2,'(T10,A,I3,T20,A,G9.2,T45,A,ES9.2, T65,A,F5.3)') &
              'kc=', kc, 'alamc=',  alamc(kc), 'etac=', etac(kc), 'f=', fudgec(kc)
      END DO
      WRITE (LUN_2,'(/T5,A)' ) 'PCP INPUT PARAMETERS:'
      WRITE (LUN_2,'(T5,A,T20,I5)') 'nvmax =', SIZE(ivtime)
      DO n = 1, SIZE(ivtime)
         WRITE (LUN_2,'(T5,A,I5,T20,A,G9.2)') &
              'ivtime=',ivtime(n), 'vinput=',vinput(n)
      END DO
      WRITE (LUN_2,'(/T5,A)' ) 'BFIELD MARKTIMES:'
      WRITE (LUN_2,'(T5,A,T20,I6)') 'nbf =', SIZE(ibtime)
      DO n = 1, SIZE(ibtime)
         WRITE (LUN_2,'(T5,A,I5)') 'ibtime=',ibtime(n)
      END DO
      WRITE (LUN_2,'(/T5,A)' ) 'KP MARKTIMES:'
      WRITE (LUN_2,'(T5,A,T20,I6)') 'nkpmax =', SIZE(ikptime)
      DO n = 1, SIZE(ikptime)
         WRITE (LUN_2,'(T5,A,I5)') 'ikptime=',ikptime(n)
      END DO
      WRITE (LUN_2,'(T2,A,T20,I2)')     'IPOT =',     ipot
      WRITE (LUN_2,'(T2,A,T20,I2)')     'ICOND = ',   icond
      WRITE (LUN_2,'(T2,A,T20,I2)')     'IBND = ',    ibnd_type
      WRITE (LUN_2,'(T2,A,T20,I2)')     'IPCP_TYPE=', ipcp_type
      !
      call close_file(LUN_2)
      !
      !
902   FORMAT (T2,'TIME', T12,'ITIME' , T19,'REC#' ,&
           T26,'VDROP', T33,'KP', T39,'FSTOFF',   &
           T46,'FMEB', T53, 'DST', T62,'FCLPS', T69,'VDROP_PHASE' )

    END SUBROUTINE Initial_printout
    !
    !
    subroutine Write_Label(i_write_time)
      integer, intent(in) :: i_write_time

      label%intg = 0
      label%real = 0.0_rprec
      label%char   = ''
      !
      !        UT TIME  = HH:MM:SS=ilabel(3):ilabel(4):ilabel(5)
      !
      label%intg (1) = 0  ! record # for disk printout
      label%intg (2) = i_write_time ! UT in seconds
      label%intg (3) = (i_write_time) / 3600! hours of UT
      label%intg (4) = MOD (label%intg (2), 3600) / 60 ! minutes of UT
      label%intg (5) = MOD (label%intg (2), 60)  ! seconds of UT time
      label%intg (6) = i_write_time       ! elapsed time in seconds
      label%intg (8) = isize
      label%intg (9) = jsize
      label%intg (10) = ksize
      !    label%intg (12) used in OUTPUT and READ3D for kmax(=kdim)
      !    label%intg (13) used in OUTPUT and READ3D for k-index
      label%intg (14) = - 1
      !
      !    label%real (1) = eb   !phoney loss
      label%real (2) = cmax
      label%real (12) = fmeb
      label%real (13) = fstoff
      label%real (14) = fdst
      label%real (15) = fclps
      label%real (16) = vdrop
      label%real (17) = kp

    end subroutine Write_Label
    !
    !
    SUBROUTINE Disk_write_arrays_ALL
      !
      ! Write all plot files regardless of requested frequency.
      !
      do ifile=1,nFilesPlot
         IF (iProc == 0) CALL Disk_write_arrays ( ifile )
      end do
    end SUBROUTINE Disk_write_arrays_ALL
    !=========================================================================
    SUBROUTINE Disk_write_arrays ( iFN )
      !
      ! Pass in current time in seconds (iWT) and file number (iFN) to write
      !
      use CON_physics, ONLY: get_time
      use ModTimeConvert, ONLY: time_real_to_int
      use ModKind, ONLY: Real8_

      integer :: iTime_I(7)
      real(Real8_) :: tCurrent

      integer, intent(in) :: iFN
      integer :: iIT
      integer, save :: iLastIT=-1
      character(len=4)  :: extension
      character(len=10) :: time_string = "xxxxxxxxxx"
      character(len=500) :: StringLine ! for IDL output

      REAL (rprec), DIMENSION (1-n_gc:isize+n_gc, 1-n_gc:jsize+n_gc) :: &
           RCM_p, RCM_n, RCM_T, RCM_PVgamma, MHD_p, veff, RCM_Hpp, RCM_Opp, &
           RCM_Hpn, RCM_HpT, RCM_Opn, RCM_OpT, RCM_HpPVgamma,RCM_OpPVgamma, &
           MHD_Hpp, MHD_Opp

      !---------------------------------------------------------------------
      !Computed iteration number
      iIT = -2
      if(idt>0) iIT=int(iCurrentTime/idt)

      !Fill labels
      call Write_Label(iCurrentTime)
      call Date_and_time (real_date, real_time)

      !Old output
      WRITE (time_char,'(I2.2,A1,I2.2,A1,I2.2)') &
           label%intg(3), ':', label%intg(4), ':', label%intg(5)
      call IM_write_prefix
      WRITE (iUnitOut,'(A15,I5.5,A13,3A4,TR4)') &
           '   Saving at T=',iCurrentTime,'s ('//time_char//') ',&
           plot_area(iFN),plot_var(iFN),plot_format(iFN)
      if(iIT /= iLastIT)then
         iLastIT=iIT
         WRITE (lun_3,901) time_char, &
              iCurrentTime, 0, vdrop, kp, fstoff, fmeb, fdst, fclps, vdrop_phase
901      FORMAT (T2,A8, T12,I6, T19,I5, T26,F5.1, T33,F4.2,&
              T39,F5.2, T46,F5.2, T53,F7.1, T62,F5.1, T69, F6.2)
      end if

      !Create filename
      select case(plot_format(iFN))
      case('tec')
         extension='.dat'
      case('idl')
         extension='.idl'
      end select

      if(UseEventPlotName)then
         call get_time(tCurrentOut = tCurrent)
         call time_real_to_int(tCurrent, iTime_I)
         write(filename,'(a,i4.4,2i2.2,"_",3i2.2,a)') &
              plot_area(iFN)//"_"//plot_var(iFN)//"_e", iTime_I(1:6), extension
      else
         ! Use simulation time: hours,minutes,seconds
         write(filename,'(a,i4.4,i2.2,i2.2,a)') &
              plot_area(iFN)//"_"//plot_var(iFN)//"_t",&
              label%intg(3),label%intg(4),label%intg(5),extension
      end if
      !Create time string
      WRITE(time_string,'(I4.4,A1,I2.2,A1,I2.2)') &
           label%intg(3),":",label%intg(4),":",label%intg(5)

      !Open file
      select case(plot_format(iFN))
      case('tec')
         call open_file(FILE=trim(NameRcmDir)//"plots/"//filename)
      case('idl')
         call open_file(FILE=trim(NameRcmDir)//"plots/"//filename, &
              FORM='unformatted')
      end select

      ! Write plot file: header followed by the data
      select case(plot_area(iFN))
      case('2d_')
         ! Write header
         select case(plot_format(iFN))
         case('tec')
            WRITE (LUN,'(A)')'TITLE="RCM-BATSRUS: T='//time_string//'"'
            select case(plot_var(iFN))
            case('min')
               if(.not. DoMultiFluidGMCoupling)then
                  WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]",&
                       &"N(RCM) [cm-3]","T(RCM) [eV]","P(RCM) [nPa]",&
                       &"N(MHD) [cm-3]","T(MHD) [eV]","P(MHD) [nPa]"'
               else
                  ! Multifluid-output
                  WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]",&
                       &"N_H(RCM) [cm-3]","T_H(RCM) [eV]","P_H(RCM) [nPa]",&
                       &"N_O(RCM) [cm-3]","T_O(RCM) [eV]","P_O(RCM) [nPa]",&
                       &"N_H(MHD) [cm-3]","T_H(MHD) [eV]","P_H(MHD) [nPa]",&
                       &"N_O(MHD) [cm-3]","T_O(MHD) [eV]","P_O(MHD) [nPa]"'
                  write(*,*)'writing multifluid header'
               end if
            case('max')
               if(.not. DoMultiFluidGMCoupling)then
                  WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]","I","J",&
                       &"COLAT","ALOCT","MLT","BNDLOC","VM","|B| [nT]","V",&
                       &"BIRK(NH)","PEDLAM [S]","PEDPSI [S]","HALL [S]","EFLUX",&
                       &"EAVG","N(RCM) [cm-3]","T(RCM) [eV]","P(RCM) [nPa]",&
                       &"PV_gamma","Birk_mhd(NH)","N(MHD) [cm-3]","T(MHD) [eV]",&
                       &"P(MHD) [nPa]","sigmaH(MHD)","sigmaP(MHD)"'
               else
                  write(*,*)'writing multifluid header'
                  WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]","I","J",&
                       &"COLAT","ALOCT","MLT","BNDLOC","VM","|B| [nT]","V",&
                       &"BIRK(NH)","PEDLAM [S]","PEDPSI [S]","HALL [S]","EFLUX",&
                       &"EAVG",&
                       &"N_H(RCM) [cm-3]","T_H(RCM) [eV]","P_H(RCM) [nPa]","PV_Hpgamma",&
                       &"N_O(RCM) [cm-3]","T_O(RCM) [eV]","P_O(RCM) [nPa]","PV_Opgamma",&
                       &"Birk_mhd(NH)",&
                       &"N_H(MHD) [cm-3]","T_H(MHD) [eV]","P_H(MHD) [nPa]",&
                       &"N_O(MHD) [cm-3]","T_O(MHD) [eV]","P_O(MHD) [nPa]",&
                       &"sigmaH(MHD)","sigmaP(MHD)"'
               endif
            case('mc1')
               WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]","COLAT [deg]","ALOCT [rad]","MLT [hrs]",&
                    &"BNDLOC","VM","|Bmin| [nT]","Pot [V]",&
                    &"BIRK(NH) [microAmp/m2]","Sigma_P [S]","Sigma_H [S]","EFLUX_e [erg/cm2/s]",&
                    &"EAVG_e [eV]",&
                    &"N_e(RCM) [cm-3]","T_e(RCM) [eV]","P_e(RCM) [nPa]","PVg_e",&
                    &"N_H(RCM) [cm-3]","T_H(RCM) [eV]","P_H(RCM) [nPa]","PVg_H",&
                    &"N_O(RCM) [cm-3]","T_O(RCM) [eV]","P_O(RCM) [nPa]","PVg_O",&
                    &"N_total(RCM) [cm-3]", "P_total(RCM) [nPa]", "PVg_total(RCM)", "N_plasmasphere(RCM), [cm-3]"'
            case('mc2')
               WRITE (LUN,'(A)')'VARIABLES="X [R]","Y [R]","COLAT [deg]","ALOCT [rad]","MLT [hrs]",&
                    &"BNDLOC","VM","|Bmin| [nT]","Pot [V]",&
                    &"BIRK(NH) [microAmp/m2]","Sigma_P [S]","Sigma_H [S]","EFLUX_e [erg/cm2/s]",&
                    &"EAVG_e [eV]",&
                    &"N_e(RCM) [cm-3]","T_e(RCM) [eV]","P_e(RCM) [nPa]","PVg_e",&
                    &"N_H(RCM) [cm-3]","T_H(RCM) [eV]","P_H(RCM) [nPa]","PVg_H",&
                    &"N_O(RCM) [cm-3]","T_O(RCM) [eV]","P_O(RCM) [nPa]","PVg_O",&
                    &"N_total(RCM) [cm-3]", "P_total(RCM) [nPa]", "PVg_total(RCM)","N_plasmasphere(RCM), [cm-3]"'
            end select
            WRITE (LUN,'(A,I4,A,I4,A)') &
                 'ZONE T="RCM-2D-'//time_string//'" I=', isize, &
                 ', J=',jsize+1,', F=POINT'
            WRITE (LUN,'(A,A,A)')    'AUXDATA TIME="',time_string,'"'
            WRITE (LUN,'(A,I7.7,A)') 'AUXDATA ITERATION="',iIT,'"'
            WRITE (LUN,'(A, A11,A4,A1,A2,A1,A2, A4,A2,A1,A2,A1,A2, A)') &
                 'AUXDATA SAVEDATE="', &
                 'Save Date: ', real_date(1:4),'/',real_date(5:6),'/',real_date(7:8), &
                 ' at ',  real_time(1:2),':',real_time(3:4),':',real_time(5:6), '"'
         case('idl')
            select case(plot_var(iFN))
            case('min')
               ! Header string containing units for coordinates and variables
               StringLine='deg deg R R amu/cm3 eV nPa amu/cm3 eV nPa'
               write(LUN) StringLine
               ! Time step, time, no. dimensions, equation params, variables
               write(LUN) iIT,real(iCurrentTime),2,0,8
               ! Grid size
               write(LUN) jSize+1, iSize
               ! Name of coordinates and variables
               if(.not. DoMultiFluidGMCoupling)then   
                  StringLine = 'lon lat x y rho T p rho_mhd T_mhd p_mhd'
                  write(LUN) StringLine
               else
                  StringLine = 'lon lat x y '// &
                       'rho_Hp T_Hp p_Hp rho_Op T_Op p_Op '// &
                       'rho_Hp_mhd T_Hp_mhd p_Hp_mhd rho_Op_mhd T_Op_mhd p_Op_mhd'
               end if
            case('max')
               ! Header string containing units for coordinates and variables
               StringLine='deg deg R R hr - - nT - - S S S - - - - - -'
               write(LUN) StringLine
               ! Time step, time, no. dimensions, equation params, variables
               write(LUN) iIT,real(iCurrentTime),2,0,17
               ! Grid size
               write(LUN) jSize+1, iSize
               ! Name of coordinates and variables 
               StringLine = 'lon lat x y mlt bnd vm b v '// &
                    'birk pedlam pedpsi hall eflux eavg pvg birkmhd sH sP'
               write(LUN) StringLine
            case('mc1')
               ! Header string containing units for coordinates and variables
               StringLine= &
                    'deg deg R R hr - - nT V microAmp/m2 S S erg/cm2/s eV '//&
                    'cm-3 eV nPa - cm-3 eV nPa - cm-3 eV nPa - cm-3 nPa - cm-3'
               write(LUN) StringLine
               ! Time step, time, no. dimensions, equation params, variables
               write(LUN) iIT,real(iCurrentTime),2,0,28
               ! Grid size
               write(LUN) jSize+1, iSize
               ! Name of coordinates and variables
               StringLine = &
                    'lon lat x y mlt bnd vm b v birk sigmaP sigmaH eflux '//&
                    'eavg n_e T_e P_e pvg_e n_h T_h P_h pvg_h n_o T_o P_o '//&
                    'pvg_o n_total P_total pvg_total n_plasmasphere'
               write(LUN) StringLine
            case('mc2')
               ! Header string containing units for coordinates and variables
               StringLine=&
                    'deg deg R R hr - - nT V microAmp/m2 S S erg/cm2/s eV '//&
                    'cm-3 eV nPa - cm-3 eV nPa - cm-3 eV nPa - cm-3 nPa - cm-3'
               write(LUN) StringLine
               ! Time step, time, no. dimensions, equation params, variables
               write(LUN) iIT,real(iCurrentTime),2,0,28
               ! Grid size
               write(LUN) jSize+1, iSize
               ! Name of coordinates and variables
               StringLine = &
                    'lon lat x y mlt bnd vm b v birk sigmaP sigmaH eflux '//&
                    'eavg n_e T_e P_e pvg_e n_h T_h P_h pvg_h n_o T_o P_o '//&
                    'pvg_o n_total P_total pvg_total n_plasmasphere'
               write(LUN) StringLine
            end select
         end select

         ! For CCMC output, we will compute moments in a different way.
         ! Later, will switch to this for all kinds of output:
         if ( plot_var(iFN) == 'mc1' .OR. plot_var(iFN) == 'mc2') then
            CALL Rcm_compute_plasma_moments
            ! No need to wrap ghostcells, as this runs over all cells
            ! field-line integrated Pedersen conductance
            sigma_P = sqrt(pedpsi*pedlam)
            ! field-line integrated Hall conductance
            sigma_H = hall
         end if

         if(.not.DoMultiFluidGMCoupling)then
            RCM_p = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_p(i,j) = -1.
               else    
                  do k=1,kcsize
                     RCM_p(i,j) = RCM_p(i,j) + &
                          vm(i,j)**2.5*eeta(i,j,k)*ABS(alamc(k))
                  end do
               end if
            end do; end do
            RCM_p = RCM_p * 1.67E-35/ 1.0E-9

            RCM_pvgamma = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_pvgamma(i,j) = -1.
               else    
                  do k=1,kcsize
                     RCM_pvgamma(i,j) = RCM_pvgamma(i,j) + eeta(i,j,k)*ABS(alamc(k))
                  end do
               end if
            end do; end do
            RCM_pvgamma = RCM_pvgamma * 2.0/3.0

            RCM_n = 0.
            RCM_T = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_T(i,j) = -1.
                  RCM_n(i,j) = -1.
               else if (rcm_pvgamma(i,j) == 0.0) THEN
                  RCM_n(i,j) = 0.0
                  RCM_t(i,j) = 0.0
               else    
                  !compute number density and temperature, for positive ions only
                  do k=1,kcsize
                     if (alamc(k) <= 0) cycle
                     RCM_n(i,j) = RCM_n(i,j) + eeta(i,j,k)*vm(i,j)**1.5/6.37E+21
                     RCM_T(i,j)=RCM_T(i,j) + eeta(i,j,k)
                  end do
                  RCM_T(i,j) = vm(i,j)*RCM_pvgamma(i,j)/SUM(eeta(i,j,:))
               end if
               MHD_P(i,j) = density(i,j)*1.0E+6*temperature(i,j)*1.6E-19 &
                    / 1.0E-9 ![nPa]
            end do; end do
         else
            ! MultiFluids
            !Compute some variables
            RCM_p   = 0.
            RCM_Hpp = 0.
            RCM_Opp = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_p(i,j) = -1.
                  RCM_Hpp(i,j) = -1.
                  RCM_Opp(i,j) = -1.
               else    
                  do k=kmin(2),kmax(2)
                     RCM_Hpp(i,j) = RCM_Hpp(i,j) + &
                          vm(i,j)**2.5*eeta(i,j,k)*ABS(alamc(k))
                  end do
                  do k=kmin(3),kmax(3)
                     RCM_Opp(i,j) = RCM_Opp(i,j) + &
                          vm(i,j)**2.5*eeta(i,j,k)*ABS(alamc(k))
                  end do
                  do k=1,kcsize
                     RCM_p(i,j) = RCM_p(i,j) + &
                          vm(i,j)**2.5*eeta(i,j,k)*ABS(alamc(k))
                  end do
               end if
            end do; end do
            RCM_p = RCM_p * 1.67E-35/ 1.0E-9
            RCM_Hpp = RCM_Hpp * 1.67E-35/1.0E-9
            RCM_Opp = RCM_Opp * 1.67E-35/1.0E-9


            RCM_pvgamma = 0.
            RCM_Hppvgamma = 0.
            RCM_Oppvgamma = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_pvgamma(i,j) = -1.
                  RCM_Hppvgamma(i,j) = -1.
                  RCM_Oppvgamma(i,j) = -1.
               else    
                  do k=kmin(2),kmax(2)
                     RCM_Hppvgamma(i,j) = RCM_Hppvgamma(i,j) + eeta(i,j,k)*ABS(alamc(k))
                  end do
                  do k=kmin(3),kmax(3)
                     RCM_Oppvgamma(i,j) = RCM_Oppvgamma(i,j) + eeta(i,j,k)*ABS(alamc(k))
                  end do
                  do k=1,kcsize
                     RCM_pvgamma(i,j) = RCM_pvgamma(i,j) + eeta(i,j,k)*ABS(alamc(k))
                  end do
               end if
            end do; end do
            RCM_pvgamma = RCM_pvgamma * 2.0/3.0
            RCM_Hppvgamma = RCM_Hppvgamma * 2.0/3.0
            RCM_Oppvgamma = RCM_Oppvgamma * 2.0/3.0

            RCM_n   = 0.
            RCM_T   = 0.
            RCM_Hpn = 0.
            RCM_HpT = 0.
            RCM_Opn = 0.
            RCM_OpT = 0.
            MHD_HpP = 0.
            MHD_OpP = 0.
            do i=1,isize; do j=1,jsize
               if( i<imin_j(j) ) then
                  RCM_T(i,j) = -1.
                  RCM_n(i,j) = -1.
                  RCM_Hpn(i,j) = -1.
                  RCM_HpT(i,j) = -1.
                  RCM_Opn(i,j)= -1.
                  RCM_OpT(i,j) = -1.
               else if (rcm_pvgamma(i,j) == 0.0) THEN
                  RCM_n(i,j) = 0.0
                  RCM_t(i,j) = 0.0
               else if (rcm_Hppvgamma(i,j) == 0.0) then
                  RCM_Hpn(i,j) = 0.0
                  RCM_Hpt(i,j) = 0.0
               else if (rcm_Oppvgamma(i,j) == 0.0) then
                  RCM_Opn(i,j) = 0.0
                  RCM_Opt(i,j) = 0.0
               else
                  !compute number density and temperature, for positive ions only
                  do k=kmin(2),kmax(2)
                     if(alamc(k) <=0)cycle
                     RCM_Hpn(i,j) = RCM_Hpn(i,j) + eeta(i,j,k)*vm(i,j)**1.5/6.37E+21
                     RCM_HpT(i,j) = RCM_HpT(i,j) + eeta(i,j,k)
                  end do
                  do k=kmin(3),kmax(3)
                     RCM_Opn(i,j) = RCM_Opn(i,j) + eeta(i,j,k)*vm(i,j)**1.5/6.37E+21
                     RCM_OpT(i,j) = RCM_OpT(i,j) + eeta(i,j,k)
                  end do
                  RCM_HpT(i,j) = vm(i,j)*RCM_Hppvgamma(i,j)/SUM(eeta(i,j,:))
                  RCM_OpT(i,j) = vm(i,j)*RCM_Oppvgamma(i,j)/SUM(eeta(i,j,:))           
                  MHD_HpP(i,j) = densityHp(i,j)*1.0E+6*temperatureHp(i,j)*1.6E-19 &
                       / 1.0E-9 ![nPa]
                  MHD_OpP(i,j) = densityOp(i,j)*1.0E+6*temperatureOp(i,j)*1.6E-19 &
                       / 1.0E-9 ![nPa]            
                  do k=1,kcsize
                     if (alamc(k) <= 0) cycle
                     RCM_n(i,j) = RCM_n(i,j) + eeta(i,j,k)*vm(i,j)**1.5/6.37E+21
                     RCM_T(i,j) = RCM_T(i,j) + eeta(i,j,k)
                  end do
                  RCM_T(i,j) = vm(i,j)*RCM_pvgamma(i,j)/SUM(eeta(i,j,:))
                  MHD_P(i,j) = density(i,j)*1.0E+6*temperature(i,j)*1.6E-19 &
                       / 1.0E-9 ![nPa]          
               end if
            end do; end do
         end if

         if(.not.DoMultiFluidGMCoupling)then
            CALL Wrap_around_ghostcells (RCM_n, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_T, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_p, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_pvgamma,isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (MHD_p,isize,jsize,n_gc)
         else
            CALL Wrap_around_ghostcells (RCM_n, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_T, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_p, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_pvgamma,isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (MHD_p, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Hpn, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_HpT, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Hpp, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Hppvgamma,isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (MHD_Hpp,isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Opn, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_OpT, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Opp, isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (RCM_Oppvgamma,isize,jsize,n_gc)
            CALL Wrap_around_ghostcells (MHD_Opp,isize,jsize,n_gc)
         end if

         !Write data
         select case(plot_format(iFN))
         case('tec')
            select case(plot_var(iFN))
            case('min')
               do j=1,jsize+1; do i=1,isize
                  if(.not. DoMultiFluidGMCoupling)then
                     write(LUN,'(8ES12.3)') &
                          xmin(i,j), ymin(i,j), &
                          RCM_n(i,j), RCM_T(i,j), RCM_P(i,j), &
                          density(i,j), temperature(i,j), MHD_p(i,j)
                  else
                     write(LUN,'(14ES12.3)') &
                          xmin(i,j), ymin(i,j), &
                          RCM_Hpn(i,j),RCM_HpT(i,j),RCM_HpP(i,j),&
                          RCM_Opn(i,j),RCM_OpT(i,j),RCM_OpP(i,j),&
                          densityHp(i,j), temperatureHp(i,j), MHD_Hpp(i,j),&
                          densityOp(i,j), temperatureOp(i,j), MHD_Opp(i,j)
                  end if
               end do; end do
            case('max')
               do j=1,jsize+1; do i=1,isize
                  if(.not. DoMultiFluidGMCoupling)then
                     write(LUN,'(2ES12.3,2I4,23ES12.3)') &
                          xmin(i,j), ymin(i,j), i, j, colat(i,j)*rtd, aloct(i,j), &
                          MODULO(aloct(i,j)*rth+12.0,24.01), bndloc(j), vm(i,j), &
                          bmin(i,j), &
                          v(i,j), 0.5*birk(i,j), pedlam(i,j), pedpsi(i,j),&
                          hall(i,j), eflux(i,j,1), eavg(i,j,1), &
                          RCM_n(i,j), RCM_T(i,j), RCM_P(i,j), RCM_pvgamma(i,j),&
                          -birk_mhd(i,j)/1.0E-6, density(i,j), temperature(i,j), &
                          MHD_p(i,j), sigmaH_mhd(i,j),sigmaP_mhd(i,j)
                  else
                     !write(*,*)'!!! i,j=',i,j
                     !write(*,*)'xmin',xmin(i,j)
                     !write(*,*)'ymin', ymin(i,j)
                     !write(*,*)'rtd', rtd
                     !write(*,*)'colat', colat(i,j)
                     !write(*,*)'aloct', aloct(i,j)
                     !write(*,*)'rth', rth
                     !write(*,*)'bndloc', bndloc(j)
                     !write(*,*)'vm', vm(i,j)                        
                     !write(*,*)'bmin', bmin(i,j) 
                     !write(*,*)'v', v(i,j)
                     !write(*,*)'birk', birk(i,j)
                     !write(*,*)'pedlam', pedlam(i,j)
                     !write(*,*)'pedpsi', pedpsi(i,j)                                 
                     !write(*,*)'hall', hall(i,j)
                     !write(*,*)'eflux', eflux(i,j,1)
                     !write(*,*)'eavg', eavg(i,j,1)
                     !write(*,*)'RCM_Hpn', RCM_Hpn(i,j)
                     !write(*,*)'RCM_HpT', RCM_HpT(i,j)
                     !write(*,*)'RCM_HpP', RCM_HpP(i,j)
                     !write(*,*)'RCM_Hpp', RCM_Hppvgamma(i,j)
                     !write(*,*)'RCM_Opn', RCM_Opn(i,j)
                     !write(*,*)'RCM_OpT', RCM_OpT(i,j)
                     !write(*,*)'RCM_OpP', RCM_OpP(i,j)
                     !write(*,*)'RCM_Opp', RCM_Oppvgamma(i,j)                    
                     !write(*,*)'birk_mhd', birk_mhd(i,j)
                     !write(*,*)'densityHp', densityHp(i,j)
                     !write(*,*)'temperatur', temperatureHp(i,j)
                     !write(*,*)'MHD_Hpp,', MHD_Hpp(i,j)                               
                     !write(*,*)'densityOp', densityOp(i,j)
                     !write(*,*)'temperatur', temperatureOp(i,j)
                     !write(*,*)'MHD_Opp,', MHD_Opp(i,j)                               
                     !write(*,*)'sigmaH_mhd', sigmaH_mhd(i,j)
                     !write(*,*)'sigmaP_mhd', sigmaP_mhd(i,j) 

                     write(LUN,'(2ES12.3,2I4,30ES12.3)') &
                          xmin(i,j), ymin(i,j), i, j, colat(i,j)*rtd, aloct(i,j), &
                          MODULO(aloct(i,j)*rth+12.0,24.01), bndloc(j), vm(i,j), &
                          bmin(i,j), &
                          v(i,j), 0.5*birk(i,j), pedlam(i,j), pedpsi(i,j),&
                          hall(i,j), eflux(i,j,1), eavg(i,j,1), &
                          RCM_Hpn(i,j), RCM_HpT(i,j), RCM_HpP(i,j), RCM_Hppvgamma(i,j),&
                          RCM_Opn(i,j), RCM_OpT(i,j), RCM_OpP(i,j), RCM_Oppvgamma(i,j),&
                          -birk_mhd(i,j)/1.0E-6,&
                          densityHp(i,j), temperatureHp(i,j), MHD_Hpp(i,j), &
                          densityOp(i,j), temperatureOp(i,j), MHD_Opp(i,j), &
                          sigmaH_mhd(i,j),sigmaP_mhd(i,j)
                  end if
               end do; end do
            end select
         case('idl')
            ! Make sure that lon-lat grid is structured
            ! Save LON-LAT coordinates as a single record
            write(LUN) &
                 ((aloct(i,j)*rtd,j=1,jsize) &
                 , aloct(i,jsize+1)*rtd+360,             i=isize,1,-1), &
                 ((90.0 - colat(i,j)*rtd,  j=1,jsize+1), i=isize,1,-1)

            ! Save common plot variables. Each variable is a new record
            write(LUN) ((xmin(i,j),        j=1,jsize+1), i=isize,1,-1)
            write(LUN) ((ymin(i,j),        j=1,jsize+1), i=isize,1,-1)

            ! Save remaining variables
            select case(plot_var(iFN))
            case('min')
               if(.not. DoMultiFluidGMCoupling)then
                  write(LUN) ((RCM_n(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_T(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_P(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((density(i,j),     j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((temperature(i,j), j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((MHD_P(i,j),       j=1,jsize+1), i=isize,1,-1)
               else
                  write(LUN) ((RCM_Hpn(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_HpT(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_HpP(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_Opn(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_OpT(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((RCM_OpP(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((densityHp(i,j),     j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((temperatureHp(i,j), j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((MHD_HpP(i,j),       j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((densityOp(i,j),     j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((temperatureOp(i,j), j=1,jsize+1), i=isize,1,-1)
                  write(LUN) ((MHD_OpP(i,j),       j=1,jsize+1), i=isize,1,-1)
               end if

            case('max')
               write(LUN) ((MODULO(aloct(i,j)*rth+12.0,24.01) &
                    ,                         j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bndloc(j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((vm(i,j),          j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bmin(i,j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((v(i,j),           j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((0.5*birk(i,j),    j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((pedlam(i,j),      j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((pedpsi(i,j),      j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((hall(i,j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eflux(i,j,1),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eavg(i,j,1),      j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvgamma(i,j), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((-birk_mhd(i,j)/1.0E-6 &
                    ,                         j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigmaH_mhd(i,j),  j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigmaP_mhd(i,j),  j=1,jsize+1), i=isize,1,-1)

               !do i=isize,1,-1; do j=1,jsize+1; 
               !   write(UNITTMP_,'(100(1pe18.10))') &
               !        aloct(i,j)*rtd, 90.0 - colat(i,j)*rtd, &
               !        xmin(i,j), ymin(i,j), &
               !        MODULO(aloct(i,j)*rth+12.0,24.01), &
               !        bndloc(j), vm(i,j), &
               !        bmin(i,j), &
               !        v(i,j), 0.5*birk(i,j), pedlam(i,j), pedpsi(i,j),&
               !        hall(i,j), eflux(i,j,1), eavg(i,j,1), &
               !        RCM_pvgamma(i,j),&
               !        -birk_mhd(i,j)/1.0E-6, sigmaH_mhd(i,j), sigmaP_mhd(i,j)
               !end do; end do
            case('mc1')
               write(LUN) ((MODULO(aloct(i,j)*rth+12.0,24.01) &
                    ,                         j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bndloc(j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((vm(i,j),          j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bmin(i,j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((v(i,j),           j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((0.5*birk(i,j),    j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigma_P(i,j),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigma_H(i,j),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eflux(i,j,1),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eavg(i,j,1),      j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_dens_cm3(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_pres_nPa(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_pvg_spc(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eeta(i,j,1)*vm(i,j)**(2./3.)/(Re*1.0E+18), j=1,jsize+1), i=isize,1,-1)
            case('mc2')
               write(LUN) ((MODULO(aloct(i,j)*rth+12.0,24.01) &
                    ,                         j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bndloc(j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((vm(i,j),          j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((bmin(i,j),        j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((v(i,j),           j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((0.5*birk(i,j),    j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigma_P(i,j),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((sigma_H(i,j),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eflux(i,j,1),     j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eavg(i,j,1),      j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,1), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,2), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_dens_cm3(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_temp_eVs(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pres_nPa(i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((RCM_pvg_spc (i,j,3), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_dens_cm3(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_pres_nPa(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((SUM(RCM_pvg_spc(i,j,:)), j=1,jsize+1), i=isize,1,-1)
               write(LUN) ((eeta(i,j,1)*vm(i,j)**(2./3.)/(Re*1.0E+18), j=1,jsize+1), i=isize,1,-1)
            end select
         end select
      case('3d_')
         !Write header
         select case(plot_format(iFN))
         case('tec')
            WRITE (LUN,'(A)')'TITLE="RCM-BATSRUS: T='//time_string//'"'
            select case(plot_var(iFN))
            case('min')
               WRITE (LUN,'(A)')'VARIABLES="I","J","K","EETA","VEFF"'
            case('max')
               WRITE (LUN,'(A)')'VARIABLES="I","J","K","X [R]","Y [R]",&
                    &"COLAT","ALOCT","MLT","BNDLOC","VM","|B| [nT]",&
                    &"V", "BIRK(NH)","ALAM", "EETA", "VEFF","W [eV]"'
            end select
            WRITE (LUN,'(A,I4,A,I4,A,I4,A)') &
                 'ZONE T="RCM-3D-'//time_string//'" I=', isize, &
                 ', J=',jsize+1,', K=',kcsize,', F=POINT'
            WRITE (LUN,'(A,A,A)')    'AUXDATA TIME="',time_string,'"'
            WRITE (LUN,'(A,I7.7,A)') 'AUXDATA ITERATION="',iIT,'"'
            WRITE (LUN,'(A, A9,A4,A1,A2,A1,A2, A8,A2,A1,A2,A1,A2, A)') &
                 'AUXDATA SAVEDATE="', &
                 'TODAY IS ', real_date(1:4),'/',real_date(5:6),'/',real_date(7:8), &
                 '  TIME: ',  real_time(1:2),':',real_time(3:4),':',real_time(5:6), '"'
         case('idl')
            !Put idl header here later
            call CON_stop( &
                 'RCM_ERROR: 3D data with IDL format is not implemented')
         end select

         !Write data
         select case(plot_var(iFN))
         case('min')
            do k=1,kcsize
               veff = v + vcorot + vm*alamc(k)
               CALL Wrap_around_ghostcells (veff, isize,jsize,n_gc)
               do j=1,jsize+1; do i=1,isize
                  write(LUN,'(3i4,2ES12.3)') &
                       i, j, k, eeta(i,j,k), veff(i,j)
               end do; end do
            end do
         case('max')
            do k=1,kcsize
               veff = v + vcorot + vm*alamc(k)
               CALL Wrap_around_ghostcells (veff, isize,jsize,n_gc)
               do j=1,jsize+1; do i=1,isize
                  write(LUN,'(3i4,14ES12.3)') &
                       i, j, k, xmin(i,j), ymin(i,j), colat(i,j)*rtd,aloct(i,j),&
                       MODULO(aloct(i,j)*rth+12.0,24.01),&
                       bndloc(j), vm(i,j), bmin(i,j), &
                       v(i,j), birk(i,j)/2.0, alamc(k),eeta(i,j,k), veff(i,j), &
                       alamc(k)*vm(i,j)
               end do; end do
            end do
         end select

      end select

      call close_file

    end SUBROUTINE Disk_write_arrays
    !=========================================================================
    subroutine write_sat_file(iSatIn)
      ! Write solution interpolated to satellite position to satellite files.
      ! !!!DTW  2007.
 
      ! Arguments
      integer, intent(in) :: iSatIn

      ! Name of subroutine
      character(len=*), parameter :: NameSubSub = 'rcm_advec.write_sat_file'

      !internal variables
      integer            :: iError
      integer, parameter :: nHeadVar=11, nDistVar=4
      real               :: HeadVar_I(nHeadVar), DistVar_II(kcsize,nDistVar)
      logical            :: IsExist
      character(len=100) :: NameSatFile, StringTime
      !------------------------------------------------------------------------
      ! Build file name; 
      if (IsFirstWrite) iStartIter = int(iCurrentTime/idt)
      write(NameSatFile, '(a, i6.6, a)')                    &
           trim(NameRcmDir)//'plots/'//'sat_'//trim(NameSat_I(iSatIn))// &
           '_n',iStartIter, '.sat'

      ! Open file in appropriate mode.  Write header if necessary.
      inquire(file=NameSatFile, exist=IsExist)

      if ( (.not.IsExist) .or. IsFirstWrite ) then
         call open_file(FILE=trim(NameSatFile))

         ! Write header
         write(LUN, '(2a)')'RCM results for SWMF trajectory file ', &
              trim(NameSat_I(iSatIn))
         write(LUN,'(a40,i3.3)')'Number of header variables:', nHeadVar + 2
         write(LUN,*)'iter simTime X Y Z lat lon status interLat interLon Xmin Ymin Vm'
         write(LUN,*) 'Number of distribution variables:', nDistVar+2
         write(LUN,*) 'Number of energy channels:', kcsize
         write(LUN,*) 'k species alamc eeta energy[eV] density[cm^-3]'


      else
         call open_file(FILE=trim(NameSatFile), STATUS='OLD', POSITION='append')
      end if

      ! Collect variables.
      call set_satvar(HeadVar_I, DistVar_II, iSatIn, nHeadVar, nDistVar)

      ! Calculate current simulation time.
      call Write_Label(iCurrentTime)
      write(StringTime,'(I2.2,A1,I2.2,A1,I2.2)') &
           label%intg(3), ':', label%intg(4), ':', label%intg(5)

      write(LUN,'(i6.6,1x,a8,20es13.5)')                             &
           int(iCurrentTime/idt),StringTime,HeadVar_I

      do k=1, kcsize
         write(LUN, '(i4.4,1x,a3,20es13.5)') &
              k, species_char(ikflavc(k)), DistVar_II(k,:)
      end do

    end subroutine write_sat_file
    !=========================================================================
    subroutine Save_Restart

      !Fill labels
      call Write_Label(iCurrentTime)

      !
      write (time_char,'(I2.2,A1,I2.2,A1,I2.2)') &
           label%intg(3), ':', label%intg(4), ':', label%intg(5)
      call IM_write_prefix
      write (iUnitOut,'(A23,I5.5,A13)') &
           '   Saving Restart at T=',iCurrentTime,'s ('//time_char//') '

      ! Open and write text file
      call open_file(FILE=trim(NameRestartOutDir)//"RCMrestart.txt")
      write(LUN,*) label
      call close_file

      ! Open and write binary file
      call open_file(FILE=trim(NameRestartOutDir)//"RCMrestart.rst", &
           FORM='unformatted')
      write(LUN) eeta
      call close_file

    end subroutine Save_Restart
    !
    !
    SUBROUTINE Clean_up_edges ()
      IMPLICIT NONE
      INTEGER (iprec) :: k
      !
      !        Check if pts need to be deleted or added:
      !
      DO  k = 1, ksize
         !
         CALL Farmers_wife (k)
         !
         CALL Zap_edge (k)
         !
         CALL Expand_edge (k)
         !
!!! sts     CALL set_itrack (jdim, kdim, nptmax, bi, bj, itrack, mpoint, &
!!!                          npoint,ain)
         !
      END DO

    end subroutine Clean_up_edges
    
  end subroutine RCM_advec
  !============================================================================
  subroutine set_satvar(headvar_I, distvar_II, iSatIn, nHeadVar, nDistVar)
    ! Collects and prepares all variables to be printed to sat files.
    ! !!!DTW 2007
    !use ModInterpolate
    use ModNumConst,   ONLY: cRadToDeg

    ! Name of subroutine:
    character(len=*), parameter :: NameSub = 'Set_SatVar'

    ! Arguments:
    integer, intent(in) :: nHeadVar, nDistVar, iSatIn
    real, intent(out)   :: HeadVar_I(nHeadVar), DistVar_II(kcsize,nDistVar)

    ! Internal Vars:
    integer            :: iLoc, jLoc, IntTemp(1), k
    real(rprec)               :: xnorm, ynorm, diff_colat(isize), diff_aloct(jsize)
    real(rprec)               :: wrapped_colat(0:isize+1), wrapped_aloct(0:jsize+1)
    character(len=100) :: StringTime
    real(rprec)               :: Volume
    !-------------------------------------------------------------------------
    HeadVar_I = -1.0
    DistVar_II= -1.0

    wrapped_colat(:) = colat(0:isize+1,1)
    wrapped_colat(0) = 2.*wrapped_colat(1)-wrapped_colat(2)
    wrapped_colat(isize+1) = 2.*wrapped_colat(isize)-wrapped_colat(isize-1)
    wrapped_aloct(:) = aloct(1,0:jsize+1)
    wrapped_aloct(0) = 2.*wrapped_aloct(1)-wrapped_aloct(2)
    wrapped_aloct(jsize+1) = 2.*wrapped_aloct(jsize)-wrapped_aloct(jsize-1)

    ! Get satellite location in generalized coordinates.
    if (SatLoc_3I(3,2,iSatIn) == 3) then
       diff_colat = colat(1:isize,1) - SatLoc_3I(1,2,iSatIn)
       diff_aloct = aloct(1,1:jsize) - SatLoc_3I(2,2,iSatIn)
       IntTemp = minloc(abs(diff_colat)); iLoc = IntTemp(1)
       IntTemp = minloc(abs(diff_aloct)); jLoc = IntTemp(1)
       if(diff_colat(iLoc) > 0) iLoc = iLoc - 1
       if(diff_aloct(jLoc) > 0) jLoc = jLoc - 1
       ! If satellite is out of bounds, mark it as such.
       !DDZ-old if statement     if( (diff_colat(1)>0) .or. (diff_colat(isize)<0) ) then
       if(iLoc<0 .or. iLoc>isize .or. jLoc<0 .or. jLoc>jsize)then
          SatLoc_3I(3,2,iSatIn) = -1
          iLoc = 1
       end if
    else 
       iLoc = 1
       jLoc = 1
    end if

    xnorm = (SatLoc_3I(1,2,iSatIn) - wrapped_colat(iLoc)) &
         /  (wrapped_colat(iLoc+1) - wrapped_colat(iLoc)) + 1.0
    ynorm = (SatLoc_3I(2,2,iSatIn) - wrapped_aloct(jLoc)) &
         /  (wrapped_aloct(jLoc+1) - wrapped_aloct(jLoc)) + 1.0

    ! Set variables.

    ! Position
    HeadVar_I(1:3) = SatLoc_3I(1:3,1,iSatIn)
    HeadVar_I(4)   = 90.0 - cRadToDeg * SatLoc_3I(1,2,iSatIn)
    HeadVar_I(5)   =        cRadToDeg * SatLoc_3I(2,2,iSatIn)
    HeadVar_I(6)   = SatLoc_3I(3,2,iSatIn)

    ! If sat resides on CLOSED field line, get those variables!
    if (SatLoc_3I(3,2,iSatIn) == 3) then 

       ! If sat has illegal norm variables, write error to screen and skip rest of routine
       if(xnorm<1. .or. xnorm>2. .or. ynorm<1. .or. ynorm>2.)then
          write(*,*)'RCM_advec: set_satvar: iSatIn=',iSatIn,' NORM ERROR...'
          !         write(*,*)'xnorm,ynorm=',xnorm,ynorm,'  iLoc,jLoc=',iLoc,jLoc
          !         write(*,*)'isize,jsize=',isize,jsize
          !         write(*,*)'SatLoc_3I=',SatLoc_3I(:,:,iSatIn)
          !         write(*,*)'SatLoc_3I(1,2,iSatIn)=',SatLoc_3I(1,2,iSatIn)
          !         write(*,*)'  colat=',colat(:,1)
          !         write(*,*)'SatLoc_3I(2,2,iSatIn)=',SatLoc_3I(2,2,iSatIn)
          !         write(*,*)'  aloct=',aloct(1,:)
          RETURN
       end if

       ! Interpolated position (for debugging/validation)
       HeadVar_I(7) = 90.0 - IM_bilinear(colat(iLoc:iLoc+1,jLoc:jLoc+1), &
            1,2,1,2,(/xnorm,ynorm/)) * cRadToDeg
       HeadVar_I(8) = IM_bilinear(aloct(iLoc:iLoc+1,jLoc:jLoc+1), &
            1,2,1,2,(/xnorm,ynorm/)) * cRadToDeg

       ! Flux tube equitorial crossing:
       HeadVar_I(9) = IM_bilinear(xmin(iLoc:iLoc+1,jLoc:jLoc+1), &
            1, 2, 1, 2, (/xnorm,ynorm/))
       HeadVar_I(10)= IM_bilinear(ymin(iLoc:iLoc+1,jLoc:jLoc+1), &
            1, 2, 1, 2, (/xnorm,ynorm/))
       ! Flux tube volume:
       Volume = IM_bilinear(vm(iLoc:iLoc+1,jLoc:jLoc+1), &
            1, 2, 1, 2, (/xnorm,ynorm/))

       !if(Volume <= 0.0)then
       !write(*,*)'!!! SatLoc=',SatLoc_3I(1:2,2,iSatIn)
       !write(*,*)'!!! xnorm, ynorm=',xnorm, ynorm
       !write(*,*)'!!! negative Volume =',Volume
       !end if
       Volume = max(Volume, 1e-20)

       HeadVar_I(11) = Volume**(-1.5)
       HeadVar_I(11) = HeadVar_I(11)

       ! Fill DistVar_II
       do k=1, kcsize 
          DistVar_II(k,1) = alamc(k) ! Energy invariant.
          DistVar_II(k,2) = IM_bilinear(eeta(iLoc:iLoc+1,jLoc:jLoc+1, k), &
               1, 2, 1, 2, (/xnorm,ynorm/)) ! Density invariant
          DistVar_II(k,3) = abs(alamc(k)) * Volume ! Kinetic Energy
          DistVar_II(k,4) = DistVar_II(k,2) * Volume**1.5/6.37E21!density
       end do

    endif

  end subroutine set_satvar

  !============================================================================
  real(rprec) function IM_bilinear(A_II, iMin, iMax, jMin, jMax, Xy_D)

    ! Calculate bilinear interpolation of A_II at position Xy_D

    integer, intent(in) :: iMin, iMax, jMin, jMax
    real(rprec), intent(in)    :: A_II(iMin:iMax,jMin:jMax)
    real(rprec), intent(in)    :: Xy_D(2)

    integer :: i1, i2, j1, j2
    real(rprec) :: Dx1, Dx2, Dy1, Dy2
    character (len=*), parameter :: NameSub='IM_bilinear'
    !--------------------------------------------------------------------------
    !Set location assuming point is inside block.
    i1 = floor(Xy_D(1))
    j1 = floor(Xy_D(2))  
    i2 = ceiling(Xy_D(1))
    j2 = ceiling(Xy_D(2))

    !If Xy_D is outside of block, change i,j,k according to DoExtrapolate.
    if(any( Xy_D < (/iMin, jMin/)) .or. any(Xy_D > (/ iMax, jMax /))) then
       write(*,*)NameSub//': Xy_D = ', Xy_D(:)
       write(*,*)NameSub//': iMin, iMax, jMin, jMax = ',iMin,iMax,jMin,jMax
       call CON_stop(NameSub//': normalized coordinates are out of range')
    endif

    !Set interpolation weights
    Dx1= Xy_D(1) - i1;   Dx2 = 1.0 - Dx1
    Dy1= Xy_D(2) - j1;   Dy2 = 1.0 - Dy1

    !Perform interpolation
    IM_bilinear = Dy2*(   Dx2*A_II(i1,j1)   &
         +             Dx1*A_II(i2,j1))  &
         +     Dy1*(   Dx2*A_II(i1,j2)   &
         +             Dx1*A_II(i2,j2))

  end function IM_bilinear
  !============================================================================

  subroutine RCM_compute_plasma_moments ()

    INTEGER (iprec) :: i, j, k, ie, kk
    REAL(rprec) :: co1, co2, co3, co4
    !------------------------------------------------------------------------
    RCM_dens_prg = 0.0
    RCM_dens_cm3 = 0.0
    RCM_temp_eVs = 0.0
    RCM_pres_nPa = 0.0
    RCM_eta_sum  = 0.0
    RCM_pvg_spc  = 0.0


    DO j=1-n_gc,jsize+n_gc; DO i=1-n_gc,isize+n_gc

       IF ( i<imin_j(j) ) CYCLE

       co1 = vm(i,j)**(3./2.)
       co2 = co1/(Re*1.0E+18)
       co3 = vm(i,j)*2./3.
       co4 = co2*1.0E+6*co3*charge_e*1.0E+9
       DO k = 2, kcsize
          kk = ikflavc(k)
          RCM_dens_prg (i,j,kk) = RCM_dens_prg (i,j,kk) + eeta(i,j,k)*co1
          RCM_dens_cm3 (i,j,kk) = RCM_dens_cm3 (i,j,kk) + eeta(i,j,k)*co2
          RCM_temp_eVs (i,j,kk) = RCM_temp_eVs (i,j,kk) + eeta(i,j,k)*ABS(alamc(k))*co3
          RCM_pres_nPa (i,j,kk) = RCM_pres_nPa (i,j,kk) + eeta(i,j,k)*ABS(alamc(k))*co4
          RCM_eta_sum  (i,j,kk) = RCM_eta_sum  (i,j,kk) + eeta(i,j,k)
          RCM_pvg_spc  (i,j,kk) = RCM_pvg_spc  (i,j,kk) + eeta(i,j,k)*ABS(alamc(k))
       END DO

       DO ie = iesize, 1, -1
          IF (RCM_dens_cm3 (i,j,ie)> 1.0E-8) THEN
             RCM_temp_eVs (i,j,ie) = RCM_temp_eVs(i,j,ie) / RCM_eta_sum(i,j,ie)
          ELSE
             RCM_temp_eVs (i,j,ie) = -1.0
          END IF
          RCM_pvg_spc (i,j,ie) = RCM_pvg_spc(i,j,ie)*2./3.*charge_e &
               /(Re*1.0E+12)/1.0E-9 ! convert to [nPa*(R_planet/nT)**(5/3)]
       END DO

    END DO; END DO

  end subroutine RCM_compute_plasma_moments

end module RCM_advection

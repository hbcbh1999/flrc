(* The Intel P to C/Pillar Compiler *)
(* Copyright (C) Intel Corporation, October 2006 *)

(* Compile C/Pillar and Link *)

signature BACK_END = sig

  structure PilCompile : sig
    val pass : (unit, unit) Pass.t
  end

  structure Link : sig
    val pass : (unit, unit) Pass.t
  end

end

structure BackEnd :> BACK_END =
struct

  val passname = "BackEnd"

  val fail = fn (f, m) => Fail.fail (passname, f, m)

   structure Chat = ChatF(type env = Config.t
                          val extract = Utils.Function.id
                          val name = "BackEnd"
                          val indent = 0)
       
   local open OS.Path
   in

   fun rundir config = concat (Config.home config, fromUnixPath "runtime/")
   fun addPath (path, file) = 
       mkCanonical (joinDirFile{dir = path,
                                file = file})
   fun concatPath (path1, path2) = 
       mkCanonical(concat(path1, fromUnixPath path2))

   fun psh (config : Config.t) =
       addPath (concat (Config.home config, fromUnixPath "bin/"), "pillar.sh")

   fun plibdir (config : Config.t) = 
       let
         val pd = case Process.getEnv "PLIB"
                   of SOME d => d
                    | _ => fail ("plibdir", "$PLIB isn't set")
       in pd
       end
         

   fun pliblib (config, lib) = 
       let
         val libd = concatPath (plibdir config, "lib")
       in 
         addPath(libd, lib)
       end

   fun plibexe (config, exe) = 
       let
         val bind = concatPath (plibdir config, "bin")
       in 
         addPath(bind,exe)
       end

   fun plibinc (config, dir) =
       concatPath (concatPath (plibdir config, "include"), dir)


   end

   fun useFutures (config : Config.t) = 
       case Config.parStyle config
        of Config.PNone => false
         | Config.PAuto => true
         | Config.PAll => true
         | Config.PPar => true
   
   val (gcWriteBarriersF, gcWriteBarriers) =
       Config.Feature.mk ("Plsr:gc-write-barriers",
                          "generate GC write barriers for refs")

   val (gcAllBarriersF, gcAllBarriers) =
       Config.Feature.mk ("Plsr:all-barriers",
                          "generate non-optional write barriers")

   val instrumentAllocationSites = MilToPil.instrumentAllocationSites

   val (instrumentAllocationF, instrumentAllocation) =
      Config.Feature.mk ("Plsr:instrument-allocation",
                         "gather allocation statistics")

   val (instrumentVtbAllocationF, instrumentVtbAllocation) =
      Config.Feature.mk ("Plsr:instrument-vtb-alc",
                         "gather allocation statistics per vtable")

   val (vtableChangeF, vtableChange) =
       Config.Feature.mk ("Plsr:change-vtables",
                          "do vtable changing for immutability etc.")


   fun defines (config : Config.t) =
       let
         val ws =
             case Config.targetWordSize config
              of Config.Ws32 => "P_WORD_SIZE=4"
               | Config.Ws64 => "P_WORD_SIZE=8"

         val gc =
             case #style (Config.gc config)
              of Config.GcsNone => []
               | Config.GcsConservative => ["P_USE_CGC"]
               | Config.GcsAccurate =>
                 ["P_USE_AGC",
                  "P_AGC_LOCK_PARAM=" ^
                  (case Config.agc config
                    of Config.AgcGcMf => "0"
                     | Config.AgcTgc  => "1"
                     | Config.AgcCgc  => "1")]
                 @
                 (if Config.agc config = Config.AgcTgc orelse
                     Config.agc config = Config.AgcCgc
                  then ["P_USE_FAST_ALLOC"]
                  else [])
                 @
                 (if gcWriteBarriers config
                  then ["P_USE_GC_WRITE_BARRIERS"]
                  else [])
                 @
                 (if gcAllBarriers config
                  then ["P_ALL_BARRIERS"]
                  else [])

         val pbase = 
             case Config.output config
              of Config.OkPillar => ["P_USE_PILLAR", "WIN32"]
               | Config.OkC      => []

         val debug = 
             if Config.pilDebug config then
               ["GC_DEBUG"]
             else
               ["NDEBUG"]

         val futures = 
             if useFutures config then ["P_USE_PARALLEL_FUTURES"] else []

         val vi = 
             if Config.vi config then ["P_USE_VNI"] else []

         val instr =
             List.concat
             [if instrumentAllocation config
              then ["P_INSTRUMENT_ALLOCATION"]
              else [],
              if instrumentVtbAllocation config orelse
                 instrumentAllocationSites config
              then ["P_INSTRUMENT_VTB_ALC"]
              else []]

         val runtime = 
             List.concat
             [
              if Globals.disableOptimizedRationals config then
                []
              else  
                ["P_USE_TAGGED_RATIONALS"]
             ]
         val vtbChg =
             if vtableChange config then ["P_DO_VTABLE_CHANGE"] else []

         val va = 
             case (Config.va config)
              of Config.ViREF => ["P_USE_VI_REF"]
               | Config.ViSSE => ["P_USE_VI_SSE"]
               | Config.ViLRB => ["P_USE_VI_LRB"]

         val ds = 
             List.concat [runtime, 
                          vi, 
                          [ws], 
                          gc, 
                          futures, 
                          debug, 
                          pbase, 
                          instr, 
                          vtbChg,
                          va]
         val flags = 
             List.map (ds, fn s => "-D" ^ s)
       in flags
       end


   val pillarStack =   2097152  (* Decimal integer in bytes (  0x200000) *)
   val smallStack  =  33554432  (* Decimal integer in bytes ( 0x2000000) *)
   val largeStack  = 536870912  (* Decimal integer in bytes (0x20000000) *) 

   fun stackSize (config : Config.t) = 
       (case (Config.stack config, Config.output config)
         of (SOME i, _) => i
          | (NONE, Config.OkPillar) => pillarStack
          | (NONE, Config.OkC) => 
            if useFutures config then smallStack else largeStack)

   fun stackStr (config : Config.t) = 
       let
         val i = stackSize config
         val s = Int.toString i
       in s
       end

   datatype compiler = CcGCC | CcICC | CcPillar
   datatype linker = LdGCC | LdICC | LdPillar

   fun sourceFile (config, compiler, fname) = fname^".c"

   fun objectFile (config, compiler, fname) = 
       (case compiler 
         of CcGCC  => fname^".o"
          | CcICC  => fname^".obj"
          | CcPillar => fname^".obj")

   fun exeFile (config, compiler, fname) = fname^".exe"

   fun compiler (config, compiler) = 
       (case compiler 
         of CcGCC  => "gcc"
          | CcICC  => "icl"
          | CcPillar => plibexe(config, "pilicl"))

   fun includes (config, compiler) = 
       let
         val mcrt = 
             if useFutures config then
               [plibinc (config, "mcrt")]
             else []

         val files = 
             (case compiler
              of CcGCC => 
                 [plibinc (config, "gc-bdw"), rundir config, plibinc (config, "prt")] @ mcrt
               | CcICC => 
                 [plibinc (config, "gc-bdw"), rundir config, plibinc (config, "prt")] @ mcrt
               | CcPillar => 
                 [rundir config, plibinc (config, "prt"), plibinc (config, "pgc")] @ mcrt)
         val flags = List.map (files, fn s => "-I" ^ s)
       in flags
       end

   structure CcOptions =
   struct
     fun out (config, compiler) = ["-c"]

     fun obj ((config, compiler), fname) = 
         (case compiler 
           of CcGCC  => ["-o"^fname]
            | CcICC  => ["-Fo"^fname]
            | CcPillar => ["-Fo"^fname])

     fun debug (config, compiler) =
         (case compiler
           of CcGCC  => if Config.pilDebug config then ["-g"] else []
            | CcICC  => ["-Zi", "-debug"]
            | CcPillar => ["-Zi", "-debug"])

     fun arch (config, compiler) = 
         (case compiler
           of CcGCC => ["-msse3"] (* without -msse, we should use -ffloat-store in float*)
            | CcICC => ["-QxT"]
            | CcPillar => ["-QxB"])

     fun opt (config, compiler) =
         let
           val level = Config.pilOpt config
           val ps = 
               (case compiler
                 of CcGCC  =>
                    (case level
                      of 0 => ["-O0"]
                       | 1 => ["-O1"]
                       | 2 => ["-O2"]
                       | 3 => ["-O3"]
                       | _ => fail ("gcc", "Bad opt level"))
                  | CcICC  => 
                    (case level
                      of 0 => ["-Od"]
                       | 1 => ["-O1"]
                       | 2 => ["-O2"]
                       | 3 => ["-O3", "-Qip",
                               "-Qvec-report0", "-Qdiag-disable:cpu-dispatch"]
                       | _ => fail ("icc", "Bad opt level"))
                  | CcPillar => 
                    let
                      val opts = 
                          ["-O2", "-Ob0", (* disable inlining*)
                           "-mP2OPT_pre=false", (* disable PRE *)
                           "-mCG_opt_mask=0xfffe"]
                      val () = if level < 2 then
                                 Chat.warn0 (config, 
                                             "Ignoring optimization flag to avoid Pillar bug")
                               else
                                 ()
                      val os = 
                          if level <=3 then
                            opts
                          else
                            fail ("picc", "Bad opt level")
                    in os
                    end
               )
         in ps
         end

     fun float (config, compiler) =
         let
           val sloppy = Config.sloppyFp config
           val os = 
               (case (compiler, sloppy)
                 of (CcGCC, true)  => ["-ffast-math"]
                  (* fpmath only works if -msse{|1|2} is set *)
                  (* without -msse, we should use -ffloat-store*)
                  | (CcGCC, false) => ["-mieee-fp", "-mfpmath=sse"] 
                  (* Pillar doesn't have -Qftz *)
                  | (CcICC, true)  => ["-fp:fast", "-Qftz"]
                  | (CcICC, false) => ["-fp:source", "-Qftz-", "-Qprec-div", "-Qprec-sqrt", "-Qvec-"]
                  | (CcPillar, true)  => ["-fp:fast"]
                  | (CcPillar, false) => ["-fp:source", "-Qprec-div", "-Qprec-sqrt", "-Qvec-"]
               )
         in os
         end

     fun warn (config, compiler) =
         (case compiler
           of CcGCC  => [(*"-Wall"*)]
            | CcICC  => ["-W3", 
                       "-Qwd 177", (* Unused variable *)
                       "-Qwd 279"  (* Controlling expression is constant*)
                      ]
            | CcPillar => ["-W3", "-Qwd 177", "-Qwd 279"]
         )

     fun lang (config, compiler) =
         (case compiler
           of CcGCC  => ["-std=c99"]
            | CcICC  => ["-TC", "-Qc99"]
            | CcPillar => ["-TC", "-Qc99",
                       "-Qtlsregister:ebx",
                       "-Qoffsetvsh:0", 
                       "-Qoffsetusertls:4", 
                       "-Qoffsetstacklimit:16"]
        )

     fun mt (config, compiler) =
         (case compiler
           of CcGCC  => []
            | CcICC  => if useFutures config then ["-MT"] else []
            | CcPillar => ["-MT"])

   end (* structure CcOptions *)

   fun compile (config : Config.t, ccTag, fname) = 
       let
         val inFile = sourceFile (config, ccTag, fname)
         val outFile = objectFile (config, ccTag, fname)
         val cfg = (config, ccTag)
         val cc = compiler cfg
         val options = 
             [
              CcOptions.out cfg,
              CcOptions.debug cfg,
              CcOptions.arch cfg,
              CcOptions.opt cfg,
              CcOptions.float cfg,
              CcOptions.warn cfg,
              CcOptions.lang cfg,
              CcOptions.mt cfg
              ]
         val options = List.concat options
         val defs = defines config
         val incs = includes cfg
         val args = [options, defs, [inFile], incs, CcOptions.obj (cfg, outFile), Config.pilcStr config]
         val args = List.concat args
         val cleanup = fn () => if Config.keepPil config then ()
                                else File.remove inFile
       in (cc, args, cleanup)
       end

   fun linker (config, ld) = 
       (case ld
         of LdGCC  => "gcc"
          | LdICC  => "icl"
          | LdPillar => plibexe(config, "pilink"))

   structure LdOptions =
   struct
     fun exe ((config, ld), fname) = 
         (case ld
           of LdGCC  => ["-o"^fname]
            | LdICC  => ["-Fe"^fname]
            | LdPillar => ["-out:"^fname])

     fun link (config, ld) = 
         (case ld
           of LdGCC  => []
            | LdICC  => ["-link"]
            | LdPillar => []
         )

     fun opt (config, ld) = 
         (case ld
           of LdGCC  => ["-O2"]
            | LdICC  => []
            | LdPillar => []
         )

     fun stack (config, ld) = 
         (case ld
           of LdGCC  => ["--stack="^(stackStr config)]
            | LdICC  => ["-stack:"^(stackStr config)]
            | LdPillar => ["-stack:"^(stackStr config)]
         )

     fun control (config, ld) = 
         (case ld
           of LdGCC  => []
            | LdICC  => ["-nologo", "-INCREMENTAL:NO"]
            | LdPillar => ["-nologo", "-INCREMENTAL:NO"]
         )

     fun debug (config, ld) = 
         (case ld
           of LdGCC  => ["-g"]
            | LdICC  => ["-debug"]
            | LdPillar => ["-debug"]
         )

   end (* structure CcOptions *)

   fun gcLibraries (config, ldTag) = 
       let

         val mt = useFutures config
         val debug = Config.pilDebug config
         val gcs = #style (Config.gc config)
         fun agc (config, debug) =
             (case (Config.agc config, debug)
               of (Config.AgcGcMf, true)  => pliblib (config, "gc-mfd.lib")
                | (Config.AgcTgc, true)   => pliblib (config, "gc-tgcd.lib")
                | (Config.AgcCgc, true)   => pliblib (config, "gc-cgcd.lib")
                | (Config.AgcGcMf, false) => pliblib (config, "gc-mf.lib")
                | (Config.AgcTgc, false)  => pliblib (config, "gc-tgc.lib")
                | (Config.AgcCgc, false)  => pliblib (config, "gc-cgc.lib"))

         val libs =
             (case (gcs, ldTag, mt, debug)
               of (Config.GcsNone, _, _, _) => []

                | (Config.GcsConservative, LdGCC, _, true)       => [pliblib (config, "libgc-bdwd.a")]
                | (Config.GcsConservative, LdGCC, _, false)      => [pliblib (config, "libgc-bdw.a")]
                | (Config.GcsConservative, LdICC, true, true)   => [pliblib (config, "gc-bdw-dlld.lib")]
                | (Config.GcsConservative, LdICC, true, false)  => [pliblib (config, "gc-bdw-dll.lib")]
                | (Config.GcsConservative, LdICC, false, true)  => [pliblib (config, "gc-bdwd.lib")]
                | (Config.GcsConservative, LdICC, false, false) => [pliblib (config, "gc-bdw.lib")]
                | (Config.GcsConservative, LdPillar, _, _)  =>
                  fail ("gcLibraries", "Conservative GC not supported on Pillar")

                | (Config.GcsAccurate, LdPillar, _, _) => 
                  [pliblib (config, "pgcd.lib"), "imagehlp.lib", agc (config, debug)]
                | (Config.GcsAccurate, _, _, _) => 
                  fail ("gcLibraries", "Accurate GC not supported on C"))
       in libs
       end

   fun futureLibraries (config, ldTag) = 
       let
         val mt = useFutures config
         val debug = Config.pilDebug config
         val nm =
             case (mt, debug)
              of (false, false) => "sequential"
               | (false, true ) => "sequentiald"
               | (true,  false) => "parallel"
               | (true,  true ) => "paralleld"
         val file = 
             (case ldTag
               of LdGCC => "ptkfutures_gcc_" ^ nm ^ ".lib"
                | LdICC => "ptkfutures_" ^ nm ^ ".lib"
                | LdPillar => "ptkfutures_pillar_" ^ nm ^ ".obj")

       in
         [pliblib (config, file)]
       end

   fun runtimeLibraries (config, ldTag) = 
       let
         val debug = Config.pilDebug config
         val mt = useFutures config
         val libs = 
             (case (ldTag, debug)
               of (LdPillar, true)  => [pliblib (config, "pillard.lib")]
                | (LdPillar, false) => [pliblib (config, "pillar.lib")] 
                | (LdICC, _) => ["user32.lib"] 
                | _ => [])
         val mcrt = 
             if ((ldTag = LdPillar) orelse mt) then
               if debug then
                 [pliblib (config, "mcrtd.lib")]
               else  
                 [pliblib (config, "mcrt.lib")]
             else
               []
       in mcrt @ libs
       end

   fun libraries (config, ldTag) = 
       let
         val mt = useFutures config
         val debug = Config.pilDebug config

         val (prtBegin, prtEnd) = 
             (case (ldTag, debug)
               of (LdPillar, true)  => ([pliblib (config, "crt_prtbegind.obj")], [pliblib (config, "crt_prtendd.obj")])
                | (LdPillar, false) => ([pliblib (config, "crt_prtbegin.obj")], [pliblib (config, "crt_prtend.obj")])
                | _ => ([], []))

         val gcLibs = gcLibraries (config, ldTag)
         val futureLibs = futureLibraries (config, ldTag)
         val runtimeLibs = runtimeLibraries (config, ldTag)
         val pre = prtBegin
         val post = 
             List.concat [futureLibs, prtEnd, gcLibs, runtimeLibs]
       in (pre, post)
       end

   fun link (config, ccTag, ldTag, fname) = 
       let
         val inFile = objectFile (config, ccTag, fname)
         val outFile = exeFile (config, ldTag, fname)
         val cfg = (config, ldTag)
         val ld = linker cfg
         val options = List.concat [LdOptions.link cfg,
                                    LdOptions.opt cfg, 
                                    LdOptions.stack cfg,
                                    LdOptions.control cfg,
                                    LdOptions.debug cfg]
         val (preLibs, postLibs) = libraries (config, ldTag)
         val args = List.concat [LdOptions.exe (cfg, outFile), 
                                 preLibs,
                                 [inFile],
                                 postLibs,
                                 options, 
                                 Config.linkStr config]
         val cleanup = fn () => if Config.keepObj config then ()
                                else File.remove inFile
       in (ld, args, cleanup)
       end

   fun icc (config, fname)  = compile (config, CcICC, fname)
   fun gcc (config, fname)  = compile (config, CcGCC, fname)
   fun picc (config, fname) = compile (config, CcPillar, fname)

   fun ilink(config : Config.t, fname) = link (config, CcICC, LdICC, fname)
   fun ld(config : Config.t, fname)    = link (config, CcGCC, LdGCC, fname)
   fun plink(config : Config.t, fname) = link (config, CcPillar, LdPillar, fname)

   fun compile (config : Config.t, fname) =
       let 
         val (c, args, cleanup) =
             case Config.output config
              of Config.OkC => 
                 (case Config.toolset config
                   of Config.Intel => icc (config, fname)
                    | Config.Gnu   => gcc (config, fname))
               | Config.OkPillar   => picc(config, fname)
         val () = 
             Exn.finally (fn () => Pass.run (config, Chat.log0, c, args),
                          cleanup)
       in ()
       end
       
   fun link (config : Config.t, fname) =
       let 
         val (c, args, cleanup) =
             case Config.output config 
              of Config.OkC => 
                 (case Config.toolset config
                   of Config.Intel => ilink (config, fname)
                    | Config.Gnu   => ld    (config, fname))
               | Config.OkPillar   => plink (config, fname)
         val () = 
             Exn.finally (fn () => Pass.run (config, Chat.log0, c, args),
                          cleanup)
       in 
         ()
       end

   structure PilCompile =
   struct
     val description = {name        = "PilCompile",
                        description = "Compile Pil",
                        inIr        = Pass.unitHelpers,
                        outIr       = Pass.unitHelpers,
                        mustBeAfter = [],
                        stats       = []}
     val associates = {controls = [],
                       debugs = [],
                       features = [gcWriteBarriersF, 
                                   gcAllBarriersF,
                                   instrumentAllocationF,
                                   instrumentVtbAllocationF,
                                   vtableChangeF],
                       subPasses = []}
     fun pilCompile ((), pd, basename) =
         compile (PassData.getConfig pd, basename)
     val pass = Pass.mkFilePass (description, associates, pilCompile)
   end

   structure Link =
   struct
     val description = {name        = "Link",
                        description = "Link the executable",
                        inIr        = Pass.unitHelpers,
                        outIr       = Pass.unitHelpers,
                        mustBeAfter = [],
                        stats       = []}
     val associates = {controls = [],
                       debugs = [],
                       features = [],
                       subPasses = []}
     fun link' ((), pd, basename) = link (PassData.getConfig pd, basename)
     val pass = Pass.mkFilePass (description, associates, link')
   end

end;
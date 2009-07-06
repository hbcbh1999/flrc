(* The Intel P to C/Pillar Compiler *)
(* Copyright (C) Intel Corporation, September 2007 *)

(* Utilities for Comparison Functions *)

signature COMPARE =
sig
  type 'a t = 'a * 'a -> order
  val option  : 'a t -> 'a option t
  val vector  : 'a t -> 'a Vector.t t
  val pair    : 'a t * 'b t -> ('a * 'b) t
  val riap    : 'a t * 'b t -> ('a * 'b) t   (* Reverse lexicographic *)
  val triple  : 'a t * 'b t * 'c t -> ('a * 'b * 'c) t
  val quad    : 'a t * 'b t * 'c t * 'd t -> ('a * 'b * 'c * 'd) t
  val quint   : 'a t * 'b t * 'c t * 'd t * 'e t -> ('a * 'b * 'c * 'd * 'e) t
  val hexa    : 'a t * 'b t * 'c t * 'd t * 'e t *'f t
                -> ('a * 'b * 'c * 'd * 'e * 'f) t
  val hepta   : 'a t * 'b t * 'c t * 'd t * 'e t *'f t * 'g t
                -> ('a * 'b * 'c * 'd * 'e * 'f * 'g) t
  val octa    : 'a t * 'b t * 'c t * 'd t * 'e t *'f t * 'g t * 'h t
                -> ('a * 'b * 'c * 'd * 'e * 'f * 'g * 'h) t
  val rec1    : ('a -> 'b) * 'b t -> 'a t
  val rec2    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t -> 'a t
  val rec3    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t * ('a -> 'd) * 'd t
                -> 'a t
  val rec4    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t * ('a -> 'd) * 'd t
                * ('a -> 'e) * 'e t
                -> 'a t
  val rec5    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t * ('a -> 'd) * 'd t
                * ('a -> 'e) * 'e t * ('a -> 'f) * 'f t
                -> 'a t
  val rec6    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t * ('a -> 'd) * 'd t
                * ('a -> 'e) * 'e t * ('a -> 'f) * 'f t * ('a -> 'g) * 'g t
                -> 'a t
  val rec7    : ('a -> 'b) * 'b t * ('a -> 'c) * 'c t * ('a -> 'd) * 'd t
                * ('a -> 'e) * 'e t * ('a -> 'f) * 'f t * ('a -> 'g) * 'g t
                * ('a -> 'h) * 'h t
                -> 'a t
  val fromOrd : ('a -> int) -> 'a t

  val equal : 'a t -> ('a * 'a) -> bool
end;

structure Compare :> COMPARE =
struct

  type 'a t = 'a * 'a -> order

  fun option cmp (o1, o2) =
      case (o1,o2) 
       of (SOME a, SOME b) => cmp (a,b)
        | (SOME a, NONE  ) => GREATER
        | (NONE,   SOME b) => LESS
        | (NONE,   NONE  ) => EQUAL
                          
  fun vector cmp (v1, v2) = Vector.compare (v1, v2, cmp)

  fun pair (cmp1, cmp2) ((a1, a2), (b1, b2)) = 
      case cmp1 (a1, b1)
       of EQUAL => cmp2 (a2, b2)
        | ord => ord

  fun riap (cmp1, cmp2) ((a1, a2), (b1, b2)) = 
      case cmp2 (a2, b2)
       of EQUAL => cmp1 (a1, b1)
        | ord => ord

  fun triple (cmp1, cmp2, cmp3) ((a1, a2, a3), (b1, b2, b3)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => cmp3 (a3, b3)
             | ord => ord)
        | ord => ord

  fun quad (cmp1, cmp2, cmp3, cmp4) ((a1, a2, a3, a4), (b1, b2, b3, b4)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => 
               (case cmp3 (a3, b3)
                 of EQUAL => cmp4 (a4, b4)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun quint (cmp1, cmp2, cmp3, cmp4, cmp5)
            ((a1, a2, a3, a4, a5), (b1, b2, b3, b4, b5)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => 
               (case cmp3 (a3, b3)
                 of EQUAL => 
                    (case cmp4 (a4, b4)
                      of EQUAL => cmp5 (a5, b5)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun hexa (cmp1, cmp2, cmp3, cmp4, cmp5, cmp6)
           ((a1, a2, a3, a4, a5, a6), (b1, b2, b3, b4, b5, b6)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => 
               (case cmp3 (a3, b3)
                 of EQUAL => 
                    (case cmp4 (a4, b4)
                      of EQUAL => 
                         (case cmp5 (a5, b5)
                           of EQUAL => cmp6 (a6, b6)
                            | ord => ord)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun hepta (cmp1, cmp2, cmp3, cmp4, cmp5,cmp6, cmp7)
            ((a1, a2, a3, a4, a5, a6, a7), (b1, b2, b3, b4, b5, b6, b7)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => 
               (case cmp3 (a3, b3)
                 of EQUAL => 
                    (case cmp4 (a4, b4)
                      of EQUAL => 
                         (case cmp5 (a5, b5)
                           of EQUAL => 
                              (case cmp6 (a6, b6)
                                of EQUAL => cmp7 (a7, b7)
                                 | ord => ord)
                            | ord => ord)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun octa (cmp1, cmp2, cmp3, cmp4, cmp5,cmp6, cmp7, cmp8)
            ((a1, a2, a3, a4, a5, a6, a7, a8), 
             (b1, b2, b3, b4, b5, b6, b7, b8)) = 
      case cmp1 (a1, b1)
       of EQUAL => 
          (case cmp2 (a2, b2)
            of EQUAL => 
               (case cmp3 (a3, b3)
                 of EQUAL => 
                    (case cmp4 (a4, b4)
                      of EQUAL => 
                         (case cmp5 (a5, b5)
                           of EQUAL => 
                              (case cmp6 (a6, b6)
                                of EQUAL => 
                                   (case cmp7 (a7, b7)
                                     of EQUAL => cmp8 (a8, a8)
                                      | ord => ord)
                                 | ord => ord)
                            | ord => ord)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun rec1 (p1, c1) (x1, x2) = c1 (p1 x1, p1 x2)

  fun rec2 (p1, c1, p2, c2) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL => c2 (p2 x1, p2 x2)
        | ord => ord

  fun rec3 (p1, c1, p2, c2, p3, c3) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL =>
          (case c2 (p2 x1, p2 x2)
            of EQUAL => c3 (p3 x1, p3 x2)
             | ord => ord)
        | ord => ord

  fun rec4 (p1, c1, p2, c2, p3, c3, p4, c4) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL =>
          (case c2 (p2 x1, p2 x2)
            of EQUAL =>
               (case c3 (p3 x1, p3 x2)
                 of EQUAL => c4 (p4 x1, p4 x2)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun rec5 (p1, c1, p2, c2, p3, c3, p4, c4, p5, c5) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL =>
          (case c2 (p2 x1, p2 x2)
            of EQUAL =>
               (case c3 (p3 x1, p3 x2)
                 of EQUAL => 
                    (case c4 (p4 x1, p4 x2)
                      of EQUAL => c5 (p5 x1, p5 x2)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun rec6 (p1, c1, p2, c2, p3, c3, p4, c4, p5, c5, p6, c6) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL =>
          (case c2 (p2 x1, p2 x2)
            of EQUAL =>
               (case c3 (p3 x1, p3 x2)
                 of EQUAL => 
                    (case c4 (p4 x1, p4 x2)
                      of EQUAL =>
                         (case c5 (p5 x1, p5 x2)
                           of EQUAL => c6 (p6 x1, p6 x2)
                            | ord => ord)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun rec7 (p1, c1, p2, c2, p3, c3, p4, c4, p5, c5, p6, c6, p7, c7) (x1, x2) =
      case c1 (p1 x1, p1 x2)
       of EQUAL =>
          (case c2 (p2 x1, p2 x2)
            of EQUAL =>
               (case c3 (p3 x1, p3 x2)
                 of EQUAL => 
                    (case c4 (p4 x1, p4 x2)
                      of EQUAL =>
                         (case c5 (p5 x1, p5 x2)
                           of EQUAL =>
                              (case c6 (p6 x1, p6 x2)
                                of EQUAL => c7 (p7 x1, p7 x2)
                                 | ord => ord)
                            | ord => ord)
                       | ord => ord)
                  | ord => ord)
             | ord => ord)
        | ord => ord

  fun fromOrd ord (x1, x2) = Int.compare (ord x1, ord x2)

  val equal = 
   fn cmp =>
   fn x => (cmp x) = EQUAL

end;
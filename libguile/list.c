/*	Copyright (C) 1995,1996,1997 Free Software Foundation, Inc.
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA
 *
 * As a special exception, the Free Software Foundation gives permission
 * for additional uses of the text contained in its release of GUILE.
 *
 * The exception is that, if you link the GUILE library with other files
 * to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the GUILE library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the
 * Free Software Foundation under the name GUILE.  If you copy
 * code from other Free Software Foundation releases into a copy of
 * GUILE, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for GUILE, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.  */

/* Software engineering face-lift by Greg J. Badros, 11-Dec-1999,
   gjb@cs.washington.edu, http://www.cs.washington.edu/homes/gjb */


#include <stdio.h>
#include "_scm.h"
#include "eq.h"

#include "scm_validate.h"
#include "list.h"

#ifdef __STDC__
#include <stdarg.h>
#define var_start(x, y) va_start(x, y)
#else
#include <varargs.h>
#define var_start(x, y) va_start(x)
#endif


/* creating lists */

/* SCM_P won't help us deal with varargs here.  */
#ifdef __STDC__
SCM
scm_listify (SCM elt, ...)
#else
SCM
scm_listify (elt, va_alist)
     SCM elt;
     va_dcl
#endif
{
  va_list foo;
  SCM answer;
  SCM *pos;

  var_start (foo, elt);
  answer = SCM_EOL;
  pos = &answer;
  while (elt != SCM_UNDEFINED)
    {
      *pos = scm_cons (elt, SCM_EOL);
      pos = SCM_CDRLOC (*pos);
      elt = va_arg (foo, SCM);
    }
  return answer;
}


GUILE_PROC(scm_list, "list", 0, 0, 1, 
           (SCM objs),
"")
#define FUNC_NAME s_scm_list
{
  return objs;
}
#undef FUNC_NAME


GUILE_PROC (scm_list_star, "list*", 1, 0, 1, 
            (SCM arg, SCM rest),
"")
#define FUNC_NAME s_scm_list_star
{
  if (SCM_NIMP (rest))
    {
      SCM prev = arg = scm_cons (arg, rest);
      while (SCM_NIMP (SCM_CDR (rest)))
	{
	  prev = rest;
	  rest = SCM_CDR (rest);
	}
      SCM_SETCDR (prev, SCM_CAR (rest));
    }
  return arg;
}
#undef FUNC_NAME



/* general questions about lists --- null?, list?, length, etc.  */

GUILE_PROC(scm_null_p, "null?", 1, 0, 0, 
           (SCM x),
"")
#define FUNC_NAME s_scm_null_p
{
  return SCM_BOOL(SCM_NULLP(x));
}
#undef FUNC_NAME

GUILE_PROC(scm_list_p, "list?", 1, 0, 0, 
           (SCM x),
"")
#define FUNC_NAME s_scm_list_p
{
  return SCM_BOOL(scm_ilength(x)>=0);
}
#undef FUNC_NAME


/* Return the length of SX, or -1 if it's not a proper list.
   This uses the "tortoise and hare" algorithm to detect "infinitely
   long" lists (i.e. lists with cycles in their cdrs), and returns -1
   if it does find one.  */
long
scm_ilength(SCM sx)
{
  register long i = 0;
  register SCM tortoise = sx;
  register SCM hare = sx;

  do {
    if (SCM_IMP(hare)) return SCM_NULLP(hare) ? i : -1;
    if (SCM_NCONSP(hare)) return -1;
    hare = SCM_CDR(hare);
    i++;
    if (SCM_IMP(hare)) return SCM_NULLP(hare) ? i : -1;
    if (SCM_NCONSP(hare)) return -1;
    hare = SCM_CDR(hare);
    i++;
    /* For every two steps the hare takes, the tortoise takes one.  */
    tortoise = SCM_CDR(tortoise);
  }
  while (hare != tortoise);

  /* If the tortoise ever catches the hare, then the list must contain
     a cycle.  */
  return -1;
}

GUILE_PROC(scm_length, "length", 1, 0, 0, 
           (SCM lst),
"")
#define FUNC_NAME s_scm_length
{
  int i;
  SCM_VALIDATE_LIST_COPYLEN(1,lst,i);
  return SCM_MAKINUM (i);
}
#undef FUNC_NAME



/* appending lists */

GUILE_PROC (scm_append, "append", 0, 0, 1, 
            (SCM args),
"")
#define FUNC_NAME s_scm_append
{
  SCM res = SCM_EOL;
  SCM *lloc = &res, arg;
  if (SCM_IMP(args)) {
    SCM_VALIDATE_NULL(SCM_ARGn, args);
    return res;
  }
  SCM_VALIDATE_CONS(SCM_ARGn, args);
  while (1) {
    arg = SCM_CAR(args);
    args = SCM_CDR(args);
    if (SCM_IMP(args)) {
      *lloc = arg;
      SCM_VALIDATE_NULL(SCM_ARGn, args);
      return res;
    }
    SCM_VALIDATE_CONS(SCM_ARGn, args);
    for(;SCM_NIMP(arg);arg = SCM_CDR(arg)) {
      SCM_VALIDATE_CONS(SCM_ARGn, arg);
      *lloc = scm_cons(SCM_CAR(arg), SCM_EOL);
      lloc = SCM_CDRLOC(*lloc);
    }
    SCM_VALIDATE_NULL(SCM_ARGn, arg);
  }
}
#undef FUNC_NAME


GUILE_PROC (scm_append_x, "append!", 0, 0, 1, 
            (SCM args),
"")
#define FUNC_NAME s_scm_append_x
{
  SCM arg;
 tail:
  if (SCM_NULLP(args)) return SCM_EOL;
  arg = SCM_CAR(args);
  args = SCM_CDR(args);
  if (SCM_NULLP(args)) return arg;
  if (SCM_NULLP(arg)) goto tail;
  SCM_VALIDATE_NIMCONS(SCM_ARG1,arg);
  SCM_SETCDR (scm_last_pair (arg), scm_append_x (args));
  return arg;
}
#undef FUNC_NAME


GUILE_PROC(scm_last_pair, "last-pair", 1, 0, 0, 
           (SCM sx),
"")
#define FUNC_NAME s_scm_last_pair
{
  register SCM res = sx;
  register SCM x;

  if (SCM_NULLP (sx))
    return SCM_EOL;

  SCM_VALIDATE_NIMCONS(SCM_ARG1,res);
  while (!0) {
    x = SCM_CDR(res);
    if (SCM_IMP(x) || SCM_NCONSP(x)) return res;
    res = x;
    x = SCM_CDR(res);
    if (SCM_IMP(x) || SCM_NCONSP(x)) return res;
    res = x;
    sx = SCM_CDR(sx);
    SCM_ASSERT(x != sx, sx, SCM_ARG1, FUNC_NAME);
  }
}
#undef FUNC_NAME


/* reversing lists */

GUILE_PROC (scm_reverse, "reverse", 1, 0, 0,
            (SCM ls),
"")
#define FUNC_NAME s_scm_reverse
{
  SCM res = SCM_EOL;
  SCM p = ls, t = ls;
  while (SCM_NIMP (p))
    {
      SCM_VALIDATE_CONS(1,ls);
      res = scm_cons (SCM_CAR (p), res);
      p = SCM_CDR (p);
      if (SCM_IMP (p))
	break;
      SCM_VALIDATE_CONS(1,ls);
      res = scm_cons (SCM_CAR (p), res);
      p = SCM_CDR (p);
      t = SCM_CDR (t);
      if (t == p)
	scm_misc_error (FUNC_NAME, "Circular structure: %S", SCM_LIST1 (ls));
    }
  ls = p;
  SCM_VALIDATE_NULL(1,ls);
  return res;
}
#undef FUNC_NAME

GUILE_PROC (scm_reverse_x, "reverse!", 1, 1, 0,
            (SCM ls, SCM new_tail),
"")
#define FUNC_NAME s_scm_reverse_x
{
  SCM old_tail;
  SCM_ASSERT (scm_ilength (ls) >= 0, ls, SCM_ARG1, FUNC_NAME);
  if (SCM_UNBNDP (new_tail))
    new_tail = SCM_EOL;
  else
    SCM_ASSERT (scm_ilength (new_tail) >= 0, new_tail, SCM_ARG2, FUNC_NAME);

  while (SCM_NIMP (ls))
    {
      old_tail = SCM_CDR (ls);
      SCM_SETCDR (ls, new_tail);
      new_tail = ls;
      ls = old_tail;
    }
  return new_tail;
}
#undef FUNC_NAME



/* indexing lists by element number */

GUILE_PROC(scm_list_ref, "list-ref", 2, 0, 0,
           (SCM lst, SCM k),
"")
#define FUNC_NAME s_scm_list_ref
{
  register long i;
  SCM_VALIDATE_INT_MIN_COPY(2,k,0,i);
  while (i-- > 0) {
    SCM_ASRTGO(SCM_NIMP(lst) && SCM_CONSP(lst), erout);
    lst = SCM_CDR(lst);
  }
 erout:	
  SCM_ASSERT(SCM_NIMP(lst) && SCM_CONSP(lst),
             SCM_NULLP(lst)?k:lst, SCM_NULLP(lst)?SCM_OUTOFRANGE:SCM_ARG1, FUNC_NAME);
  return SCM_CAR(lst);
}
#undef FUNC_NAME

GUILE_PROC(scm_list_set_x, "list-set!", 3, 0, 0,
           (SCM lst, SCM k, SCM val),
"")
#define FUNC_NAME s_scm_list_set_x
{
  register long i;
  SCM_VALIDATE_INT_MIN_COPY(2,k,0,i);
  while (i-- > 0) {
    SCM_ASRTGO(SCM_NIMP(lst) && SCM_CONSP(lst), erout);
    lst = SCM_CDR(lst);
  }
 erout:	
  SCM_ASSERT(SCM_NIMP(lst) && SCM_CONSP(lst),
             SCM_NULLP(lst)?k:lst, SCM_NULLP(lst)?SCM_OUTOFRANGE:SCM_ARG1, FUNC_NAME);
  SCM_SETCAR (lst, val);
  return val;
}
#undef FUNC_NAME


SCM_REGISTER_PROC(s_list_cdr_ref, "list-cdr-ref", 2, 0, 0, scm_list_tail);

GUILE_PROC(scm_list_tail, "list-tail", 2, 0, 0,
           (SCM lst, SCM k),
"")
#define FUNC_NAME s_scm_list_tail
{
  register long i;
  SCM_VALIDATE_INT_MIN_COPY(2,k,0,i);
  while (i-- > 0) {
    SCM_VALIDATE_NIMCONS(1,lst);
    lst = SCM_CDR(lst);
  }
  return lst;
}
#undef FUNC_NAME


GUILE_PROC(scm_list_cdr_set_x, "list-cdr-set!", 3, 0, 0,
           (SCM lst, SCM k, SCM val),
"")
#define FUNC_NAME s_scm_list_cdr_set_x
{
  register long i;
  SCM_VALIDATE_INT_MIN_COPY(2,k,0,i);
  while (i-- > 0) {
    SCM_ASRTGO(SCM_NIMP(lst) && SCM_CONSP(lst), erout);
    lst = SCM_CDR(lst);
  }
erout:
  SCM_ASSERT(SCM_NIMP(lst) && SCM_CONSP(lst),
             SCM_NULLP(lst)?k:lst, SCM_NULLP(lst)?SCM_OUTOFRANGE:SCM_ARG1, FUNC_NAME);
  SCM_SETCDR (lst, val);
  return val;
}
#undef FUNC_NAME



/* copying lists, perhaps partially */

GUILE_PROC(scm_list_head, "list-head", 2, 0, 0,
           (SCM lst, SCM k),
"")
#define FUNC_NAME s_scm_list_head
{
  SCM answer;
  SCM * pos;
  register long i;

  SCM_VALIDATE_INT_MIN_COPY(2,k,0,i);
  answer = SCM_EOL;
  pos = &answer;
  while (i-- > 0)
    {
      SCM_VALIDATE_NIMCONS(1,lst);
      *pos = scm_cons (SCM_CAR (lst), SCM_EOL);
      pos = SCM_CDRLOC (*pos);
      lst = SCM_CDR(lst);
    }
  return answer;
}
#undef FUNC_NAME


GUILE_PROC (scm_list_copy, "list-copy", 1, 0, 0, 
            (SCM lst),
"")
#define FUNC_NAME s_scm_list_copy
{
  SCM newlst;
  SCM * fill_here;
  SCM from_here;

  newlst = SCM_EOL;
  fill_here = &newlst;
  from_here = lst;

  while (SCM_NIMP (from_here) && SCM_CONSP (from_here))
    {
      SCM c;
      c = scm_cons (SCM_CAR (from_here), SCM_CDR (from_here));
      *fill_here = c;
      fill_here = SCM_CDRLOC (c);
      from_here = SCM_CDR (from_here);
    }
  return newlst;
}
#undef FUNC_NAME


/* membership tests (memq, memv, etc.) */ 

GUILE_PROC (scm_sloppy_memq, "sloppy-memq", 2, 0, 0,
            (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_sloppy_memq
{
  for(;  SCM_NIMP(lst) && SCM_CONSP (lst);  lst = SCM_CDR(lst))
    {
      if (SCM_CAR(lst)==x)
	return lst;
    }
  return lst;
}
#undef FUNC_NAME


GUILE_PROC (scm_sloppy_memv, "sloppy-memv", 2, 0, 0,
            (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_sloppy_memv
{
  for(;  SCM_NIMP(lst) && SCM_CONSP (lst);  lst = SCM_CDR(lst))
    {
      if (SCM_BOOL_F != scm_eqv_p (SCM_CAR(lst), x))
	return lst;
    }
  return lst;
}
#undef FUNC_NAME


GUILE_PROC (scm_sloppy_member, "sloppy-member", 2, 0, 0,
            (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_sloppy_member
{
  for(;  SCM_NIMP(lst) && SCM_CONSP (lst);  lst = SCM_CDR(lst))
    {
      if (SCM_BOOL_F != scm_equal_p (SCM_CAR(lst), x))
	return lst;
    }
  return lst;
}
#undef FUNC_NAME



GUILE_PROC(scm_memq, "memq", 2, 0, 0,
           (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_memq
{
  SCM answer;
  SCM_VALIDATE_LIST(2,lst);
  answer = scm_sloppy_memq (x, lst);
  return (answer == SCM_EOL) ? SCM_BOOL_F : answer;
}
#undef FUNC_NAME



GUILE_PROC(scm_memv, "memv", 2, 0, 0,
           (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_memv
{
  SCM answer;
  SCM_VALIDATE_LIST(2,lst);
  answer = scm_sloppy_memv (x, lst);
  return (answer == SCM_EOL) ? SCM_BOOL_F : answer;
}
#undef FUNC_NAME


GUILE_PROC(scm_member, "member", 2, 0, 0,
           (SCM x, SCM lst),
"")
#define FUNC_NAME s_scm_member
{
  SCM answer;
  SCM_VALIDATE_LIST(2,lst);
  answer = scm_sloppy_member (x, lst);
  return (answer == SCM_EOL) ? SCM_BOOL_F : answer;
}
#undef FUNC_NAME



/* deleting elements from a list (delq, etc.) */

GUILE_PROC(scm_delq_x, "delq!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delq_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_CAR (walk) == item)
	*prev = SCM_CDR (walk);
      else
	prev = SCM_CDRLOC (walk);
    }
    
  return lst;
}
#undef FUNC_NAME


GUILE_PROC(scm_delv_x, "delv!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delv_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_BOOL_F != scm_eqv_p (SCM_CAR (walk), item))
	*prev = SCM_CDR (walk);
      else
	prev = SCM_CDRLOC (walk);
    }
    
  return lst;
}
#undef FUNC_NAME



GUILE_PROC(scm_delete_x, "delete!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delete_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_BOOL_F != scm_equal_p (SCM_CAR (walk), item))
	*prev = SCM_CDR (walk);
      else
	prev = SCM_CDRLOC (walk);
    }

  return lst;
}
#undef FUNC_NAME





GUILE_PROC (scm_delq, "delq", 2, 0, 0,
            (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delq
{
  SCM copy = scm_list_copy (lst);
  return scm_delq_x (item, copy);
}
#undef FUNC_NAME

GUILE_PROC (scm_delv, "delv", 2, 0, 0,
            (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delv
{
  SCM copy = scm_list_copy (lst);
  return scm_delv_x (item, copy);
}
#undef FUNC_NAME

GUILE_PROC (scm_delete, "delete", 2, 0, 0,
            (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delete
{
  SCM copy = scm_list_copy (lst);
  return scm_delete_x (item, copy);
}
#undef FUNC_NAME


GUILE_PROC(scm_delq1_x, "delq1!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delq1_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_CAR (walk) == item)
	{
	  *prev = SCM_CDR (walk);
	  break;
	}
      else
	prev = SCM_CDRLOC (walk);
    }
    
  return lst;
}
#undef FUNC_NAME


GUILE_PROC(scm_delv1_x, "delv1!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delv1_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_BOOL_F != scm_eqv_p (SCM_CAR (walk), item))
	{
	  *prev = SCM_CDR (walk);
	  break;
	}
      else
	prev = SCM_CDRLOC (walk);
    }
    
  return lst;
}
#undef FUNC_NAME


GUILE_PROC(scm_delete1_x, "delete1!", 2, 0, 0,
           (SCM item, SCM lst),
"")
#define FUNC_NAME s_scm_delete1_x
{
  SCM walk;
  SCM *prev;

  for (prev = &lst, walk = lst;
       SCM_NIMP (walk) && SCM_CONSP (walk);
       walk = SCM_CDR (walk))
    {
      if (SCM_BOOL_F != scm_equal_p (SCM_CAR (walk), item))
	{
	  *prev = SCM_CDR (walk);
	  break;
	}
      else
	prev = SCM_CDRLOC (walk);
    }

  return lst;
}
#undef FUNC_NAME



void
scm_init_list ()
{
#include "list.x"
}

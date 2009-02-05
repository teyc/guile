/* Copyright (C) 2001 Free Software Foundation, Inc.
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

/* This file is included in vm.c multiple times */

#if (VM_ENGINE == SCM_VM_REGULAR_ENGINE)
#define VM_USE_HOOKS		0	/* Various hooks */
#define VM_USE_CLOCK		0	/* Bogoclock */
#define VM_CHECK_EXTERNAL	1	/* Check external link */
#define VM_CHECK_OBJECT         1       /* Check object table */
#define VM_PUSH_DEBUG_FRAMES    0       /* Push frames onto the evaluator debug stack */
#elif (VM_ENGINE == SCM_VM_DEBUG_ENGINE)
#define VM_USE_HOOKS		1
#define VM_USE_CLOCK		1
#define VM_CHECK_EXTERNAL	1
#define VM_CHECK_OBJECT         1
#define VM_PUSH_DEBUG_FRAMES    1
#else
#error unknown debug engine VM_ENGINE
#endif

#include "vm-engine.h"


static SCM
VM_NAME (struct scm_vm *vp, SCM program, SCM *argv, int nargs)
{
  /* VM registers */
  register scm_byte_t *ip IP_REG;	/* instruction pointer */
  register SCM *sp SP_REG;		/* stack pointer */
  register SCM *fp FP_REG;		/* frame pointer */

  /* Cache variables */
  struct scm_objcode *bp = NULL;	/* program base pointer */
  SCM external = SCM_EOL;		/* external environment */
  SCM *objects = NULL;			/* constant objects */
  size_t object_count = 0;              /* length of OBJECTS */
  SCM *stack_base = vp->stack_base;	/* stack base address */
  SCM *stack_limit = vp->stack_limit;	/* stack limit address */

  /* Internal variables */
  int nvalues = 0;
  long start_time = scm_c_get_internal_run_time ();
  SCM finish_args;                      /* used both for returns: both in error
                                           and normal situations */
#if VM_USE_HOOKS
  SCM hook_args = SCM_EOL;
#endif

#ifdef HAVE_LABELS_AS_VALUES
  static void **jump_table = NULL;
#endif
  
#if VM_PUSH_DEBUG_FRAMES
  scm_t_debug_frame debug;
  scm_t_debug_info debug_vect_body;
  debug.status = SCM_VOIDFRAME;
#endif

#ifdef HAVE_LABELS_AS_VALUES
  if (SCM_UNLIKELY (!jump_table))
    {
      int i;
      jump_table = malloc (SCM_VM_NUM_INSTRUCTIONS * sizeof(void*));
      for (i = 0; i < SCM_VM_NUM_INSTRUCTIONS; i++)
        jump_table[i] = &&vm_error_bad_instruction;
#define VM_INSTRUCTION_TO_LABEL 1
#include "vm-expand.h"
#include "vm-i-system.i"
#include "vm-i-scheme.i"
#include "vm-i-loader.i"
#undef VM_INSTRUCTION_TO_LABEL
    }
#endif

  /* Initialization */
  {
    SCM prog = program;

    /* Boot program */
    program = vm_make_boot_program (nargs);

#if VM_PUSH_DEBUG_FRAMES
    debug.prev = scm_i_last_debug_frame ();
    if (!(debug.prev && debug.prev->status == SCM_APPLYFRAME
          && debug.prev->vect[0].a.proc != prog))
      {
        debug.status = SCM_APPLYFRAME;
        debug.vect = &debug_vect_body;
        debug.vect[0].a.proc = program; /* the boot program */
        debug.vect[0].a.args = SCM_EOL;
        scm_i_set_last_debug_frame (&debug);
      }
#endif

    /* Initial frame */
    CACHE_REGISTER ();
    CACHE_PROGRAM ();
    PUSH (program);
    NEW_FRAME ();

    /* Initial arguments */
    PUSH (prog);
    if (SCM_UNLIKELY (sp + nargs >= stack_limit))
      goto vm_error_too_many_args;
    while (nargs--)
      PUSH (*argv++);
  }

  /* Let's go! */
  BOOT_HOOK ();
  NEXT;

#ifndef HAVE_LABELS_AS_VALUES
 vm_start:
  switch ((*ip++) & SCM_VM_INSTRUCTION_MASK) {
#endif

#include "vm-expand.h"
#include "vm-i-system.c"
#include "vm-i-scheme.c"
#include "vm-i-loader.c"

#ifndef HAVE_LABELS_AS_VALUES
  default:
    goto vm_error_bad_instruction;
  }
#endif

  
 vm_done:
  SYNC_ALL ();
#if VM_PUSH_DEBUG_FRAMES
  if (debug.status == SCM_APPLYFRAME)
    scm_i_set_last_debug_frame (debug.prev);
#endif
  return finish_args;

  /* Errors */
  {
    SCM err_msg;

  vm_error_bad_instruction:
    err_msg  = scm_from_locale_string ("VM: Bad instruction: ~A");
    finish_args = SCM_LIST1 (scm_from_uchar (ip[-1]));
    goto vm_error;

  vm_error_unbound:
    err_msg  = scm_from_locale_string ("VM: Unbound variable: ~A");
    goto vm_error;

  vm_error_wrong_type_arg:
    err_msg  = scm_from_locale_string ("VM: Wrong type argument");
    finish_args = SCM_EOL;
    goto vm_error;

  vm_error_too_many_args:
    err_msg  = scm_from_locale_string ("VM: Too many arguments");
    finish_args = SCM_LIST1 (scm_from_int (nargs));
    goto vm_error;

  vm_error_wrong_num_args:
    /* nargs and program are valid */
    SYNC_ALL ();
    scm_wrong_num_args (program);
    /* shouldn't get here */
    goto vm_error;

  vm_error_wrong_type_apply:
    err_msg  = scm_from_locale_string ("VM: Wrong type to apply: ~S "
				       "[IP offset: ~a]");
    finish_args = SCM_LIST2 (program,
			  SCM_I_MAKINUM (ip - bp->base));
    goto vm_error;

  vm_error_stack_overflow:
    err_msg  = scm_from_locale_string ("VM: Stack overflow");
    finish_args = SCM_EOL;
    goto vm_error;

  vm_error_stack_underflow:
    err_msg  = scm_from_locale_string ("VM: Stack underflow");
    finish_args = SCM_EOL;
    goto vm_error;

  vm_error_improper_list:
    err_msg  = scm_from_locale_string ("VM: Attempt to unroll an improper list: tail is ~A");
    goto vm_error;

  vm_error_not_a_pair:
    SYNC_ALL ();
    scm_wrong_type_arg_msg (FUNC_NAME, 1, finish_args, "pair");
    /* shouldn't get here */
    goto vm_error;

  vm_error_no_values:
    err_msg  = scm_from_locale_string ("VM: 0-valued return");
    finish_args = SCM_EOL;
    goto vm_error;

  vm_error_not_enough_values:
    err_msg  = scm_from_locale_string ("VM: Not enough values for mv-bind");
    finish_args = SCM_EOL;
    goto vm_error;

  vm_error_no_such_module:
    err_msg  = scm_from_locale_string ("VM: No such module: ~A");
    goto vm_error;

#if VM_CHECK_IP
  vm_error_invalid_address:
    err_msg  = scm_from_locale_string ("VM: Invalid program address");
    finish_args = SCM_EOL;
    goto vm_error;
#endif

#if VM_CHECK_EXTERNAL
  vm_error_external:
    err_msg  = scm_from_locale_string ("VM: Invalid external access");
    finish_args = SCM_EOL;
    goto vm_error;
#endif

#if VM_CHECK_OBJECT
  vm_error_object:
    err_msg = scm_from_locale_string ("VM: Invalid object table access");
    finish_args = SCM_EOL;
    goto vm_error;
#endif

  vm_error:
    SYNC_ALL ();

    scm_ithrow (sym_vm_error, SCM_LIST3 (sym_vm_run, err_msg, finish_args), 1);
  }

  abort (); /* never reached */
}

#undef VM_USE_HOOKS
#undef VM_USE_CLOCK
#undef VM_CHECK_EXTERNAL
#undef VM_CHECK_OBJECT
#undef VM_PUSH_DEBUG_FRAMES

/*
  Local Variables:
  c-file-style: "gnu"
  End:
*/

BITS 32
section .text
foo:
cmovo cx, bx
cmovno bx, [edx+esi*4]
cmovb edx, eax
cmovc ebp, [esp+eax*4]
cmovnae cx, bx
cmovnb bx, [edx+esi*4]
cmovnc edx, eax
cmovae ebp, [esp+eax*4]
cmove cx, bx
cmovz bx, [edx+esi*4]
cmovne edx, eax
cmovnz ebp, [esp+eax*4]
cmovbe cx, bx
cmovna bx, [edx+esi*4]
cmova edx, eax
cmovnbe ebp, [esp+eax*4]
cmovs cx, bx
cmovns bx, [edx+esi*4]
cmovp edx, eax
cmovpe ebp, [esp+eax*4]
cmovnp cx, bx
cmovpo bx, [edx+esi*4]
cmovl edx, eax
cmovnge ebp, [esp+eax*4]
cmovge cx, bx
cmovnl bx, [edx+esi*4]
cmovle edx, eax
cmovng ebp, [esp+eax*4]
cmovnle cx, bx
cmovg bx, [edx+esi*4]

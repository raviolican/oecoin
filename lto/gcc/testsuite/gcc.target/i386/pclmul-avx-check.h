#ifdef DEBUG
#include <stdio.h>
#endif
#include <stdlib.h>
#include "cpuid.h"

static void pclmul_avx_test (void);

int
main ()
{
  unsigned int eax, ebx, ecx, edx;
 
  if (!__get_cpuid (1, &eax, &ebx, &ecx, &edx))
    return 0;

  /* Run PCLMUL + AVX test only if host has PCLMUL + AVX support.  */
  if ((ecx & (bit_AVX | bit_PCLMUL)) == (bit_AVX | bit_PCLMUL))
    {
      pclmul_avx_test ();
#ifdef DEBUG
      printf ("PASSED\n");
#endif
    }
#ifdef DEBUG
  else
    printf ("SKIPPED\n");
#endif

  return 0;
}

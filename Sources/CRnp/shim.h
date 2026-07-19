#ifndef SWIFT_RNP_CRNP_SHIM_H
#define SWIFT_RNP_CRNP_SHIM_H

#if __has_include(<rnp/rnp.h>)
#include <rnp/rnp.h>
#else
/* Fall back to the vendored headers bundled next to this module map when
   building from Xcode without pkg-config. rnp_ver.h needs assert.h for
   static_assert, so it is included after the standard header. */
#include "rnp/rnp.h"
#include "rnp/rnp_err.h"
#include "rnp/rnp_export.h"
#include <assert.h>
#include "rnp/rnp_ver.h"
#endif

#endif /* SWIFT_RNP_CRNP_SHIM_H */

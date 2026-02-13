/*
 * Replacement for upstream `src/terminal/terminaldisplayinit.cc` that avoids
 * ncurses/terminfo on Apple platforms (and generally for library embedding).
 *
 * We intentionally do not compile the upstream terminaldisplayinit.cc in Clauntty.
 */

#include "src/terminal/terminaldisplay.h"

using namespace Terminal;

namespace {
// xterm-compatible alternate screen sequences (terminfo smcup/rmcup)
static const char kSmcup[] = "\033[?1049h";
static const char kRmcup[] = "\033[?1049l";
}

Display::Display( bool /*use_environment*/ )
  : has_ech( true ), has_bce( true ), has_title( true ), smcup( kSmcup ), rmcup( kRmcup )
{
  // We deliberately ignore terminfo and assume xterm-256color semantics.
  // GhosttyKit (and most modern terminals) support these sequences.
}


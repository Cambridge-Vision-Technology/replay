module Replay.TraceContext.Effect
  ( TraceContextF(..)
  ) where

import Prelude

import Replay.TraceContext as Replay.TraceContext

-- ============================================================================
-- Effect Type
-- ============================================================================

-- | Functor for the trace context effect.
-- | Follows the reader pattern like PipelineEnvF.
-- | The context is set at interpreter creation time via configuration.
data TraceContextF a = AskTraceContext (Replay.TraceContext.TraceContext -> a)

derive instance Functor TraceContextF

module Replay.TraceContext.Test
  ( runTests
  ) where

import Prelude

import Data.Maybe as Data.Maybe
import Effect as Effect
import Replay.Common as Replay.Common
import Replay.TraceContext as Replay.TraceContext
import Replay.Protocol.Types as Replay.Protocol.Types

testNewTraceCreatesUniqueTraceId :: Effect.Effect Replay.Common.TestResult
testNewTraceCreatesUniqueTraceId = do
  ctx1 <- Replay.TraceContext.newTrace
  ctx2 <- Replay.TraceContext.newTrace
  pure $
    if ctx1.traceId /= ctx2.traceId then
      Replay.Common.TestSuccess "newTrace creates unique TraceId each time"
    else
      Replay.Common.TestFailure "newTrace creates unique TraceId each time" "Two calls to newTrace produced the same TraceId"

testNewTraceCreatesUniqueStreamId :: Effect.Effect Replay.Common.TestResult
testNewTraceCreatesUniqueStreamId = do
  ctx1 <- Replay.TraceContext.newTrace
  ctx2 <- Replay.TraceContext.newTrace
  pure $
    if ctx1.currentStreamId /= ctx2.currentStreamId then
      Replay.Common.TestSuccess "newTrace creates unique StreamId each time"
    else
      Replay.Common.TestFailure "newTrace creates unique StreamId each time" "Two calls to newTrace produced the same StreamId"

testNewTraceRootStreamEqualsTrace :: Effect.Effect Replay.Common.TestResult
testNewTraceRootStreamEqualsTrace = do
  ctx <- Replay.TraceContext.newTrace
  let (Replay.Protocol.Types.TraceId traceIdStr) = ctx.traceId
  let (Replay.Protocol.Types.StreamId streamIdStr) = ctx.currentStreamId
  pure $
    if traceIdStr == streamIdStr then
      Replay.Common.TestSuccess "newTrace sets traceId equal to currentStreamId at root"
    else
      Replay.Common.TestFailure "newTrace sets traceId equal to currentStreamId at root" "Root trace's traceId does not equal its currentStreamId"

testNewTraceHasNoParent :: Effect.Effect Replay.Common.TestResult
testNewTraceHasNoParent = do
  ctx <- Replay.TraceContext.newTrace
  pure $
    if Data.Maybe.isNothing ctx.parentStreamId then
      Replay.Common.TestSuccess "newTrace has no parent at root"
    else
      Replay.Common.TestFailure "newTrace has no parent at root" "Root trace unexpectedly has a parentStreamId"

testNewTraceHasNoCausation :: Effect.Effect Replay.Common.TestResult
testNewTraceHasNoCausation = do
  ctx <- Replay.TraceContext.newTrace
  pure $
    if Data.Maybe.isNothing ctx.causationStreamId then
      Replay.Common.TestSuccess "newTrace has no causation at root"
    else
      Replay.Common.TestFailure "newTrace has no causation at root" "Root trace unexpectedly has a causationStreamId"

testNewTraceHasSiblingIndexZero :: Effect.Effect Replay.Common.TestResult
testNewTraceHasSiblingIndexZero = do
  ctx <- Replay.TraceContext.newTrace
  pure $
    if ctx.siblingIndex == Replay.Protocol.Types.SiblingIndex 0 then
      Replay.Common.TestSuccess "newTrace has siblingIndex 0 at root"
    else
      Replay.Common.TestFailure "newTrace has siblingIndex 0 at root" "Root trace's siblingIndex is not 0"

testChildContextMaintainsTraceId :: Effect.Effect Replay.Common.TestResult
testChildContextMaintainsTraceId = do
  parent <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext parent
  pure $
    if parent.traceId == child.traceId then
      Replay.Common.TestSuccess "childContext maintains traceId"
    else
      Replay.Common.TestFailure "childContext maintains traceId" "Child context has different traceId than parent"

testChildContextUpdatesParentStreamId :: Effect.Effect Replay.Common.TestResult
testChildContextUpdatesParentStreamId = do
  parent <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext parent
  pure $
    if child.parentStreamId == Data.Maybe.Just parent.currentStreamId then
      Replay.Common.TestSuccess "childContext updates parentStreamId"
    else
      Replay.Common.TestFailure "childContext updates parentStreamId" "Child's parentStreamId does not match parent's currentStreamId"

testChildContextCreatesNewStreamId :: Effect.Effect Replay.Common.TestResult
testChildContextCreatesNewStreamId = do
  parent <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext parent
  pure $
    if parent.currentStreamId /= child.currentStreamId then
      Replay.Common.TestSuccess "childContext creates new streamId"
    else
      Replay.Common.TestFailure "childContext creates new streamId" "Child has same streamId as parent"

testChildContextResetsSiblingIndex :: Effect.Effect Replay.Common.TestResult
testChildContextResetsSiblingIndex = do
  parent <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext parent
  pure $
    if child.siblingIndex == Replay.Protocol.Types.SiblingIndex 0 then
      Replay.Common.TestSuccess "childContext resets siblingIndex to 0"
    else
      Replay.Common.TestFailure "childContext resets siblingIndex to 0" "Child's siblingIndex is not 0"

testSiblingContextMaintainsTraceId :: Effect.Effect Replay.Common.TestResult
testSiblingContextMaintainsTraceId = do
  parent <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext parent (Replay.Protocol.Types.SiblingIndex 1)
  pure $
    if parent.traceId == sibling.traceId then
      Replay.Common.TestSuccess "siblingContext maintains traceId"
    else
      Replay.Common.TestFailure "siblingContext maintains traceId" "Sibling context has different traceId than original"

testSiblingContextMaintainsParentStreamId :: Effect.Effect Replay.Common.TestResult
testSiblingContextMaintainsParentStreamId = do
  parent <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext parent (Replay.Protocol.Types.SiblingIndex 1)
  pure $
    if parent.parentStreamId == sibling.parentStreamId then
      Replay.Common.TestSuccess "siblingContext maintains parentStreamId"
    else
      Replay.Common.TestFailure "siblingContext maintains parentStreamId" "Sibling context has different parentStreamId than original"

testSiblingContextUpdatesSiblingIndex :: Effect.Effect Replay.Common.TestResult
testSiblingContextUpdatesSiblingIndex = do
  parent <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext parent (Replay.Protocol.Types.SiblingIndex 5)
  pure $
    if sibling.siblingIndex == Replay.Protocol.Types.SiblingIndex 5 then
      Replay.Common.TestSuccess "siblingContext updates siblingIndex"
    else
      Replay.Common.TestFailure "siblingContext updates siblingIndex" "Sibling's siblingIndex was not updated correctly"

testSiblingContextCreatesNewStreamId :: Effect.Effect Replay.Common.TestResult
testSiblingContextCreatesNewStreamId = do
  parent <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext parent (Replay.Protocol.Types.SiblingIndex 1)
  pure $
    if parent.currentStreamId /= sibling.currentStreamId then
      Replay.Common.TestSuccess "siblingContext creates new streamId"
    else
      Replay.Common.TestFailure "siblingContext creates new streamId" "Sibling has same streamId as original"

testWithCausationSetsCausationStreamId :: Effect.Effect Replay.Common.TestResult
testWithCausationSetsCausationStreamId = do
  ctx <- Replay.TraceContext.newTrace
  let causationId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  let modifiedCtx = Replay.TraceContext.withCausation causationId ctx
  pure $
    if modifiedCtx.causationStreamId == Data.Maybe.Just causationId then
      Replay.Common.TestSuccess "withCausation sets causationStreamId"
    else
      Replay.Common.TestFailure "withCausation sets causationStreamId" "causationStreamId was not set correctly"

testWithCausationPreservesOtherFields :: Effect.Effect Replay.Common.TestResult
testWithCausationPreservesOtherFields = do
  ctx <- Replay.TraceContext.newTrace
  let causationId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  let modifiedCtx = Replay.TraceContext.withCausation causationId ctx
  let
    preserved =
      modifiedCtx.traceId == ctx.traceId
        && modifiedCtx.currentStreamId == ctx.currentStreamId
        && modifiedCtx.parentStreamId == ctx.parentStreamId
        && modifiedCtx.siblingIndex == ctx.siblingIndex
  pure $
    if preserved then
      Replay.Common.TestSuccess "withCausation preserves other fields"
    else
      Replay.Common.TestFailure "withCausation preserves other fields" "withCausation modified fields other than causationStreamId"

testContextFlowsThroughSequentialOps :: Effect.Effect Replay.Common.TestResult
testContextFlowsThroughSequentialOps = do
  root <- Replay.TraceContext.newTrace
  child1 <- Replay.TraceContext.childContext root
  child2 <- Replay.TraceContext.childContext child1
  grandchild <- Replay.TraceContext.childContext child2
  let
    rootCorrect = Data.Maybe.isNothing root.parentStreamId
    child1Correct = child1.parentStreamId == Data.Maybe.Just root.currentStreamId
    child2Correct = child2.parentStreamId == Data.Maybe.Just child1.currentStreamId
    grandchildCorrect = grandchild.parentStreamId == Data.Maybe.Just child2.currentStreamId
    allSameTraceId = root.traceId == child1.traceId
      && child1.traceId == child2.traceId
      && child2.traceId == grandchild.traceId
  pure $
    if rootCorrect && child1Correct && child2Correct && grandchildCorrect && allSameTraceId then
      Replay.Common.TestSuccess "Context flows correctly through sequential operations"
    else
      Replay.Common.TestFailure "Context flows correctly through sequential operations" "Parent-child chain is broken or traceId not preserved"

testGenerateStreamIdCreatesUniqueIds :: Effect.Effect Replay.Common.TestResult
testGenerateStreamIdCreatesUniqueIds = do
  id1 <- Replay.TraceContext.generateStreamId
  id2 <- Replay.TraceContext.generateStreamId
  id3 <- Replay.TraceContext.generateStreamId
  pure $
    if id1 /= id2 && id2 /= id3 && id1 /= id3 then
      Replay.Common.TestSuccess "generateStreamId creates unique IDs"
    else
      Replay.Common.TestFailure "generateStreamId creates unique IDs" "Generated stream IDs are not unique"

testAccessorsReturnCorrectValues :: Effect.Effect Replay.Common.TestResult
testAccessorsReturnCorrectValues = do
  root <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext root
  let causationId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  let childWithCausation = Replay.TraceContext.withCausation causationId child
  let
    traceIdCorrect = Replay.TraceContext.traceId childWithCausation == childWithCausation.traceId
    parentCorrect = Replay.TraceContext.parentStreamId childWithCausation == childWithCausation.parentStreamId
    causationCorrect = Replay.TraceContext.causationStreamId childWithCausation == childWithCausation.causationStreamId
    siblingCorrect = Replay.TraceContext.siblingIndex childWithCausation == childWithCausation.siblingIndex
    currentCorrect = Replay.TraceContext.currentStreamId childWithCausation == childWithCausation.currentStreamId
  pure $
    if traceIdCorrect && parentCorrect && causationCorrect && siblingCorrect && currentCorrect then
      Replay.Common.TestSuccess "Accessors return correct values"
    else
      Replay.Common.TestFailure "Accessors return correct values" "One or more accessors returned incorrect values"

effectTests :: Effect.Effect (Array Replay.Common.TestResult)
effectTests = do
  r1 <- testNewTraceCreatesUniqueTraceId
  r2 <- testNewTraceCreatesUniqueStreamId
  r3 <- testNewTraceRootStreamEqualsTrace
  r4 <- testNewTraceHasNoParent
  r5 <- testNewTraceHasNoCausation
  r6 <- testNewTraceHasSiblingIndexZero
  r7 <- testChildContextMaintainsTraceId
  r8 <- testChildContextUpdatesParentStreamId
  r9 <- testChildContextCreatesNewStreamId
  r10 <- testChildContextResetsSiblingIndex
  r11 <- testSiblingContextMaintainsTraceId
  r12 <- testSiblingContextMaintainsParentStreamId
  r13 <- testSiblingContextUpdatesSiblingIndex
  r14 <- testSiblingContextCreatesNewStreamId
  r15 <- testWithCausationSetsCausationStreamId
  r16 <- testWithCausationPreservesOtherFields
  r17 <- testContextFlowsThroughSequentialOps
  r18 <- testGenerateStreamIdCreatesUniqueIds
  r19 <- testAccessorsReturnCorrectValues
  pure [ r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19 ]

runTests :: Effect.Effect Replay.Common.TestResults
runTests = Replay.Common.computeResults <$> effectTests

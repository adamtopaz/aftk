import AFTKTest.Informal.Assert
import AFTKTest.Informal.Fixtures

namespace AFTKTest.Informal.Presentation

open AFTKTest.Informal
open AFTK.Informal

private def compactSummaryIncludesCoreFields : TestCase := {
  name := "informal.presentation.compactSummaryIncludesCoreFields"
  run := do
    let root ← basicRoot
    let resolved ← resolveRefAt root "group.basic.definition"
    let summary := summaryOfResolved resolved
    let rendered := renderSummaryText summary
    assertContains rendered "Informal node: group.basic.definition"
    assertContains rendered "Title: Definition of group"
    assertContains rendered "Kind: definition"
    assertContains rendered "Status: active"
    assertContains rendered "Summary: A group is a monoid in which every element has an inverse."
}

private def richPreviewTruncatesDeterministically : TestCase := {
  name := "informal.presentation.richPreviewTruncatesDeterministically"
  run := do
    let root ← longBodyRoot
    let resolved ← resolveRefAt root "analysis.uniform_continuity"
    let payload := payloadOfResolved resolved .preview
    let rendered := renderPayloadText payload
    assertContains rendered "Body"
    assertContains rendered "[truncated]"
    match payload.body with
    | .preview _ truncated => assertTrue truncated "expected preview body to be truncated"
    | _ => fail "expected preview body presentation"
}

private def richFullBodyKeepsWholeBody : TestCase := {
  name := "informal.presentation.richFullBodyKeepsWholeBody"
  run := do
    let root ← longBodyRoot
    let resolved ← resolveRefAt root "analysis.uniform_continuity"
    let payload := payloadOfResolved resolved .full
    let rendered := renderPayloadText payload
    assertContains rendered "Compactness hypotheses frequently imply uniform continuity"
    match payload.body with
    | .full text => assertContains text "The same δ must work for every pair x and y."
    | _ => fail "expected full body presentation"
}

private def richPresentationIncludesSortedSections : TestCase := {
  name := "informal.presentation.richPresentationIncludesSortedSections"
  run := do
    let root ← longBodyRoot
    let resolved ← resolveRefAt root "analysis.uniform_continuity"
    let payload := payloadOfResolved resolved .preview
    assertEq payload.tags #["analysis", "continuity"]
    assertEq payload.authors #["Ada", "Bernhard"]
    assertEq payload.relationshipLines #[
      "relatedTo: algebra.monoid.definition",
      "seeAlso: group.basic.definition — comparison"
    ]
    assertEq payload.leanRefLines #["Mathlib.UniformContinuous [theorem]"]
}


def tests : List TestCase :=
  [compactSummaryIncludesCoreFields, richPreviewTruncatesDeterministically, richFullBodyKeepsWholeBody, richPresentationIncludesSortedSections]

end AFTKTest.Informal.Presentation

module

public import Lean
public import Init.Data.String.Legacy

public section

namespace AFTK

/-- Trim surrounding ASCII whitespace from a string. -/
def normalizeText (raw : String) : String :=
  raw.trimAscii.toString

/-- Require a trimmed string to be non-empty. -/
def nonEmptyText (label raw : String) : Except String String := do
  let trimmed := normalizeText raw
  if trimmed.isEmpty then
    throw s!"{label} must be non-empty"
  return trimmed

def dedupePreservingOrder [BEq α] (items : Array α) : Array α := Id.run do
  let mut out : Array α := #[]
  for item in items do
    if !out.contains item then
      out := out.push item
  return out

def addUnique [BEq α] (items : Array α) (item : α) : Array α :=
  if items.contains item then items else items.push item

def removeAll [BEq α] (items : Array α) (item : α) : Array α :=
  items.filter (· != item)

def sortStrings (items : Array String) : Array String :=
  items.qsort (fun a b => a < b)

def normalizeStringArray (label : String) (items : Array String) : Except String (Array String) := do
  let values ← items.mapM (nonEmptyText label)
  return dedupePreservingOrder values

def lowercase (text : String) : String :=
  String.ofList <| text.toList.map Char.toLower

def containsCaseInsensitive (haystack needle : String) : Bool :=
  lowercase haystack |>.contains (lowercase needle)

end AFTK

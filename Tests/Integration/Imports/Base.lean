import Informalize

namespace Tests.Integration.Imports.Base

noncomputable def baseBare : Nat :=
  informal

noncomputable def baseLoc : Nat :=
  informal[Foo.bar]

end Tests.Integration.Imports.Base

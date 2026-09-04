## Demonstrates the complete façade and the equivalent focused imports.
##
## Compile normally to use `terminal_status`, or pass `-d:focusedImports` to
## prove that pure string rendering does not require importing `live`.

when defined(focusedImports):
  import terminal_status/[progress, rendering, themes]
else:
  import terminal_status

var bar = initProgressBar("Compile API façade", 4, "modules")
bar.advance(3)

var options = defaultRenderOptions()
options.characters = statusAscii
options.useColor = false
options.barWidth = 12
options.showRate = false
options.showEta = false

echo bar.render(options)

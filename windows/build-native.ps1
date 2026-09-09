param([Parameter(Mandatory=$true)][string]$Zig)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
  & $Zig c++ -target x86_64-windows-gnu -std=c++17 -O2 -shared -static -I ../vendor/Clipper2/CPP/Clipper2Lib/include native/windows.cpp ../src/NativeGeometry.cpp ../vendor/Clipper2/CPP/Clipper2Lib/src/clipper.engine.cpp ../vendor/Clipper2/CPP/Clipper2Lib/src/clipper.offset.cpp ../vendor/Clipper2/CPP/Clipper2Lib/src/clipper.rectclip.cpp -o native/acrylic.dll
  if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
} finally { Pop-Location }

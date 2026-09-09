$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
 $launcher=$env:ACRYLIC_ILLUSTRATOR_LAUNCHER
 if(-not $launcher -or -not (Test-Path -LiteralPath $launcher)){throw 'Illustrator 启动脚本缺失。'}
 $aiType=[type]::GetTypeFromProgID('Illustrator.Application')
 if(-not $aiType){throw '本机未注册 Illustrator COM 接口。请安装 Illustrator，或手动运行 JSX。'}
 $aiApp=[Activator]::CreateInstance($aiType)
 $reply=$aiApp.DoJavaScriptFile($launcher,[Type]::Missing,[Type]::Missing)
 [Console]::WriteLine($reply)
} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 1 }

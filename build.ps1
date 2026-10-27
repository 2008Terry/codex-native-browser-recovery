$ErrorActionPreference='Stop'
foreach($name in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Archive')){
    Import-Module ($PSHOME+'\Modules\'+$name+'\'+$name+'.psd1') -ErrorAction Stop
}
$version='0.1.0-preview'
$files=@(
    'ComputerUse.ps1','01-check.cmd','02-repair.cmd','03-restore.cmd',
    'README.md','NATIVE-ACCEPTANCE.txt','docs\REVIEW.md',
    'LICENSE','NOTICE','CHANGELOG.md','.gitignore','validation.json',
    'tests\Test-Recovery.ps1','build.ps1'
)
$dist=Join-Path $PSScriptRoot 'dist'
if((Test-Path -LiteralPath $dist) -and ((Get-Item -LiteralPath $dist).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Refusing a redirected dist directory.'}
[void][IO.Directory]::CreateDirectory($dist)
$stage=Join-Path $dist ('stage-'+[Guid]::NewGuid().ToString('N'))
$package=Join-Path $stage 'codex-native-browser-recovery'
[void][IO.Directory]::CreateDirectory($package)
try{
    $sums=@()
    foreach($relative in $files){
        $source=Join-Path $PSScriptRoot $relative
        if(-not (Test-Path -LiteralPath $source)){throw ('Missing release file: '+$relative)}
        $destination=Join-Path $package $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
        Copy-Item -LiteralPath $source -Destination $destination
        $sums+=((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$relative.Replace('\','/'))
    }
    [IO.File]::WriteAllText((Join-Path $package 'SHA256SUMS.txt'),($sums -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $zip=Join-Path $dist ('CodexNativeBrowserRecovery-'+$version+'.zip')
    Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try{
        $actual=@($archive.Entries|Where-Object{-not $_.FullName.EndsWith('/')}|ForEach-Object{$_.FullName.Replace('\','/')})
        $expected=@($files|ForEach-Object{'codex-native-browser-recovery/'+$_.Replace('\','/')})+@('codex-native-browser-recovery/SHA256SUMS.txt')
        if(@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count -gt 0){throw 'Archive contents do not match the release allowlist.'}
    }finally{$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($zip+'.sha256.txt'),($hash+'  '+[IO.Path]::GetFileName($zip)+"`n"),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Version=$version;Zip=$zip;Sha256=$hash;Files=$expected.Count;ComponentBinariesIncluded=$false}|ConvertTo-Json
}finally{
    $full=[IO.Path]::GetFullPath($stage)
    $allowed=[IO.Path]::GetFullPath($dist).TrimEnd('\')+'\'
    if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside dist.'}
    Remove-Item -LiteralPath $full -Recurse -Force
}

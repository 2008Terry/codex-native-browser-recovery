param([string]$OriginalHelper)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $root 'ComputerUse.ps1'
if (-not (Test-Path -LiteralPath $entry)) { throw 'FAIL: portable recovery implementation is missing.' }
. $entry
$script:Passed = 0
function Assert-True($Condition,[string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:Passed++
    Write-Output ('PASS: ' + $Name)
}
$a = [pscustomobject]@{Path='C:\cache\old.exe';State='KnownPatched'}
$b = [pscustomobject]@{Path='C:\cache\new.exe';State='Unknown'}
$s = Select-Component @($a,$b) @() $true
Assert-True ($s.State -eq 'Ambiguous' -and -not $s.Target) 'multiple caches never imply the old patch is active'
$s = Select-Component @($a,$b) @($b.Path) $true
Assert-True ($s.Target.State -eq 'Unknown' -and $s.LiveConfirmed) 'actual running unknown component takes priority'
Assert-True ((Select-Component @($a,$b) @($a.Path,$b.Path) $true).State -eq 'Ambiguous') 'multiple active paths are ambiguous'
Assert-True ((Select-Component @($a) @() $false).State -eq 'InspectionUnavailable') 'process access failure is not an empty process list'
$s = Select-Component @($a) @() $true
Assert-True (-not $s.LiveConfirmed -and $s.Basis -eq 'OnlyCachedRuntime') 'cache-only result is not live acceptance'
Assert-True ((Select-Component @($a) @('C:\elsewhere\helper.exe') $true).State -eq 'ActivePathNotRecognized') 'unexpected active path is not replaced with a familiar cache'
Assert-True ((Select-Component @() @() $true).State -eq 'Missing') 'missing runtime has a distinct result'
Assert-True ((Protect-ReportText 'C:\Users\ExampleUser\private' 'C:\Users\ExampleUser') -eq '%USERPROFILE%\private') 'shared report removes profile path'
Assert-True ((Protect-ReportText 'C:\\Users\\ExampleUser\\private' 'C:\Users\ExampleUser') -eq '%USERPROFILE%\\private') 'JSON-escaped report paths are also redacted'
$rejected = $false
try { Assert-ChangeAllowed -ProcessInspectionAvailable $true -AppCount 1 -NativeCount 0 } catch { $rejected=$true }
Assert-True $rejected 'running application blocks changes'
$rejected = $false
try { Assert-ChangeAllowed -ProcessInspectionAvailable $false -AppCount 0 -NativeCount 0 } catch { $rejected=$true }
Assert-True $rejected 'unavailable process inspection blocks changes'

$realTests = 'Skipped: pass -OriginalHelper with an exact known original; binaries are not distributed.'
if ($OriginalHelper) {
    $original = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $OriginalHelper).Path)
    if ((Get-ImageHash $original) -ne $script:OriginalHash) { throw 'Test fixture is not the exact known signed original.' }
    $scratch = Join-Path $PSScriptRoot ('scratch-' + [Guid]::NewGuid().ToString('N') + ' 空格测试')
    [void][IO.Directory]::CreateDirectory($scratch)
    try {
        $copy = Join-Path $scratch 'nonexecuted-helper.exe'
        $backup = Join-Path $scratch 'backup\original.exe'
        [IO.File]::WriteAllBytes($copy,$original)
        $patched = New-VerifiedImage $original 'Repair'
        $different = @(for($i=0;$i -lt $original.Length;$i++){if($original[$i] -ne $patched[$i]){$i}})
        Assert-True ($different.Count -eq 36 -and $different[0] -ge $script:PredicateOffset -and $different[-1] -lt $script:PredicateOffset+42) 'exactly 36 changed bytes within the reviewed region'
        $r = Invoke-FileChange $copy 'Repair' $backup
        Assert-True ($r.Changed -and (Get-FileHash -LiteralPath $copy).Hash -eq $script:PatchedHash) 'repair copy has exact expected complete hash'
        Assert-True ((Get-FileHash -LiteralPath $backup).Hash -eq $script:OriginalHash -and (Get-AuthenticodeSignature -LiteralPath $backup).Status -eq 'Valid') 'first repair creates a valid signed local backup'
        Assert-True (-not (Invoke-FileChange $copy 'Repair' $backup).Changed) 'repeat repair is idempotent'
        $rejected=$false
        try { Invoke-FileChange $copy 'Restore' (Join-Path $scratch 'missing.exe') | Out-Null } catch { $rejected=$true }
        Assert-True ($rejected -and (Get-FileHash -LiteralPath $copy).Hash -eq $script:PatchedHash) 'missing original backup blocks restore without a write'
        Invoke-FileChange $copy 'Restore' $backup | Out-Null
        Assert-True ((Get-FileHash -LiteralPath $copy).Hash -eq $script:OriginalHash -and (Get-AuthenticodeSignature -LiteralPath $copy).Status -eq 'Valid') 'restore is byte-identical and signature valid'
        $unknown = $original.Clone()
        $unknown[256] = $unknown[256] -bxor 1
        [IO.File]::WriteAllBytes($copy,$unknown)
        $before = (Get-FileHash -LiteralPath $copy).Hash
        $rejected = $false
        try { Invoke-FileChange $copy 'Repair' $backup | Out-Null } catch { $rejected=$true }
        Assert-True ($rejected -and (Get-FileHash -LiteralPath $copy).Hash -eq $before) 'unknown version is rejected without modification'
        [IO.File]::WriteAllBytes($copy,$original)
        [IO.File]::WriteAllBytes($backup,$unknown)
        $rejected=$false
        try { Invoke-FileChange $copy 'Repair' $backup | Out-Null } catch { $rejected=$true }
        Assert-True ($rejected -and (Get-FileHash -LiteralPath $copy).Hash -eq $script:OriginalHash) 'corrupt backup blocks a write'
        [IO.File]::WriteAllBytes($backup,$original)
        $locked = [IO.File]::Open($copy,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $rejected=$false
        try { Invoke-FileChange $copy 'Repair' $backup | Out-Null } catch { $rejected=$true } finally { $locked.Dispose() }
        Assert-True ($rejected -and (Get-FileHash -LiteralPath $copy).Hash -eq $script:OriginalHash) 'locked file is not forced open'
        $savedWriter = (Get-Item Function:Write-PatchRegion).ScriptBlock
        $script:WriteCalls = 0
        function Write-PatchRegion($Stream,$Image) {
            $script:WriteCalls++
            if ($script:WriteCalls -eq 1) {
                $Stream.Position=$script:PredicateOffset
                $Stream.Write($Image,$script:PredicateOffset,12)
                $Stream.Flush()
                throw 'Simulated partial write failure'
            }
            & $savedWriter $Stream $Image
        }
        $rejected=$false
        try { Invoke-FileChange $copy 'Repair' $backup | Out-Null } catch { $rejected=$true }
        finally { Set-Item Function:Write-PatchRegion $savedWriter }
        Assert-True ($rejected -and (Get-FileHash -LiteralPath $copy).Hash -eq $script:OriginalHash) 'partial write failure rolls back and verifies original'
        $realTests='Passed using nonexecuted local copies; no installed component was modified.'
    } finally {
        $full = [IO.Path]::GetFullPath($scratch)
        $allowed = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
        if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside test folder.'}
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
[pscustomobject]@{Passed=$script:Passed;RealImageTests=$realTests;InstalledComponentModified=$false} | ConvertTo-Json

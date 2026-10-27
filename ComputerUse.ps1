# Community workaround. Not an OpenAI product or official signed fix.
# Modified 2026-10-27: portable PowerShell implementation with local backup,
# explicit consent, exact-build guards, rollback, and redacted reports.
# Predicate bytes derive from heelee912/codex commit 95ee61d; see NOTICE.
[CmdletBinding()]
param(
    [ValidateSet('Check','Repair','Restore')][string]$Action = 'Check',
    [string]$HelperPath,
    [string]$BackupPath,
    [string]$ReportDirectory,
    [switch]$AcceptSignatureChange,
    [switch]$ConfirmRestore,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
foreach($moduleName in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Security','CimCmdlets')) {
    Import-Module ($PSHOME+'\Modules\'+$moduleName+'\'+$moduleName+'.psd1') -ErrorAction Stop
}
$script:ToolVersion = '0.1.0-preview'
$script:OriginalHash = '11825CB78575D9099AED8F13D16F78B03C20A1A0EBC809CF78B406FB2F25F5F8'
$script:PatchedHash = 'C94B17C278AEA46D1DFD42422AF326C7D99B8C604B449695410FFF88B3135B43'
$script:PredicateOffset = 0x1B6C6
$script:OriginalPredicate = '488B8C2488020000488B9424900200004C8D0556BB110041B908000000E82452FFFF84C00F84E7000000'
$script:PatchedPredicate = '4889E9488B01488D942480000000FF90A801000085C0780D81BC24800000006EC300007405E9E7000000'

function Get-ImageHash([byte[]]$Image) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Image)).Replace('-','') } finally { $sha.Dispose() }
}

function Get-ComponentInfo([string]$Path) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $signature = (Get-AuthenticodeSignature -LiteralPath $Path).Status.ToString()
    $state = 'Unknown'
    if($hash -eq $script:OriginalHash){$state='KnownOriginal'}
    if($hash -eq $script:PatchedHash){$state='KnownPatched'}
    $version=$null
    $package=Join-Path (Split-Path (Split-Path (Split-Path $Path -Parent) -Parent) -Parent) 'package.json'
    if(Test-Path -LiteralPath $package){try{$version=(Get-Content -LiteralPath $package -Raw|ConvertFrom-Json).version}catch{}}
    [pscustomobject]@{Path=$Path;State=$state;Sha256=$hash;Signature=$signature;SkyVersion=$version}
}

function Select-Component($Candidates,$ActivePaths,[bool]$ProcessInspectionAvailable) {
    $items=@($Candidates); $active=@($ActivePaths|Sort-Object -Unique)
    $state='Selected'; $target=$null; $basis=$null; $live=$false
    if(-not $ProcessInspectionAvailable){$state='InspectionUnavailable'}
    elseif($active.Count -gt 1){$state='Ambiguous'}
    elseif($active.Count -eq 1){
        $matches=@($items|Where-Object{$_.Path -ieq $active[0]})
        if($matches.Count -eq 1){$target=$matches[0];$basis='RunningNativeProcess';$live=$true}else{$state='ActivePathNotRecognized'}
    }
    elseif($items.Count -eq 1){$target=$items[0];$basis='OnlyCachedRuntime'}
    elseif($items.Count -eq 0){$state='Missing'}else{$state='Ambiguous'}
    [pscustomobject]@{State=$state;Target=$target;Basis=$basis;LiveConfirmed=$live}
}

function New-VerifiedImage([byte[]]$Image,[string]$Operation) {
    if($Operation -notin @('Repair','Restore')){throw 'Unsupported operation.'}
    $hash=Get-ImageHash $Image
    if($hash -notin @($script:OriginalHash,$script:PatchedHash)){throw 'Unknown full-file SHA256; no write allowed.'}
    $desired=if($Operation -eq 'Repair'){$script:PatchedHash}else{$script:OriginalHash}
    if($hash -eq $desired){return ,$Image}
    $old=if($Operation -eq 'Repair'){$script:OriginalPredicate}else{$script:PatchedPredicate}
    $new=if($Operation -eq 'Repair'){$script:PatchedPredicate}else{$script:OriginalPredicate}
    if([BitConverter]::ToString($Image,$script:PredicateOffset,42).Replace('-','') -ne $old){throw 'Reviewed predicate does not match.'}
    $result=$Image.Clone()
    for($i=0;$i -lt 42;$i++){$result[$script:PredicateOffset+$i]=[Convert]::ToByte($new.Substring($i*2,2),16)}
    if((Get-ImageHash $result) -ne $desired){throw 'Derived whole-file hash is not the reviewed expected image.'}
    return ,$result
}

function Read-Image($Stream) {
    $Stream.Position=0
    $memory=[IO.MemoryStream]::new()
    try{$Stream.CopyTo($memory);return ,$memory.ToArray()}finally{$memory.Dispose()}
}

function Write-PatchRegion($Stream,[byte[]]$Image) {
    $Stream.Position=$script:PredicateOffset
    $Stream.Write($Image,$script:PredicateOffset,42)
    $Stream.Flush($true)
    if((Get-ImageHash (Read-Image $Stream)) -ne (Get-ImageHash $Image)){throw 'Complete file readback differs from the expected image.'}
}

function Assert-OriginalBackup([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){throw 'Original backup is missing; restore is unavailable.'}
    $info=Get-ComponentInfo $Path
    if($info.State -ne 'KnownOriginal' -or $info.Signature -ne 'Valid'){throw 'Backup hash/signature is invalid; no write allowed.'}
}

function Invoke-FileChange([string]$Path,[string]$Operation,[string]$OriginalBackupPath) {
    $before=Get-ComponentInfo $Path
    if($before.State -notin @('KnownOriginal','KnownPatched')){throw 'Unknown component; no write allowed.'}
    $desired=if($Operation -eq 'Repair'){'KnownPatched'}elseif($Operation -eq 'Restore'){'KnownOriginal'}else{throw 'Unsupported operation.'}
    if($before.State -eq $desired){return [pscustomobject]@{Changed=$false;State=$desired;Sha256=$before.Sha256}}
    if($before.State -eq 'KnownOriginal' -and $before.Signature -ne 'Valid'){throw 'Original signature is not Valid; no write allowed.'}
    if($Operation -eq 'Restore'){Assert-OriginalBackup $OriginalBackupPath}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $original=Read-Image $stream
        $expected=New-VerifiedImage $original $Operation
        if($Operation -eq 'Repair'){
            if(-not (Test-Path -LiteralPath $OriginalBackupPath)){
                [void][IO.Directory]::CreateDirectory((Split-Path $OriginalBackupPath -Parent))
                $backupStream=[IO.File]::Open($OriginalBackupPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{$backupStream.Write($original,0,$original.Length);$backupStream.Flush($true)}finally{$backupStream.Dispose()}
            }
            Assert-OriginalBackup $OriginalBackupPath
        }
        try{Write-PatchRegion $stream $expected}
        catch{
            $writeError=$_.Exception.Message
            try{Write-PatchRegion $stream $original}
            catch{throw ('WRITE AND ROLLBACK FAILED. Preserve backup and stop using this file. '+$_.Exception.Message)}
            throw ('Write failed; original image restored and verified. '+$writeError)
        }
    } finally{$stream.Dispose()}
    $after=Get-ComponentInfo $Path
    if($after.State -ne $desired){throw 'Post-write complete hash verification failed; preserve the backup.'}
    if($Operation -eq 'Restore' -and $after.Signature -ne 'Valid'){throw 'Original bytes restored, but Windows did not validate the restored signature. Preserve the report.'}
    [pscustomobject]@{Changed=$true;State=$after.State;Sha256=$after.Sha256;Signature=$after.Signature}
}

function Assert-ChangeAllowed([bool]$ProcessInspectionAvailable,[int]$AppCount,[int]$NativeCount) {
    if(-not $ProcessInspectionAvailable){throw 'Process inspection unavailable; no write allowed.'}
    if($AppCount -gt 0 -or $NativeCount -gt 0){throw 'Save work, fully quit Codex and its native helper, then retry. No process will be killed.'}
}

function Protect-ReportText([string]$Text,[string]$ProfilePath) {
    if($ProfilePath){$Text=$Text.Replace($ProfilePath.Replace('\','\\'),'%USERPROFILE%').Replace($ProfilePath,'%USERPROFILE%')}
    return $Text
}

function Get-LocalInspection {
    $runtimeRoot=Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
    $relative='bin\node_modules\@oai\sky\bin\windows\codex-computer-use.exe'
    $items=@();$readErrors=@()
    if(Test-Path -LiteralPath $runtimeRoot){
        foreach($folder in @(Get-ChildItem -LiteralPath $runtimeRoot -Directory)){
            if($folder.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            $candidate=Join-Path $folder.FullName $relative
            if(Test-Path -LiteralPath $candidate){
                try{$items+=Get-ComponentInfo $candidate}catch{$readErrors+=[pscustomobject]@{Path=$candidate;Error=$_.Exception.Message}}
            }
        }
    }
    $available=$true;$native=@();$apps=@()
    try{
        $native=@(Get-CimInstance Win32_Process -Filter "Name = 'codex-computer-use.exe'")
        $apps=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'")
        if(@($native|Where-Object{-not $_.ExecutablePath}).Count -gt 0){throw 'Native process path unavailable.'}
    }catch{$available=$false}
    $active=@($native|ForEach-Object{$_.ExecutablePath}|Where-Object{$_}|Sort-Object -Unique)
    $selected=Select-Component $items $active $available
    if($HelperPath){
        $full=[IO.Path]::GetFullPath($HelperPath)
        $matches=@($items|Where-Object{$_.Path -ieq $full})
        if($matches.Count -ne 1){throw '-HelperPath must identify a readable component inside the standard current-user runtime inventory.'}
        $selected=[pscustomobject]@{State='Selected';Target=$matches[0];Basis='ExplicitCachedPath';LiveConfirmed=($active -contains $full)}
    }
    [pscustomobject]@{Candidates=$items;ReadErrors=$readErrors;Selection=$selected;ProcessInspectionAvailable=$available;AppCount=$apps.Count;NativeCount=$native.Count}
}

function Invoke-Recovery {
    if(-not [Environment]::Is64BitProcess){throw 'Use 64-bit Windows PowerShell 5.1 or 64-bit PowerShell 7.'}
    if($Action -eq 'Repair' -and -not $AcceptSignatureChange){throw 'Repair requires -AcceptSignatureChange. Read README: modifying the helper invalidates its OpenAI signature.'}
    if($Action -eq 'Restore' -and -not $ConfirmRestore){throw 'Restore requires -ConfirmRestore. The known old original may reproduce the browser failure.'}
    $inspection=Get-LocalInspection
    $selection=$inspection.Selection
    $backup=$BackupPath
    if(-not $backup){$backup=Join-Path $env:LOCALAPPDATA ('CodexNativeBrowserRecovery\backups\'+$script:OriginalHash+'.exe')}
    $backup=[IO.Path]::GetFullPath($backup)
    $backupState='Missing'
    if(Test-Path -LiteralPath $backup){try{Assert-OriginalBackup $backup;$backupState='Verified'}catch{$backupState='Invalid'}}
    $code=20;$message='No supported component selected; no component was modified.'
    if($selection.Target){
        switch($selection.Target.State){
            'KnownPatched'{$code=0;$message='Exact known patch image found. File evidence only; native webpage acceptance has not been run.'}
            'KnownOriginal'{$code=10;$message='Known localization-defect build found. This is not proof that the current user has a runtime failure.'}
            'Unknown'{$code=20;$message='Unknown build: it may be officially fixed or still affected. No old patch is applicable; native validation is needed.'}
        }
        if(-not $selection.LiveConfirmed){$code=21;$message+=' Cached file only: no proof this is the active runtime.'}
        if($selection.Target.State -eq 'KnownPatched' -and $backupState -ne 'Verified'){$code=27;$message+=' Original backup is unavailable here; restoration requires a verified local original backup.'}
        if($selection.Target.State -eq 'KnownOriginal' -and $selection.Target.Signature -ne 'Valid'){$code=28;$message+=' Original signature is not Valid; repair is refused.'}
    }else{
        switch($selection.State){
            'Missing'{$code=22;$message='No helper found in the standard runtime layout. Start Codex normally or investigate a changed layout.'}
            'Ambiguous'{$code=23;$message='Multiple runtimes exist. No automatic choice was made. Review the inventory before selecting an explicit helper.'}
            'InspectionUnavailable'{$code=24;$message='Cannot inspect process paths. Run in the normal desktop user context; no active-runtime conclusion is available.'}
            'ActivePathNotRecognized'{$code=25;$message='An active native process uses an unrecognized path; investigate locally.'}
        }
    }
    $otherUnknown=@($inspection.Candidates|Where-Object{$_.State -eq 'Unknown' -and (-not $selection.Target -or $_.Path -ine $selection.Target.Path)}).Count -gt 0
    if($otherUnknown){$message+=' Other unverified runtime caches also exist; recheck after restart/update.';if($code -eq 0){$code=26}}
    if($inspection.ReadErrors.Count -gt 0){$code=29;$message+=' Runtime inventory was incomplete; see ReadErrors.'}
    $change=$null
    if($Action -ne 'Check'){
        if(-not $selection.Target -or $inspection.ReadErrors.Count -gt 0){throw $message}
        if($selection.Target.State -eq 'Unknown'){throw 'Unknown full-file hash; the old patch will not be applied.'}
        $desired=if($Action -eq 'Repair'){'KnownPatched'}else{'KnownOriginal'}
        if($selection.Target.State -ne $desired){Assert-ChangeAllowed $inspection.ProcessInspectionAvailable $inspection.AppCount $inspection.NativeCount}
        $change=Invoke-FileChange $selection.Target.Path $Action $backup
        $selection.Target=Get-ComponentInfo $selection.Target.Path
        $code=0;$message=if($change.Changed){'Exact file change verified. Start Codex normally and perform native webpage acceptance.'}else{'Already in the requested exact file state; no write or process restart was performed.'}
        $backupState='Missing'
        if(Test-Path -LiteralPath $backup){try{Assert-OriginalBackup $backup;$backupState='Verified'}catch{$backupState='Invalid'}}
    }
    [pscustomobject]@{
        ToolVersion=$script:ToolVersion;CheckedAtUtc=[DateTime]::UtcNow.ToString('o');Action=$Action;ExitCode=$code;Message=$message
        WindowsUICulture=[Globalization.CultureInfo]::InstalledUICulture.Name
        Selection=$selection;Candidates=$inspection.Candidates;ReadErrors=$inspection.ReadErrors
        BackupPath=$backup;BackupState=$backupState;OtherUnverifiedRuntimePresent=$otherUnknown
        ProcessInspectionAvailable=$inspection.ProcessInspectionAvailable;Change=$change
        NativeWebAcceptance='NotRun';ExplicitNetworkRequests='None; Windows signature validation uses the system trust service'
    }
}

function Write-LocalReport($Report) {
    $folder=$ReportDirectory
    if(-not $folder){$folder=Join-Path $env:LOCALAPPDATA 'CodexNativeBrowserRecovery\reports'}
    [void][IO.Directory]::CreateDirectory($folder)
    $text=Protect-ReportText ($Report|ConvertTo-Json -Depth 8) $env:USERPROFILE
    if($env:LOCALAPPDATA){$text=$text.Replace($env:LOCALAPPDATA.Replace('\','\\'),'%LOCALAPPDATA%').Replace($env:LOCALAPPDATA,'%LOCALAPPDATA%')}
    [IO.File]::WriteAllText((Join-Path $folder 'last-report.json'),$text,[Text.UTF8Encoding]::new($false))
    $summary="Codex Native Browser Recovery $script:ToolVersion`r`n$($Report.CheckedAtUtc)`r`n$($Report.Action) / $($Report.ExitCode)`r`n$($Report.Message)`r`n`r`nRead the JSON report for file evidence. No webpage acceptance was performed by this checker."
    $summary=Protect-ReportText $summary $env:USERPROFILE
    if($env:LOCALAPPDATA){$summary=$summary.Replace($env:LOCALAPPDATA,'%LOCALAPPDATA%')}
    [IO.File]::WriteAllText((Join-Path $folder 'last-report.txt'),$summary,[Text.UTF8Encoding]::new($false))
    if($Json){Write-Output $text}else{Write-Output $summary;Write-Output ('Local report: '+(Join-Path $folder 'last-report.json'))}
}

if($MyInvocation.InvocationName -ne '.'){
    try{$report=Invoke-Recovery}
    catch{$report=[pscustomobject]@{ToolVersion=$script:ToolVersion;CheckedAtUtc=[DateTime]::UtcNow.ToString('o');Action=$Action;ExitCode=30;Message=$_.Exception.Message;NativeWebAcceptance='NotRun'}}
    try{Write-LocalReport $report}catch{Write-Error ('Cannot write local report: '+$_.Exception.Message) -ErrorAction Continue;exit 31}
    exit $report.ExitCode
}

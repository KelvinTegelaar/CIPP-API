function Invoke-CIPPBaselineExoBulkSweep {
    <#
    .SYNOPSIS
        ExoBulkSweep executor: runs one Exchange cmdlet per object in a prepare hook's
        offender set.
    .DESCRIPTION
        The Exchange counterpart to GraphBulkSweep, and it follows the same contract: the
        prepare hook decides WHICH mailboxes are wrong (bespoke - joins, licence predicates,
        plan caps), this applies the SAME cmdlet to each of them in one batched request rather
        than one round trip per mailbox.

        A hook returns two lists, because the compare and the write want different shapes:
          offenders - display strings (a UPN), graded against [] so drift reads as names.
          targets   - one object per offender carrying what the cmdlet needs. Not graded: the
                      engine projects Current down to the expected keys before comparing.

        Spec (fully rendered):
          writes[]      - ordered groups, each { from, cmdlet, params, compliance }. 'from'
                          names the property on -Current holding the objects (default
                          'targets'); a group naming a property that does not exist is an
                          authoring error and throws, one that exists and is empty is nothing
                          to do. params values may carry %property% tokens resolved against
                          each object, with the engine's token semantics - an exact "%prop%"
                          keeps the property's type.
          refreshCache  - cache types to re-collect after a successful sweep, so the mailboxes
                          just fixed do not read back as drift next run.

        Each cmdlet carries an OperationGuid set to the object it targets, which is what makes
        per-object failures attributable - New-ExoBulkRequest echoes it back on both the
        success and the error shape. Partial failure does NOT throw: the mailboxes that were
        fixed stay fixed and the next run re-derives the remainder. A sweep where EVERY cmdlet
        failed does throw, because that is a permission or connectivity problem and swallowing
        it would report Remediated forever while nothing changed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Expand = {
        param($Template, $Object)
        $Json = ConvertTo-Json -Compress -Depth 100 -InputObject $Template
        foreach ($Property in $Object.PSObject.Properties) {
            $Token = '%{0}%' -f $Property.Name
            $Json = $Json.Replace(('"{0}"' -f $Token), (ConvertTo-Json -Compress -Depth 100 -InputObject $Property.Value))
            $Json = $Json.Replace($Token, "$($Property.Value)")
        }
        $Json | ConvertFrom-Json
    }

    $Attempted = 0
    $Failed = 0
    $FailureDetail = [System.Collections.Generic.List[string]]::new()

    foreach ($Write in @($Remediate.writes)) {
        if (-not $Write) { continue }
        $From = "$($Write.from)"
        if ([string]::IsNullOrWhiteSpace($From)) { $From = 'targets' }
        if (-not ($Current -and $Current.PSObject.Properties.Name -contains $From)) {
            throw "ExoBulkSweep: the prepare hook produced no '$From' set to sweep."
        }
        $Objects = @($Current.$From | Where-Object { $_ })
        if ($Objects.Count -eq 0) { continue }
        if (-not $Write.cmdlet) { throw 'ExoBulkSweep: a write group declares no cmdlet.' }

        $Requests = foreach ($Object in $Objects) {
            $Parameters = @{}
            foreach ($Property in (& $Expand ($Write.params ?? [PSCustomObject]@{}) $Object).PSObject.Properties) {
                $Parameters[$Property.Name] = $Property.Value
            }
            @{
                CmdletInput   = @{ CmdletName = "$($Write.cmdlet)"; Parameters = $Parameters }
                OperationGuid = "$($Object.id ?? $Object.Identity ?? $Object.UPN)"
            }
        }

        $Attempted += $Objects.Count
        $Results = @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Requests) -useSystemMailbox $true -Compliance:([bool]($Write.compliance ?? $false)))
        foreach ($Result in $Results) {
            if ($Result.error) {
                $Failed++
                $FailureDetail.Add("$($Result.OperationGuid ?? $Result.target) -> $($Result.error)")
            }
        }
    }

    if ($Attempted -eq 0) { return }

    if ($FailureDetail.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Sweep: $Failed of $Attempted mailbox writes failed. $(($FailureDetail | Select-Object -First 10) -join ' | ')" -Sev 'Warning'
    }
    if ($Failed -ge $Attempted) {
        throw "ExoBulkSweep: all $Attempted writes failed. $($FailureDetail | Select-Object -First 1)"
    }

    foreach ($CacheType in @($Remediate.refreshCache | Where-Object { $_ })) {
        $Collector = Get-Command -Name "Set-CIPPDBCache$CacheType" -ErrorAction SilentlyContinue
        if (-not $Collector) { continue }
        try {
            $CollectParams = @{ TenantFilter = $TenantFilter }
            foreach ($Argument in ($Remediate.refreshCacheArgs.$CacheType ?? [PSCustomObject]@{}).PSObject.Properties) {
                $CollectParams[$Argument.Name] = $Argument.Value
            }
            $null = & $Collector @CollectParams
        } catch {
            Write-Information "Baselines: cache refresh for $CacheType on $TenantFilter after a sweep failed: $($_.Exception.Message)"
        }
    }
}

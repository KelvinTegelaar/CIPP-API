function Invoke-CIPPBaselineGraphBulkSweep {
    <#
    .SYNOPSIS
        GraphBulkSweep executor: applies one Graph write per object in a prepare hook's
        offender set.
    .DESCRIPTION
        The per-object counterpart to GraphRequest. A sweep standard's prepare hook computes
        WHICH objects are wrong (that part is bespoke - joins, relative-date windows, exclusion
        lists); this applies the SAME write to each of them through $batch, so a tenant with
        900 stale guests costs 45 round trips rather than 900.

        A sweep's prepare hook returns TWO lists, because the compare and the write want
        different shapes:
          offenders - display strings (a UPN, a domain, a group name). This is the property
                      the definition grades against [], so drift reads as a list of names
                      rather than a wall of serialized objects.
          targets   - one object per offender carrying whatever the write needs (id, and any
                      value that varies per object). Not graded: the engine projects Current
                      down to the expected keys, so it never reaches the compare.

        Spec (fully rendered):
          writes[]      - ordered write groups, each { from, method, uri, body, asApp }.
                          'from' names the property on -Current holding the objects (default
                          'targets'); a group whose property does not exist is an authoring
                          error and throws, while one that exists and is empty is simply
                          nothing to do. uri and body may carry %property% tokens resolved
                          against each object, with the engine's token semantics: an exact
                          "%prop%" JSON token keeps the property's type, a bare %prop% inside
                          a longer string interpolates.
          version       - 'beta' (default) or 'v1.0'.
          refreshCache  - cache types to re-collect after a successful sweep, so the objects
                          just fixed do not read back as drift on the next run.

        Partial failure does NOT throw: the objects that were fixed stay fixed, the failures
        are logged, and the next run's compare re-derives the offender set and retries the
        remainder. A sweep where EVERY write failed does throw - that is a permission or
        endpoint problem, and swallowing it would report Remediated forever while nothing
        changed.
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

    $Version = "$($Remediate.version)"
    if ($Version -notin @('beta', 'v1.0')) { $Version = 'beta' }

    $Attempted = 0
    $Failed = 0
    $FailureDetail = [System.Collections.Generic.List[string]]::new()

    foreach ($Write in @($Remediate.writes)) {
        if (-not $Write) { continue }
        $From = "$($Write.from)"
        if ([string]::IsNullOrWhiteSpace($From)) { $From = 'targets' }
        if (-not ($Current -and $Current.PSObject.Properties.Name -contains $From)) {
            throw "GraphBulkSweep: the prepare hook produced no '$From' set to sweep."
        }
        $Objects = @($Current.$From | Where-Object { $_ })
        if ($Objects.Count -eq 0) { continue }

        $Index = 0
        $Requests = foreach ($Object in $Objects) {
            $Request = @{
                # NOT "$($Index++)": an increment inside a subexpression emits NOTHING in
                # PowerShell, which shipped every batch request with an empty id - Graph
                # rejects the whole batch with 'Id property cannot be empty'.
                id     = "$Index"
                method = ($Write.method ?? 'PATCH')
                url    = "/$((& $Expand $Write.uri $Object) -replace '^/')"
            }
            $Index++
            if ($Write.PSObject.Properties.Name -contains 'body' -and $null -ne $Write.body) {
                $Request['body'] = & $Expand $Write.body $Object
                $Request['headers'] = @{ 'Content-Type' = 'application/json' }
            }
            $Request
        }

        $Attempted += $Objects.Count
        $Responses = @(New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp ([bool]($Write.asApp ?? $true)) -Version $Version)
        foreach ($Response in $Responses) {
            if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                $Failed++
                $Target = @($Requests)[[int]$Response.id].url
                $FailureDetail.Add("$Target -> $($Response.status) $($Response.body.error.message)")
            }
        }
    }

    if ($Attempted -eq 0) { return }

    if ($FailureDetail.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Sweep: $Failed of $Attempted writes failed. $($FailureDetail -join ' | ')" -Sev 'Warning'
    }
    if ($Failed -eq $Attempted) {
        throw "GraphBulkSweep: all $Attempted writes failed. $($FailureDetail | Select-Object -First 1)"
    }

    foreach ($CacheType in @($Remediate.refreshCache | Where-Object { $_ })) {
        $Collector = Get-Command -Name "Set-CIPPDBCache$CacheType" -ErrorAction SilentlyContinue
        if (-not $Collector) { continue }
        try { $null = & $Collector -TenantFilter $TenantFilter } catch {
            Write-Information "Baselines: cache refresh for $CacheType on $TenantFilter after a sweep failed: $($_.Exception.Message)"
        }
    }
}

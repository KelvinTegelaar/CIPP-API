function Invoke-ExecNHIRelease {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .SYNOPSIS
        Releases the containment of a non-human identity (NHI) compromise case.
    .DESCRIPTION
        Re-enables what the case disabled and is still in force (containment after the latest release): the app itself, and the apps it created or put credentials on, once they turned out to be clean or their credentials were replaced. Removed credentials, owners and permissions are not restored: the rows say what to re-create by hand. Needs Confirmation: the app's display name or application id. Appends a Release entry to the case's containment history.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $CaseId = [string]$Request.Body.caseId
    # The app's display name or application id, typed to confirm
    $Confirmation = ([string]$Request.Body.Confirmation).Trim()

    try {
        if (-not $TenantFilter -or -not $CaseId) { throw 'tenantFilter and caseId are required' }
        $Run = Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId
        if (-not $Run) { throw "NHI case $CaseId was not found for $TenantFilter" }
        if (-not $Confirmation -or ($Confirmation -ne [string]$Run.DisplayName -and $Confirmation -ne [string]$Run.AppId)) { throw "Type the app's display name or application id to confirm the release" }

        # Only containment after the most recent release is still in force
        $History = @($Run.Containment | Where-Object { $_ })
        $LastRelease = -1
        for ($i = 0; $i -lt $History.Count; $i++) { if ($History[$i].Kind -eq 'Release') { $LastRelease = $i } }
        $InForce = @($History | Select-Object -Skip ($LastRelease + 1) | ForEach-Object { $_.Results } | Where-Object { $_ -and $_.state -eq 'success' })
        if ($InForce.Count -eq 0) { throw "Case $CaseId has no containment in force to release" }

        $Catalog = Get-CIPPNhiContainmentActions
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Action in @($Catalog | Where-Object { $_.Id -in @($InForce.Action) } | Sort-Object -Property Order)) {
            if ($Action.Release -ne 'Reverse') {
                $Rows.Add([pscustomobject]@{ Action = $Action.Id; Target = $Run.DisplayName; state = 'info'; resultText = "$($Action.Label) is not undone by a release$(if ($Action.Release -eq 'Manual') { ': re-create what is still needed by hand' })" })
                continue
            }
            # the app itself, or each app the persistence action disabled
            $Disabled = if ($Action.Id -eq 'DisableServicePrincipal') { @([string]$Run.ServicePrincipalId) } else { @($InForce | Where-Object { $_.Action -eq $Action.Id } | ForEach-Object { [string]$_.Target } | Where-Object { $_ } | Select-Object -Unique) }
            foreach ($TargetId in $Disabled) {
                try {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$TargetId" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":true}' -AsApp $true
                    $Rows.Add([pscustomobject]@{ Action = $Action.Id; Target = $TargetId; state = 'success'; resultText = "Re-enabled $(if ($TargetId -eq $Run.ServicePrincipalId) { $Run.DisplayName } else { $TargetId }) in this tenant" })
                } catch {
                    $Rows.Add([pscustomobject]@{ Action = $Action.Id; Target = $TargetId; state = 'error'; resultText = "Could not re-enable $TargetId`: $((Get-CippException -Exception $_).NormalizedError)" })
                }
            }
        }

        $By = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' }
        $Updated = @($History) + @([pscustomobject]@{ At = (Get-Date).ToUniversalTime().ToString('o'); By = [string]$By; Kind = 'Release'; Actions = @($Rows.Action); Results = $Rows.ToArray() })
        $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Containment = $Updated }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Released the containment of $($Run.DisplayName) [case $CaseId]" -Sev 'Info' -LogData @($Rows)
        $Body = @{ Results = $Rows.ToArray() }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI release failed for case $CaseId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = @([pscustomobject]@{ resultText = "Release failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

function Invoke-ExecNHIContainment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .SYNOPSIS
        Contains the app of a non-human identity (NHI) compromise case.
    .DESCRIPTION
        Runs the selected containment actions (Actions, ids from ListNHIContainmentActions; the default set when empty) on the app of a completed case, with explicit targets in Parameters (CredentialKeyIds, FederatedCredentialIds, OwnerIds, AppRoleAssignmentIds, GrantIds, RoleAssignmentIds, PersistenceServicePrincipalIds, ElevationIds), else the targets the case flagged. Critical actions need Confirmation: the app's display name or application id, typed by the operator. Returns one result row per action and target, and appends them to the case's containment history.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $CaseId = [string]$Request.Body.caseId
    # Action ids; plain strings or { value } options
    $Actions = @($Request.Body.Actions | ForEach-Object { [string]($_.value ?? $_) } | Where-Object { $_ })
    # The app's display name or application id, typed to confirm Critical actions
    $Confirmation = ([string]$Request.Body.Confirmation).Trim()

    try {
        if (-not $TenantFilter -or -not $CaseId) { throw [System.ArgumentException]::new('tenantFilter and caseId are required') }
        $Run = Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId
        if (-not $Run) { throw [System.Management.Automation.ItemNotFoundException]::new("NHI case $CaseId was not found for $TenantFilter") }
        $Confirmed = $Confirmation -and ($Confirmation -eq [string]$Run.DisplayName -or $Confirmation -eq [string]$Run.AppId)
        $Rows = @(Invoke-CIPPNhiContainment -TenantFilter $TenantFilter -CaseId $CaseId -Actions $Actions -Parameters $Request.Body.Parameters -Confirmed:$Confirmed -Headers $Headers -APIName $APIName)
        $Body = @{ Results = $Rows }
        $StatusCode = Get-CippBulkStatusCode -Total $Rows.Count -Failed @($Rows | Where-Object state -EQ 'error').Count
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI containment failed for case $CaseId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = @([pscustomobject]@{ resultText = "Containment failed: $($ErrorMessage.NormalizedError)"; state = 'error' }) }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

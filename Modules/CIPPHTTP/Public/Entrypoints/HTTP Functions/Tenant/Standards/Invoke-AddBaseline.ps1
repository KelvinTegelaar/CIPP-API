function Invoke-AddBaseline {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Creates or updates a baseline. There is no baseline blob: the Baselines
        delta rows (design doc §4.1) are the editable source of truth for every standard's
        configuration, and the BaselineRollouts row (§12.2) holds the baseline-level data -
        name, description, exclusions, alert destinations, and the ordered stage definitions.
        Baselines are reconstructed from those rows on read. The actual write lives in
        New-CIPPBaseline, shared with the community-repo import.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $Saved = New-CIPPBaseline -Baseline $Request.Body -User $User

        Write-LogMessage -headers $Request.Headers -API $APIName -message "Baseline $($Request.Body.templateName) ($($Saved.GUID)) saved; $($Saved.DeltaCount) delta rows written." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = 'Successfully saved the baseline'; Metadata = @{ id = $Saved.GUID; deltas = $Saved.DeltaCount } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to save baseline: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to save baseline: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}

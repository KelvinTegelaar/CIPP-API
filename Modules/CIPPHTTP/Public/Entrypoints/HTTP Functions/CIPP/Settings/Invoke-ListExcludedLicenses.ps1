function Invoke-ListExcludedLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Lists license SKUs that have been excluded from CIPP license counts and reporting.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Table = Get-CIPPTable -TableName ExcludedLicenses
        $Rows = Get-CIPPAzDataTableEntity @Table

        # If no excluded licenses exist, initialize them
        if ($Rows.Count -lt 1) {
            Write-Information 'Excluded licenses table is empty. Initializing from config file.'
            $null = Initialize-CIPPExcludedLicenses -Headers $Headers -APIName $APIName
            $Rows = Get-CIPPAzDataTableEntity @Table
        }

        $Results = @($Rows | ForEach-Object {
            # Normalize ExcludedEverywhere for legacy rows that don't have the property
            if ($null -eq $_.ExcludedEverywhere) {
                $_ | Add-Member -NotePropertyName 'ExcludedEverywhere' -NotePropertyValue $true -Force
            }
            if ($null -eq $_.ShowInLicenseDropdown) {
                $_ | Add-Member -NotePropertyName 'ShowInLicenseDropdown' -NotePropertyValue $false -Force
            }
            $ExclusionType = if ($_.ExcludedEverywhere -eq $true) { 'Excluded Everywhere' } else { 'Excluded from Alerts Only' }
            $_ | Add-Member -NotePropertyName 'ExclusionType' -NotePropertyValue $ExclusionType -Force
            $_
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = "Failed to list excluded licenses. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = [pscustomobject]@{ 'Results' = $Results }
        })
}

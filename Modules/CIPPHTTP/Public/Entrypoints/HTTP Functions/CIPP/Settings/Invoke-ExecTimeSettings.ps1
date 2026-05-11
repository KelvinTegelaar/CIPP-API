function Invoke-ExecTimeSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Timezone = $Request.Body.Timezone.value ?? $Request.Body.Timezone

        if (-not $Timezone) {
            throw 'Timezone is required'
        }

        # Validate the IANA timezone ID is recognised by .NET
        try {
            $null = [TimeZoneInfo]::FindSystemTimeZoneById($Timezone)
        } catch {
            throw "Invalid timezone: '$Timezone' is not a recognised IANA timezone ID"
        }

        $Config = @{
            PartitionKey = 'TimeSettings'
            RowKey       = 'TimeSettings'
            Timezone     = $Timezone
        }

        $ConfigTable = Get-CIPPTable -tablename Config
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force | Out-Null
        $env:CIPP_TIMEZONE = $Timezone

        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Updated time settings: Timezone=$Timezone" -Sev 'Info'

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::OK
                Body       = @{
                    Results  = 'Time settings updated successfully.'
                    Timezone = $Timezone
                }
            })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Failed to update time settings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::BadRequest
                Body       = @{
                    Results = "Failed to update time settings: $($ErrorMessage.NormalizedError)"
                }
            })
    }
}

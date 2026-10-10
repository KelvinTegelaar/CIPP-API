
function Get-CIPPLapsPassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Device,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'Get LAPS Password',

        [Parameter(Mandatory = $false)]
        [object]$Headers
    )

    try {
        $GraphRequest = (New-GraphGetRequest -NoAuthCheck $true -uri "https://graph.microsoft.com/beta/directory/deviceLocalCredentials/$($Device)?`$select=credentials" -tenantid $TenantFilter -ErrorAction Stop).credentials | Select-Object -First 1 | ForEach-Object {
            $PlainText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.passwordBase64))
            $BackupDate = $_.BackupDateTime
            [PSCustomObject]@{
                resultText     = "LAPS password retrieved for $($_.accountName), generated at $BackupDate. Copy the password by clicking the copy button"
                copyField      = $PlainText
                accountName    = $_.accountName
                backupDateTime = $_.BackupDateTime
                state          = 'success'
            }
        }
        if ($GraphRequest) {
            Write-LogMessage -headers $Headers -API $APIName -message "Retrieved LAPS password for $Device" -Sev 'Info' -tenant $TenantFilter
            return $GraphRequest
        } else {
            Write-LogMessage -headers $Headers -API $APIName -message "No LAPS password found for $Device" -Sev 'Info' -tenant $TenantFilter
            return "No LAPS password found for $Device"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not retrieve LAPS password for $Device. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not retrieve LAPS password for $Device. Error: $($ErrorMessage.NormalizedError)"
    }
}


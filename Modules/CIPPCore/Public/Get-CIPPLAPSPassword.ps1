
function Get-CIPPLapsPassword {
    [CmdletBinding()]
    param (
        $device,
        $TenantFilter,
        $APIName = "Get LAPS Password",
        $ExecutingUser
    )

    try {
        $GraphRequest = (New-GraphGetRequest -noauthcheck $true -uri "https://graph.microsoft.com/beta/deviceLocalCredentials/$($device)?`$select=credentials" -tenantid $TenantFilter).credentials | Select-Object -First 1 | ForEach-Object {
            $PlainText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.passwordBase64))
            $date = $_.BackupDateTime
            return  "The password for $($_.AccountName) is $($PlainText) generated at $($date)"
        }
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add OOO for $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not add out of office message for $($userid). Error: $($_.Exception.Message)"
    }
}



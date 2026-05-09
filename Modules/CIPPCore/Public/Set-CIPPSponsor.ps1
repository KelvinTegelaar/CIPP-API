function Set-CIPPSponsor {
    [CmdletBinding()]
    param (
        [Alias('User')]
        [string[]] $Users,
        [string] $Sponsor,
        $TenantFilter,
        $APIName = 'Set Sponsor',
        $Headers
    )

    if ($Users.Count -eq 0) {
        return @()
    }

    $RequestId = 0
    $Requests = foreach ($User in $Users) {
        @{
            id      = ($RequestId++).ToString()
            method  = 'PUT'
            url     = "users/$User/sponsors/`$ref"
            body    = @{ '@odata.id' = "https://graph.microsoft.com/beta/users/$Sponsor" }
            headers = @{ 'Content-Type' = 'application/json' }
        }
    }

    $Responses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests)

    $Results = foreach ($Response in @($Responses)) {
        $ResponseIndex = [int]$Response.id
        $User = $Users[$ResponseIndex]
        $Success = [int]$Response.status -in @(200, 204)
        $ErrorMessage = if ($Response.body.error.message) { $Response.body.error.message } else { "Unknown error (Status: $($Response.status))" }
        $Result = if ($Success) { "Set $User's sponsor to $Sponsor" } else { "Failed to set $User's sponsor: $ErrorMessage" }
        $Severity = if ($Success) { 'Info' } else { 'Error' }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev $Severity

        [pscustomobject]@{
            User    = $User
            Sponsor = $Sponsor
            Success = $Success
            Result  = $Result
            Status  = $Response.status
        }
    }

    return @($Results)
}

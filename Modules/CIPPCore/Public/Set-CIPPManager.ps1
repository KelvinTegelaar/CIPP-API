function Set-CIPPManager {
    [CmdletBinding()]
    param (
        [Alias('User')]
        [string[]] $Users,
        [string] $Manager,
        $TenantFilter,
        $APIName = 'Set Manager',
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
            url     = "users/$User/manager/`$ref"
            body    = @{ '@odata.id' = "https://graph.microsoft.com/beta/users/$Manager" }
            headers = @{ 'Content-Type' = 'application/json' }
        }
    }

    $Responses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests)

    $Results = foreach ($Response in @($Responses)) {
        $ResponseIndex = [int]$Response.id
        $User = $Users[$ResponseIndex]
        $Success = [int]$Response.status -in @(200, 204)
        $ErrorMessage = if ($Response.body.error.message) { $Response.body.error.message } else { "Unknown error (Status: $($Response.status))" }
        $Result = if ($Success) { "Set $User's manager to $Manager" } else { "Failed to set $User's manager: $ErrorMessage" }
        $Severity = if ($Success) { 'Info' } else { 'Error' }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev $Severity

        [pscustomobject]@{
            User    = $User
            Manager = $Manager
            Success = $Success
            Result  = $Result
            Status  = $Response.status
        }
    }

    return @($Results)
}

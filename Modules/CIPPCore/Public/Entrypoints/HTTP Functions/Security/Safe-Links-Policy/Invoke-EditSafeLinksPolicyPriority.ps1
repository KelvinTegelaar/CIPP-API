using namespace System.Net

function Invoke-EditSafeLinksPolicyPriority {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        This function changes the priority of a Safe Links rule.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $RuleName = $Request.Query.RuleName ?? $Request.Body.RuleName
    $Priority = $Request.Query.Priority ?? $Request.Body.Priority

    try {
        if (-not [int]::TryParse($Priority, [ref]$null)) {
            throw "Priority must be an integer value."
        }

        $ExoRequestParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Set-SafeLinksRule'
            cmdParams        = @{
                Identity = $RuleName
                Priority = [int]$Priority
            }
            useSystemMailbox = $true
        }

        $null = New-ExoRequest @ExoRequestParam

        $Result = "Successfully set SafeLinks rule $($RuleName) to $($Priority)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed setting SafeLinks rule $($RuleName) to $($Priority). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

using namespace System.Net

function Invoke-ExecDeleteSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        This function deletes a Safe Links rule and its associated policy.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $RuleName = $Request.Query.RuleName ?? $Request.Body.RuleName
    $PolicyName = $Request.Query.PolicyName ?? $Request.Body.PolicyName

    try {
        # First delete the rule
        $ExoRequestRuleParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Remove-SafeLinksRule'
            cmdParams        = @{
                Identity = $RuleName
                Confirm  = $false
            }
            useSystemMailbox = $true
        }

        $null = New-ExoRequest @ExoRequestRuleParam

        # Then delete the policy
        $ExoRequestPolicyParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Remove-SafeLinksPolicy'
            cmdParams        = @{
                Identity = $PolicyName
                Confirm  = $false
            }
            useSystemMailbox = $true
        }

        $null = New-ExoRequest @ExoRequestPolicyParam

        $Result = "Successfully deleted SafeLinks rule '$RuleName' and policy '$PolicyName'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed deleting SafeLinks rule '$RuleName' and policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

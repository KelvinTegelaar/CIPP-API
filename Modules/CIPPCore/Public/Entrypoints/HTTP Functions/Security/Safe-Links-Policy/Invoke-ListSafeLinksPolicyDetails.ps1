using namespace System.Net

function Invoke-ListSafeLinksPolicyDetails {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        This function retrieves details for a specific Safe Links policy and rule.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyName = $Request.Query.PolicyName ?? $Request.Body.PolicyName
    $RuleName = $Request.Query.RuleName ?? $Request.Body.RuleName

    try {
        # Get policy details
        $PolicyRequestParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Get-SafeLinksPolicy'
            cmdParams        = @{
                Identity = $PolicyName
            }
            useSystemMailbox = $true
        }

        $PolicyDetails = New-ExoRequest @PolicyRequestParam

        # Get rule details
        $RuleRequestParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Get-SafeLinksRule'
            cmdParams        = @{
                Identity = $RuleName
            }
            useSystemMailbox = $true
        }

        $RuleDetails = New-ExoRequest @RuleRequestParam

        # Combine policy and rule details
        $Result = @{
            Policy = $PolicyDetails
            Rule   = $RuleDetails
            PolicyName = $PolicyDetails.Name
            RuleName   = $RuleDetails.Name
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully retrieved details for SafeLinks policy '$PolicyName' and rule '$RuleName'" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed retrieving details for SafeLinks policy '$PolicyName' and rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

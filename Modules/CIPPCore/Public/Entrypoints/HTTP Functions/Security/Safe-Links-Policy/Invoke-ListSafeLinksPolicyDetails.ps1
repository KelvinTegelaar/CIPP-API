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

    $Result = @{}
    $LogMessages = [System.Collections.ArrayList]@()

    try {
        # Get policy details if PolicyName is provided
        if ($PolicyName) {
            try {
                $PolicyRequestParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'Get-SafeLinksPolicy'
                    cmdParams        = @{
                        Identity = $PolicyName
                    }
                    useSystemMailbox = $true
                }
                $PolicyDetails = New-ExoRequest @PolicyRequestParam
                $Result.Policy = $PolicyDetails
                $Result.PolicyName = $PolicyDetails.Name
                $LogMessages.Add("Successfully retrieved details for SafeLinks policy '$PolicyName'") | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully retrieved details for SafeLinks policy '$PolicyName'" -Sev 'Info'
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                $LogMessages.Add("Failed to retrieve details for SafeLinks policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)") | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to retrieve details for SafeLinks policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)" -Sev 'Warning'
                $Result.PolicyError = "Failed to retrieve: $($ErrorMessage.NormalizedError)"
            }
        }
        else {
            $LogMessages.Add("No policy name provided, skipping policy retrieval") | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "No policy name provided, skipping policy retrieval" -Sev 'Info'
        }

        # Get rule details if RuleName is provided
        if ($RuleName) {
            try {
                $RuleRequestParam = @{
                    tenantid         = $TenantFilter
                    cmdlet           = 'Get-SafeLinksRule'
                    cmdParams        = @{
                        Identity = $RuleName
                    }
                    useSystemMailbox = $true
                }
                $RuleDetails = New-ExoRequest @RuleRequestParam
                $Result.Rule = $RuleDetails
                $Result.RuleName = $RuleDetails.Name
                $LogMessages.Add("Successfully retrieved details for SafeLinks rule '$RuleName'") | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully retrieved details for SafeLinks rule '$RuleName'" -Sev 'Info'
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                $LogMessages.Add("Failed to retrieve details for SafeLinks rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)") | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to retrieve details for SafeLinks rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)" -Sev 'Warning'
                $Result.RuleError = "Failed to retrieve: $($ErrorMessage.NormalizedError)"
            }
        }
        else {
            $LogMessages.Add("No rule name provided, skipping rule retrieval") | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "No rule name provided, skipping rule retrieval" -Sev 'Info'
        }

        # If no valid retrievals were performed, throw an error
        if (-not ($Result.Policy -or $Result.Rule)) {
            throw "No valid policy or rule details could be retrieved"
        }

        # Set success status
        $StatusCode = [HttpStatusCode]::OK
        $Result.Message = $LogMessages -join " | "
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Operation failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

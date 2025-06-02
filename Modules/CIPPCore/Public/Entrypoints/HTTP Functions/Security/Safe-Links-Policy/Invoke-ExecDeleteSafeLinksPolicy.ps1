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

    $ResultMessages = @()

    try {
        # Only try to delete the rule if a name was provided
        if ($RuleName) {
            try {
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
                $ResultMessages += "Successfully deleted SafeLinks rule '$RuleName'"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully deleted SafeLinks rule '$RuleName'" -Sev 'Info'
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                $ResultMessages += "Failed to delete SafeLinks rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete SafeLinks rule '$RuleName'. Error: $($ErrorMessage.NormalizedError)" -Sev 'Warning'
            }
        }
        else {
            $ResultMessages += "No rule name provided, skipping rule deletion"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "No rule name provided, skipping rule deletion" -Sev 'Info'
        }

        # Only try to delete the policy if a name was provided
        if ($PolicyName) {
            try {
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
                $ResultMessages += "Successfully deleted SafeLinks policy '$PolicyName'"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully deleted SafeLinks policy '$PolicyName'" -Sev 'Info'
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                $ResultMessages += "Failed to delete SafeLinks policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete SafeLinks policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)" -Sev 'Warning'
            }
        }
        else {
            $ResultMessages += "No policy name provided, skipping policy deletion"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "No policy name provided, skipping policy deletion" -Sev 'Info'
        }

        # Combine all result messages
        $Result = $ResultMessages -join " | "
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "An unexpected error occurred: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

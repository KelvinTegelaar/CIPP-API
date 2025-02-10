using namespace System.Net

Function Invoke-ExecGroupsHideFromGAL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    Try {
        $GroupStatus = Set-CIPPGroupGAL -Id $Request.query.id -tenantFilter $Request.query.TenantFilter -GroupType $Request.query.groupType -HiddenString $Request.query.HidefromGAL -APIName $APINAME -Headers $Request.Headers
        $Results = [pscustomobject]@{'Results' = $GroupStatus }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($tenantfilter) -message "Hide/UnHide from GAL failed: $($_.Exception.Message)" -Sev 'Error'
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}

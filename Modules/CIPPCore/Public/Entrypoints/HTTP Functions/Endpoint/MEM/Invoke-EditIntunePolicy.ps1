using namespace System.Net

Function Invoke-EditIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $DisplayName = $Request.Query.newDisplayName ?? $Request.Body.newDisplayName
    $PolicyType = $Request.Query.policyType ?? $Request.Body.policyType

    try {
        $properties = @{}

        # Only add displayName if it's provided
        if ($DisplayName) {
            $properties["displayName"] = $DisplayName
        }

        # Update the policy
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$ID" -tenantid $TenantFilter -type PATCH -body ($properties | ConvertTo-Json) -asapp $true

        $Result = "Successfully updated Intune policy $($ID)"
        if ($DisplayName) { $Result += " name to '$($DisplayName)'" }

        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update Intune policy $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}

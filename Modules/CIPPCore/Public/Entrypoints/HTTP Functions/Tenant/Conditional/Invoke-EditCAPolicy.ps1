using namespace System.Net

Function Invoke-EditCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the request
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.GUID ?? $Request.Body.GUID
    $State = $Request.Query.State ?? $Request.Body.State
    $DisplayName = $Request.Query.newDisplayName ?? $Request.Body.newDisplayName

    try {
        $properties = @{}

        # Conditionally add properties
        if ($State) {
            $properties["state"] = $State
        }

        if ($DisplayName) {
            $properties["displayName"] = $DisplayName
        }

        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta//identity/conditionalAccess/policies/$($ID)" -tenantid $TenantFilter -type PATCH -body ($properties | ConvertTo-Json) -asapp $true

        $Result = "Successfully updated CA policy $($ID)"
        if ($State) { $Result += " state to $($State)" }
        if ($DisplayName) { $Result += " name to '$($DisplayName)'" }

        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update CA policy $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}

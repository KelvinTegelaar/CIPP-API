function Invoke-EditIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $ID = $Request.Body.ID
    $DisplayName = $Request.Body.newDisplayName
    $PolicyType = $Request.Body.policyType
    $PlatformType = $Request.Body.platformType ?? 'deviceManagement'

    # The description is optional and may be sent as an empty string to clear it,
    # so track whether the caller actually supplied the key.
    $DescriptionProvided = $Request.Body.PSObject.Properties.Name -contains 'description'
    $Description = $Request.Body.description

    try {
        # App protection policy lists expose the singular @odata.type as the URLName, but a
        # Graph PATCH needs the plural collection segment. Normalize the known types here.
        $PolicyType = switch ($PolicyType) {
            'androidManagedAppProtection' { 'androidManagedAppProtections' }
            'iosManagedAppProtection' { 'iosManagedAppProtections' }
            'windowsManagedAppProtection' { 'windowsManagedAppProtections' }
            'mdmWindowsInformationProtectionPolicy' { 'mdmWindowsInformationProtectionPolicies' }
            'windowsInformationProtectionPolicy' { 'windowsInformationProtectionPolicies' }
            'targetedManagedAppConfiguration' { 'targetedManagedAppConfigurations' }
            default { $PolicyType }
        }

        $properties = @{}

        # Settings catalog policies (configurationPolicies) store the name in the 'name'
        # property rather than 'displayName'.
        $NameProperty = if ($PolicyType -ieq 'configurationPolicies') { 'name' } else { 'displayName' }

        # Only add the name if it's provided
        if ($DisplayName) {
            $properties[$NameProperty] = $DisplayName
        }

        # Only add description if the caller supplied it (empty string clears it)
        if ($DescriptionProvided) {
            $properties['description'] = $Description
        }

        # Update the policy
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$PolicyType/$ID" -tenantid $TenantFilter -type PATCH -body ($properties | ConvertTo-Json) -asapp $true

        $Result = "Successfully updated Intune policy $($ID)"
        if ($DisplayName) { $Result += " name to '$($DisplayName)'" }
        if ($DescriptionProvided) { $Result += ' and description' }

        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update Intune policy $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}

function Invoke-AddIntunePolicyClone {
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

    # Interact with the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $ID = $Request.Body.ID
    $URLName = $Request.Body.URLName
    $ODataType = $Request.Body.ODataType
    $NewDisplayName = $Request.Body.newDisplayName
    $NewDescription = $Request.Body.newDescription

    try {
        if ([string]::IsNullOrWhiteSpace($NewDisplayName)) { throw 'You must enter a display name for the cloned policy' }

        # Export the source policy to template JSON; this strips read-only properties per policy type.
        $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $ID -ODataType $ODataType
        if (-not $Template.TemplateJson) { throw "Policy type '$($URLName ?? $ODataType)' is not supported for cloning" }

        # Set-CIPPIntunePolicy updates an existing policy when the display name matches, so a clone
        # that keeps the source name would overwrite the source policy instead of creating a copy.
        if ($NewDisplayName -eq $Template.DisplayName) { throw 'The new display name must be different from the name of the policy you are cloning' }

        $Description = $NewDescription ?? $Template.Description

        # Several policy types take their name and description from the JSON payload rather than the
        # parameters, so rewrite them in the payload too. Admin (groupPolicyConfigurations) template
        # JSON holds definition values rather than the policy object and must stay untouched.
        $RawJSON = $Template.TemplateJson
        if ($Template.Type -ne 'Admin') {
            $PolicyObject = $RawJSON | ConvertFrom-Json
            $NameProperty = if ($Template.Type -eq 'Catalog') { 'name' } else { 'displayName' }
            $PolicyObject | Add-Member -MemberType NoteProperty -Name $NameProperty -Value $NewDisplayName -Force
            $PolicyObject | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force
            $RawJSON = ConvertTo-Json -InputObject $PolicyObject -Depth 100 -Compress
        }

        $null = Set-CIPPIntunePolicy -TemplateType $Template.Type -Description $Description -DisplayName $NewDisplayName -RawJSON $RawJSON -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName

        $Result = "Successfully cloned Intune policy '$($Template.DisplayName)' to '$($NewDisplayName)'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to clone Intune policy $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}

function Invoke-AddIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $GUID = (New-Guid).GUID
    try {
        if ($Request.Body.RawJSON) {
            if (!$Request.Body.displayName) { throw 'You must enter a displayName' }
            if ($null -eq ($Request.Body.RawJSON | ConvertFrom-Json)) { throw 'the JSON is invalid' }

            $reusableTemplateRefs = @()
            $object = [PSCustomObject]@{
                Displayname      = $Request.Body.displayName
                Description      = $Request.Body.description
                RAWJson          = $Request.Body.RawJSON
                Type             = $Request.Body.TemplateType
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON                  = "$object"
                ReusableSettingsCount = $reusableTemplateRefs.Count
                RowKey                = "$GUID"
                PartitionKey          = 'IntuneTemplate'
                GUID                  = "$GUID"
            }
            Write-LogMessage -headers $Headers -API $APIName -message "Created intune policy template named $($Request.Body.displayName) with GUID $GUID" -Sev 'Debug'

            $Result = 'Successfully added template'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
            $URLName = $Request.Body.URLName ?? $Request.Query.URLName
            $ID = $Request.Body.ID ?? $Request.Query.ID
            $ODataType = $Request.Body.ODataType ?? $Request.Query.ODataType
            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $ID -ODataType $ODataType

            $reusableResult = Get-CIPPReusableSettingsFromPolicy -PolicyJson $Template.TemplateJson -Tenant $TenantFilter -Headers $Headers -APIName $APIName
            $reusableTemplateRefs = $reusableResult.ReusableSettings

            $object = [PSCustomObject]@{
                Displayname      = $Template.DisplayName
                Description      = $Template.Description
                RAWJson          = $Template.TemplateJson
                Type             = $Template.Type
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json -Compress
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
            }
            Write-LogMessage -headers $Headers -API $APIName -message "Created intune policy template $($Request.Body.displayName) with GUID $GUID using an original policy from a tenant" -Sev 'Debug'

            $Result = 'Successfully added template'
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Intune Template Deployment failed: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

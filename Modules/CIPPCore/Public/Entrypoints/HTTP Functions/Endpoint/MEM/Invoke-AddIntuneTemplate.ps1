using namespace System.Net

Function Invoke-AddIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $GUID = (New-Guid).GUID
    try {
        if ($Request.Body.RawJSON) {
            if (!$Request.Body.displayName) { throw 'You must enter a displayname' }
            if ($null -eq ($Request.Body.RawJSON | ConvertFrom-Json)) { throw 'the JSON is invalid' }


            $object = [PSCustomObject]@{
                Displayname = $Request.Body.displayName
                Description = $Request.Body.description
                RAWJson     = $Request.Body.RawJSON
                Type        = $Request.Body.TemplateType
                GUID        = $GUID
            } | ConvertTo-Json
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
            }
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Created intune policy template named $($Request.Body.displayName) with GUID $GUID" -Sev 'Debug'

            $body = [pscustomobject]@{'Results' = 'Successfully added template' }
        } else {
            $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
            $URLName = $Request.Body.URLName ?? $Request.Query.URLName
            $ID = $Request.Body.ID ?? $Request.Query.ID
            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $ID
            Write-Host "Template: $Template"
            $object = [PSCustomObject]@{
                Displayname = $Template.DisplayName
                Description = $Template.Description
                RAWJson     = $Template.TemplateJson
                Type        = $Template.Type
                GUID        = $GUID
            } | ConvertTo-Json
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
            }
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Created intune policy template $($Request.Body.displayName) with GUID $GUID using an original policy from a tenant" -Sev 'Debug'

            $body = [pscustomobject]@{'Results' = 'Successfully added template' }
        }
    } catch {
        Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message "Intune Template Deployment failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Intune Template Deployment failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}

using namespace System.Net

function Invoke-AddGroupTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $GUID = $Request.Body.GUID ?? (New-Guid).GUID
    try {
        if (!$Request.Body.displayname) { throw 'You must enter a displayname' }

        $object = [PSCustomObject]@{
            displayName     = $Request.Body.displayName
            description     = $Request.Body.description
            groupType       = $Request.Body.groupType
            membershipRules = $Request.Body.membershipRules
            allowExternal   = $Request.Body.allowExternal
            username        = $Request.Body.username
            GUID            = $GUID
        } | ConvertTo-Json
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            JSON         = "$object"
            RowKey       = "$GUID"
            PartitionKey = 'GroupTemplate'
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created Group template named $($Request.Body.displayname) with GUID $GUID" -Sev 'Debug'

        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Group Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Group Template Creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}

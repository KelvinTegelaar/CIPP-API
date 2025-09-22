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
        if (!$Request.Body.displayName) {
            throw 'You must enter a displayname'
        }

        # Normalize group type to match New-CIPPGroup expectations (handle both camelCase and lowercase)
        $groupType = switch -wildcard ($Request.Body.groupType.ToLower()) {
            '*dynamicdistribution*' { 'dynamicDistribution'; break }  # Check this first before *dynamic* and *distribution*
            '*dynamic*' { 'dynamic'; break }
            '*azurerole*' { 'azureRole'; break }
            '*unified*' { 'm365'; break }
            '*microsoft*' { 'm365'; break }
            '*m365*' { 'm365'; break }
            '*generic*' { 'generic'; break }
            '*security*' { 'security'; break }
            '*distribution*' { 'distribution'; break }
            '*mail*' { 'distribution'; break }
            default { $Request.Body.groupType }
        }

        # Override to dynamic if membership rules are provided (for backward compatibility)
        # but only if it's not already a dynamicDistribution group
        if ($Request.body.membershipRules -and $groupType -notin @('dynamicDistribution')) {
            $groupType = 'dynamic'
        }
        # Normalize field names to handle different casing from various forms
        $displayName = $Request.Body.displayName ?? $Request.Body.Displayname ?? $Request.Body.displayname
        $description = $Request.Body.description ?? $Request.Body.Description

        $object = [PSCustomObject]@{
            displayName     = $displayName
            description     = $description
            groupType       = $groupType
            membershipRules = $Request.Body.membershipRules
            allowExternal   = $Request.Body.allowExternal
            username        = $Request.Body.username  # Can contain variables like @%tenantfilter%
            GUID            = $GUID
        } | ConvertTo-Json
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            JSON         = "$object"
            RowKey       = "$GUID"
            PartitionKey = 'GroupTemplate'
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created Group template named $displayName with GUID $GUID" -Sev 'Debug'

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

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
        $groupType = switch -wildcard ($Request.Body.groupType) {
            '*dynamic*' { 'dynamic' }
            '*azurerole*' { 'azurerole' }
            '*unified*' { 'm365' }
            '*Microsoft*' { 'm365' }
            '*generic*' { 'generic' }
            '*mail*' { 'mailenabledsecurity' }
            '*Distribution*' { 'distribution' }
            '*security*' { 'security' }
            default { $Request.Body.groupType }
        }
        if ($Request.Body.membershipRules) { $groupType = 'dynamic' }
        $object = [PSCustomObject]@{
            displayName     = $Request.Body.displayName
            description     = $Request.Body.description
            groupType       = $groupType
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
        Write-LogMessage -headers $Headers -API $APIName -message "Created Group template named $($Request.Body.displayname) with GUID $GUID" -Sev 'Debug'

        $Results = 'Successfully added template'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Group Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = "Group Template Creation failed: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}

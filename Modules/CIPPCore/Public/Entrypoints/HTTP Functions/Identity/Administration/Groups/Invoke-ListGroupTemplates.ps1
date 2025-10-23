function Invoke-ListGroupTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    Write-Host $Request.query.id

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'GroupTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json

        # Normalize groupType to camelCase for consistent frontend handling
        # Handle both stored normalized values and legacy values
        $normalizedGroupType = switch -Wildcard ($data.groupType.ToLower()) {
            # Already normalized values (most common)
            'dynamicdistribution' { 'dynamicDistribution'; break }
            'azurerole' { 'azureRole'; break }
            # Legacy values that might exist in stored templates
            '*dynamicdistribution*' { 'dynamicDistribution'; break }
            '*dynamic*' { 'dynamic'; break }
            '*azurerole*' { 'azureRole'; break }
            '*unified*' { 'm365'; break }
            '*microsoft*' { 'm365'; break }
            '*m365*' { 'm365'; break }
            '*generic*' { 'generic'; break }
            '*security*' { 'security'; break }
            '*distribution*' { 'distribution'; break }
            '*mail*' { 'distribution'; break }
            default { $data.groupType }
        }

        [PSCustomObject]@{
            displayName     = $data.displayName
            description     = $data.description
            groupType       = $normalizedGroupType
            membershipRules = $data.membershipRules
            allowExternal   = $data.allowExternal
            username        = $data.username
            GUID            = $_.RowKey
        }
    } | Sort-Object -Property displayName

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
